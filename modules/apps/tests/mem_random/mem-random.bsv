//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

import FIFO::*;
import FIFOF::*;
import LFSR::*;
import ConfigReg::*;
import DefaultValue::*;


`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/mem_services.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/fpga_components.bsh"

`include "awb/dict/VDEV_SCRATCH.bsh"
`include "awb/dict/PARAMS_HARDWARE_SYSTEM.bsh"

// It is normally NOT necessary to include scratchpad_memory.bsh to use
// scratchpads.  mem-random includes it only to get the value of
// SCRATCHPAD_MEM_VALUE in order to pick data sizes that will force
// maximum pressure on the host memory.
`include "awb/provides/scratchpad_memory.bsh"



//
// Send random read/write requests to a scratchpad.  A parallel set of requests
// is also sent to a local block RAM and the two are compared.
//


typedef enum
{
    STATE_init,
    STATE_run,
    STATE_finished,
    STATE_wait,
    STATE_exit
}
STATE
    deriving (Bits, Eq);


typedef Bit#(64) CYCLE_COUNTER;

//
// The scratchpad and the block RAM can have different address spaces so
// that a large scratchpad region can be tested using a block RAM that fits
// on the FPGA.  There has to be a 1:1 correspondence between the subset
// of the scratchpad that is used and the block RAM.  The mapping is handled
// in testAddrToScratchAddr() below.  Having this mapping can be useful for
// testing system features such as page-based virtual to physical translation
// where a large number of pages have to be touched.
//
typedef Bit#(28) SCRATCH_ADDRESS;
typedef Bit#(13) MEM_ADDRESS;

module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate scratchpad
    //
    SCRATCHPAD_CONFIG sconf = defaultValue;
    sconf.requestMerging = (`MEM_TEST_REQUEST_MERGING != 0);
    sconf.cacheMode = (`MEM_TEST_PRIVATE_CACHES != 0 ? SCRATCHPAD_CACHED :
                                                       SCRATCHPAD_NO_PVT_CACHE);

    // Large data (multiple containers for single datum)
    MEMORY_IFC#(SCRATCH_ADDRESS, SCRATCHPAD_MEM_VALUE) memory <-
        mkScratchpad(`VDEV_SCRATCH_MEMTEST_RANDOM, sconf);

    DEBUG_FILE debugLog <- mkDebugFile("mem_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Test cycles
    Param#(64) testCycles <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_MEM_TEST_CYCLES, paramNode);
    Reg#(Bit#(64))maxCycles <- mkConfigRegU();

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(CYCLE_COUNTER) cycle <- mkConfigReg(0);
    Reg#(STATE) state <- mkConfigReg(STATE_init);

    Reg#(MEM_ADDRESS) addr <- mkReg(0);

    // Random number generators
    LFSR#(Bit#(32)) lfsrRdA <- mkLFSR_32();

    LFSR#(Bit#(32)) lfsrWrA <- mkLFSR_32();
    LFSR#(Bit#(32)) lfsrWrD <- mkLFSR_32();

    Reg#(Bit#(64)) nReadReqs <- mkConfigReg(0);
    Reg#(Bit#(64)) nReadRsps <- mkConfigReg(0);
    Reg#(Bit#(64)) nWrites <- mkConfigReg(0);

    Reg#(Bit#(32)) nErrors <- mkConfigReg(0);

    // ====================================================================
    //
    // Messages and printing.
    //
    // ====================================================================

    let msgStart <- getGlobalStringUID("memtest: starting\n");
    let msgError <- getGlobalStringUID("ERROR: Read 0x%08x, expected 0x%08x\n");
    let msgDone <- getGlobalStringUID("memtest: done\n");
    let msgReadsDone <- getGlobalStringUID("memtest: all reads done\n");
    let msgStatus <- getGlobalStringUID("Completed %lld read req, %lld read rsp, %lld writes, %lld errors\n");

    (* fire_when_enabled *)
    rule printStatus ((state == STATE_run) && (cycle[32:0] == 0));
        stdio.printf(msgStatus,
                     list(nReadReqs, nReadRsps, nWrites, zeroExtend(nErrors)));
    endrule

    (* fire_when_enabled *)
    rule cycleCount (state != STATE_init);
        cycle <= cycle + 1;

        lfsrRdA.next();

        lfsrWrA.next();
        lfsrWrD.next();
    endrule


    // ====================================================================
    //
    // Control logic.
    //
    // ====================================================================

    rule doInit (state == STATE_init);
        linkStarterStartRun.deq();
        stdio.printf(msgStart, List::nil);

        lfsrRdA.seed(1);

        lfsrWrA.seed(29);
        lfsrWrD.seed(33);

        cycle <= 0;
        maxCycles <= testCycles;

        state <= STATE_run;
    endrule

    rule run (state == STATE_run);
        if (cycle >= maxCycles)
        begin
            state <= STATE_finished;
        end
    endrule

    rule sendDone (state == STATE_finished);
        stdio.printf(msgDone, List::nil);
        state <= STATE_wait;
    endrule

    rule waitForReads ((state == STATE_wait) && (nReadReqs == nReadRsps));
        stdio.printf(msgReadsDone, List::nil);
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule



    // ====================================================================
    //
    // Convert from the dense testing address space to the scratchpad
    // address space.  The conversion may map to more pages in order
    // to test virtual to physical translation, or whatever else is
    // needed.  The mapping may then use only a few entries on each
    // page.
    //
    // ====================================================================

    function SCRATCH_ADDRESS testAddrToScratchAddr(MEM_ADDRESS mAddr)
        provisos (Bits#(SCRATCH_ADDRESS, t_SCRATCH_ADDRESS_SZ),
                  Bits#(MEM_ADDRESS, t_MEM_ADDRESS_SZ));
        Bit#(TSub#(t_SCRATCH_ADDRESS_SZ, t_MEM_ADDRESS_SZ)) pad = 0;
        return {mAddr, pad};
    endfunction


    // ====================================================================
    //
    // Test memory (BRAM) for comparing against system memory.
    //
    // ====================================================================

    MEMORY_IFC#(MEM_ADDRESS, Bit#(32)) bram <- mkBRAMInitialized(0);

    // Buffer BRAM read responses in a big FIFO so reads can have latency
    // like host memory.
    FIFOF#(Bit#(32)) bramRdFIFO <- mkSizedBRAMFIFOF(512);

    rule bramReadBuffer (True);
        let v <- bram.readRsp();
        bramRdFIFO.enq(v);
    endrule


    // ====================================================================
    //
    // Write values into memory
    //
    // ====================================================================

    rule doWrite (state == STATE_run);
        MEM_ADDRESS m_addr = truncate(lfsrWrA.value);

        let s_addr = testAddrToScratchAddr(m_addr);
        let v = lfsrWrD.value;

        nWrites <= nWrites + 1;
        memory.write(s_addr, zeroExtend(v));
        bram.write(m_addr, v);

        debugLog.record($format("write: addr 0x%x, data 0x%x", s_addr, v));
    endrule
    

    // ====================================================================
    //
    // Read from memory
    //
    // ====================================================================

    rule doReadReq (state == STATE_run);
        MEM_ADDRESS m_addr = truncate(lfsrRdA.value);

        let s_addr = testAddrToScratchAddr(m_addr);

        nReadReqs <= nReadReqs + 1;
        memory.readReq(s_addr);
        bram.readReq(m_addr);

        debugLog.record($format("read req: addr 0x%x", s_addr));
    endrule
    
    (* descending_urgency = "doInit, doReadRsp" *)
    (* descending_urgency = "sendDone, doReadRsp" *)
    (* descending_urgency = "printStatus, doReadRsp" *)
    (* descending_urgency = "doReadRsp, waitForReads" *)
    rule doReadRsp (True);
        let v <- memory.readRsp();
        nReadRsps <= nReadRsps + 1;

        let check = bramRdFIFO.first();
        bramRdFIFO.deq();

        if (truncate(v) != check)
        begin
            nErrors <= nErrors + 1;

            debugLog.record($format("ERROR: Read 0x%x, expected 0x%x", v[31:0], check));
            stdio.printf(msgError, list(zeroExtend(v[31:0]), zeroExtend(check)));
        end

        debugLog.record($format("read rsp: data 0x%x", v[31:0]));
    endrule

endmodule
