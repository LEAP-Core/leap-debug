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
import Vector::*;
import GetPut::*;
import LFSR::*;
import DefaultValue::*;


`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/mem_services.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/dict/VDEV_SCRATCH.bsh"
`include "awb/dict/PARAMS_HARDWARE_SYSTEM.bsh"

// It is normally NOT necessary to include scratchpad_memory.bsh to use
// scratchpads.  mem-test includes it only to get the value of
// SCRATCHPAD_MEM_VALUE in order to pick data sizes that will force
// the three possible container scenarios:  multiple containers per
// datum, one container per datum, multiple data per container.
`include "awb/provides/scratchpad_memory.bsh"

`define START_ADDR 0
`define LAST_ADDR  'h1ff

// `define DISABLE_HEAP 1

typedef enum
{
    STATE_init,
    STATE_writing,
    STATE_read_random,
    STATE_read_sequential,
    STATE_read_timing,
    STATE_read_timing_emit,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);


typedef Bit#(32) CYCLE_COUNTER;

// Test that complex types can be passed to mkMemPack
typedef struct
{
    Bit#(10) x;
}
MEM_DATA_SM
    deriving (Bits, Eq);

typedef Bit#(13) MEM_ADDRESS;

module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),

              // Large data (multiple containers for single datum)
              Alias#(Int#(TAdd#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA_LG),

              // Medium data (same container size as data)
              Alias#(Bit#(TSub#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA_MD),

              // Small data (multiple data per container)
              Alias#(MEM_DATA_SM, t_MEM_DATA_SM));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate scratchpads
    //
    SCRATCHPAD_CONFIG sconf = defaultValue;
    sconf.requestMerging = (`MEM_TEST_REQUEST_MERGING != 0);
    sconf.cacheMode = (`MEM_TEST_PRIVATE_CACHES != 0 ? SCRATCHPAD_CACHED :
                                                       SCRATCHPAD_NO_PVT_CACHE);

    // Large data (multiple containers for single datum)
    MEMORY_IFC#(MEM_ADDRESS, t_MEM_DATA_LG) memoryLG <-
        mkScratchpad(`VDEV_SCRATCH_MEMTEST_LG, sconf);

    // Medium data (same container size as data)
    MEMORY_IFC#(MEM_ADDRESS, t_MEM_DATA_MD) memoryMD <-
        mkScratchpad(`VDEV_SCRATCH_MEMTEST_MD, sconf);

    // Small data (multiple data per container)
    MEMORY_IFC#(MEM_ADDRESS, t_MEM_DATA_SM) memorySM <-
        mkScratchpad(`VDEV_SCRATCH_MEMTEST_SM, sconf);

    // Heap
`ifndef DISABLE_HEAP
    MEMORY_HEAP#(MEM_ADDRESS, t_MEM_DATA_SM) heap <-
        mkMemoryHeapUnionScratchpad(`VDEV_SCRATCH_MEMTEST_HEAP, sconf);
`endif

    DEBUG_FILE debugLog <- mkDebugFile("mem_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Memory initialization (write) modes:
    //  0 -- normal
    //  1 -- write zeros
    //  2 -- no writes
    Param#(2) memInitMode <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_MEM_TEST_INIT_MODE, paramNode);

    // Verbose mode
    //  0 -- quiet
    //  1 -- verbose
    Param#(1) verboseMode <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_MEM_TEST_VERBOSE, paramNode);
    let verbose = verboseMode == 1;

    // Heap enable -- allow heap tests?  Skip heap case (it used to cause deadlocks).
    //  0 -- disable
    //  1 -- enable
    Param#(1) heapTestMode <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_MEM_TEST_HEAP, paramNode);
`ifndef DISABLE_HEAP
    Bool enableHeap = heapTestMode == 1;
`else
    Bool enableHeap = False;
`endif

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(CYCLE_COUNTER) cycle <- mkReg(0);
    Reg#(STATE) state <- mkReg(STATE_init);

    Reg#(MEM_ADDRESS) addr <- mkReg(`START_ADDR);

    // Random number generator
    LFSR#(Bit#(16)) lfsr <- mkLFSR_16();

    Reg#(Bit#(2)) nCompleteReads <- mkRegU();

    // If not doing heap tests then mark heap test done already
    function Bit#(2) completeReadsInitVal() = enableHeap ? 0 : 1;

    // ====================================================================
    //
    // Messages and printing.
    //
    // ====================================================================

    let msgStart <- getGlobalStringUID("memtest: starting\n");
    let msgWritesDone <- getGlobalStringUID("memtest: writes complete\n");
    let msgData <- getGlobalStringUID("mem%s [0x%8x] = 0x%08x\n");
    let msgDataErr <- getGlobalStringUID("mem%s [0x%8x] = 0x%08x  ERROR\n");
    let msgLG <- getGlobalStringUID("LG");
    let msgMD <- getGlobalStringUID("MD");
    let msgSM <- getGlobalStringUID("SM");
    let msgH  <- getGlobalStringUID("H ");
    let msgLatency <- getGlobalStringUID("latency (4 loads, 2 bytes per load) = 0x%016llx\n                                      0x%016llx\n");
    let msgDone <- getGlobalStringUID("memtest: done\n");

    FIFO#(Tuple3#(GLOBAL_STRING_UID, MEM_ADDRESS, t_MEM_DATA_LG)) memLGPrintQ <- mkFIFO();
    FIFO#(Tuple3#(GLOBAL_STRING_UID, MEM_ADDRESS, t_MEM_DATA_MD)) memMDPrintQ <- mkFIFO();
    FIFO#(Tuple3#(GLOBAL_STRING_UID, MEM_ADDRESS, t_MEM_DATA_SM)) memSMPrintQ <- mkFIFO();
    FIFO#(Tuple3#(GLOBAL_STRING_UID, MEM_ADDRESS, t_MEM_DATA_SM)) memHPrintQ <- mkFIFO();

    rule doPrintLG (True);
        match {.msg, .r_addr, .v} = memLGPrintQ.first();
        memLGPrintQ.deq();

        stdio.printf(msg, list3(zeroExtend(msgLG), zeroExtend(r_addr), resize(pack(v))));
    endrule

    rule doPrintMD (True);
        match {.msg, .r_addr, .v} = memMDPrintQ.first();
        memMDPrintQ.deq();

        stdio.printf(msg, list3(zeroExtend(msgMD), zeroExtend(r_addr), resize(pack(v))));
    endrule

    rule doPrintSM (True);
        match {.msg, .r_addr, .v} = memSMPrintQ.first();
        memSMPrintQ.deq();

        stdio.printf(msg, list3(zeroExtend(msgSM), zeroExtend(r_addr), resize(pack(v))));
    endrule

    rule doPrintH (True);
        match {.msg, .r_addr, .v} = memHPrintQ.first();
        memHPrintQ.deq();

        stdio.printf(msg, list3(zeroExtend(msgH), zeroExtend(r_addr), resize(pack(v))));
    endrule



    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doInit (state == STATE_init);
        linkStarterStartRun.deq();
        stdio.printf(msgStart, List::nil);

        nCompleteReads <= completeReadsInitVal();

        lfsr.seed(1);
        state <= STATE_writing;
    endrule


    // ====================================================================
    //
    // Write values into memory
    //
    // ====================================================================

    rule sendWrite (state == STATE_writing);
        //
        // Store different values in each of the memories to increase confidence
        // that data are being directed to the right places.
        //
        // There are three dynamic modes, useful for testing memory in case
        // the backing storage retains its state between runs.  Mode 0 is the
        // normal case, mode 1 writes zeros, and mode 2 skips the writes.
        //
        if (memInitMode != 2)
        begin
            t_MEM_DATA_LG dataLG = 0;
            t_MEM_DATA_MD dataMD = 0;
            t_MEM_DATA_SM dataSM = unpack(0);
            t_MEM_DATA_SM dataH  = unpack(0);

            if (memInitMode == 0)
            begin
                dataLG = -(unpack(zeroExtend(pack(addr))) + 2);
                dataMD = unpack(zeroExtend(pack(addr))) + 1;
                dataSM = unpack(truncate(pack(addr)));
            end

            memoryLG.write(addr, dataLG);
            debugLog.record($format("writeLG: addr 0x%x, data 0x%x", addr, dataLG));

            memoryMD.write(addr, dataMD);
            debugLog.record($format("writeMD: addr 0x%x, data 0x%x", addr, dataMD));

            memorySM.write(addr, dataSM);
            debugLog.record($format("writeSM: addr 0x%x, data 0x%x", addr, dataSM));
            
            // Allocate a slot in the heap
`ifndef DISABLE_HEAP
            if (enableHeap)
            begin
                let heap_idx <- heap.malloc();
                debugLog.record($format("malloc: idx 0x%x", heap_idx));

                if (memInitMode == 0)
                begin
                    dataH  = unpack(~truncate(pack(heap_idx)));
                end

                heap.write(heap_idx, dataH);
                debugLog.record($format("writeH: idx 0x%x, data 0x%x", heap_idx, dataH));
            end
`endif
        end
        
        if (addr == `LAST_ADDR)
        begin
            addr <= `START_ADDR;
            state <= STATE_read_random;
            if (verbose)
            begin
                stdio.printf(msgWritesDone, List::nil);
            end
        end
        else
        begin
            addr <= addr + 1;
        end
    endrule
    

    // ====================================================================
    //
    // Read values back and dump them through streams
    //
    // ====================================================================

    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrLGQ <- mkSizedFIFO(32);
    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrMDQ <- mkSizedFIFO(32);
    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrSMQ <- mkSizedFIFO(32);
    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrHQ  <- mkSizedFIFO(32);
    Reg#(Bool) readSeqDone <- mkReg(False);
    Reg#(Bit#(10)) randTrip <- mkReg(0);

    //
    // Initiate random read request on each memory in parallel.  This is mostly
    // a cache test.
    //
    rule readRandomReq (state == STATE_read_random && (randTrip != maxBound));
        MEM_ADDRESS r_addr = truncate(lfsr.value) & `LAST_ADDR;
        lfsr.next();

        memoryLG.readReq(r_addr);
        memoryMD.readReq(r_addr);
        memorySM.readReq(r_addr);
`ifndef DISABLE_HEAP
        if (enableHeap)
            heap.readReq(r_addr);
`endif

        let done = ((randTrip + 1) == maxBound);

        readAddrLGQ.enq(tuple2(r_addr, done));
        readAddrMDQ.enq(tuple2(r_addr, done));
        readAddrSMQ.enq(tuple2(r_addr, done));
        if (enableHeap)
            readAddrHQ.enq(tuple2(r_addr, done));

        debugLog.record($format("read RAND from all: addr 0x%x", r_addr));

        randTrip <= randTrip + 1;
    endrule

    //
    // Initiate sequential read request on each memory in parallel.
    //
    rule readSequentialReq (state == STATE_read_sequential && ! readSeqDone);
        memoryLG.readReq(addr);
        memoryMD.readReq(addr);
        memorySM.readReq(addr);
`ifndef DISABLE_HEAP
        if (enableHeap)
            heap.readReq(addr);
`endif

        let done = (addr == `LAST_ADDR);

        readAddrLGQ.enq(tuple2(addr, done));
        readAddrMDQ.enq(tuple2(addr, done));
        readAddrSMQ.enq(tuple2(addr, done));
        if (enableHeap)
            readAddrHQ.enq(tuple2(addr, done));

        debugLog.record($format("read SEQ from all: addr 0x%x", addr));

        // malloc on every 4th access just to keep things interesting.
        // The readRecvHeap rule is freeing every read address, so there
        // will be entries available.
`ifndef DISABLE_HEAP
        if (enableHeap && (addr[1:0] == 3))
        begin
            let m <- heap.malloc();
            debugLog.record($format("malloc: idx 0x%x", m));
        end
`endif

        if (done)
        begin
            addr <= `START_ADDR;
            readSeqDone <= True;
        end
        else
        begin
            addr <= addr + 1;
        end
    endrule

    //
    // Individual rules to receive values and write them to the same stream.
    // The Bluespec scheduler will pick an order.
    //

    rule readRecvLG ((state == STATE_read_random) || (state == STATE_read_sequential));
        match {.r_addr, .done} = readAddrLGQ.first();
        readAddrLGQ.deq();

        let v <- memoryLG.readRsp();
        debugLog.record($format("readLG: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        if (memInitMode == 0)
            v = -(v + 2);

        Bool error = False;
        if (((memInitMode != 1) && (v != unpack(zeroExtend(pack(r_addr))))) ||
            ((memInitMode == 1) && (v != unpack(0))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            memLGPrintQ.enq(tuple3(msg, r_addr, v));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    rule readRecvMD ((state == STATE_read_random) || (state == STATE_read_sequential));
        match {.r_addr, .done} = readAddrMDQ.first();
        readAddrMDQ.deq();

        let v <- memoryMD.readRsp();
        debugLog.record($format("readMD: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        if (memInitMode == 0)
            v = v - 1;

        Bool error = False;
        if (((memInitMode != 1) && (v != unpack(zeroExtend(pack(r_addr))))) ||
            ((memInitMode == 1) && (v != unpack(0))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            memMDPrintQ.enq(tuple3(msg, r_addr, v));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    rule readRecvSM ((state == STATE_read_random) || (state == STATE_read_sequential));
        match {.r_addr, .done} = readAddrSMQ.first();
        readAddrSMQ.deq();

        let v <- memorySM.readRsp();
        debugLog.record($format("readSM: addr 0x%x, data 0x%x", r_addr, v));

        Bool error = False;
        if (((memInitMode != 1) && (v != unpack(truncate(pack(r_addr))))) ||
            ((memInitMode == 1) && (v != unpack(0))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            memSMPrintQ.enq(tuple3(msg, r_addr, v));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    (* descending_urgency = "readRecvHeap, readRecvSM, readRecvMD, readRecvLG" *)
    rule readRecvHeap ((state == STATE_read_random) || (state == STATE_read_sequential));
        match {.r_addr, .done} = readAddrHQ.first();
        readAddrHQ.deq();

`ifndef DISABLE_HEAP
        if (state == STATE_read_sequential)
        begin
            heap.free(r_addr);
            debugLog.record($format("free: idx 0x%x", r_addr));
        end

        let v <- heap.readRsp();
        debugLog.record($format("readH: idx 0x%x, data 0x%x", r_addr, v));

        if (memInitMode == 0)
            v = unpack(~pack(v));

        Bool error = False;
        if (((memInitMode != 1) && (v != unpack(truncate(pack(r_addr))))) ||
            ((memInitMode == 1) && (v != unpack(0))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            memHPrintQ.enq(tuple3(msg, r_addr, v));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
`endif
    endrule
    

    // ====================================================================
    //
    // Read latency test
    //
    // ====================================================================

    FIFO#(CYCLE_COUNTER) readCycleQ <- mkSizedFIFO(32);
    Reg#(Bit#(4)) readCycleReqIdx <- mkReg(0);
    Reg#(Bit#(4)) readCycleRespIdx <- mkReg(0);
    Reg#(Vector#(8, Bit#(16))) readCycles <- mkRegU();
    Reg#(Bit#(2)) timingPass <- mkReg(0);

    rule readTimeReq (state == STATE_read_timing && (readCycleReqIdx != 8));
        case (timingPass)
            0: memoryLG.readReq(addr);
            1: memoryMD.readReq(addr);
            2: memorySM.readReq(addr);
        endcase

        readCycleQ.enq(cycle);
        addr <= addr + 4;
        readCycleReqIdx <= readCycleReqIdx + 1;
    endrule

    rule readTimeRecv (state == STATE_read_timing);
        let start_cycle = readCycleQ.first();
        readCycleQ.deq();

        case (timingPass)
            0: let x <- memoryLG.readRsp();
            1: let y <- memoryMD.readRsp();
            2: let z <- memorySM.readRsp();
        endcase

        readCycles[readCycleRespIdx] <= truncate(cycle - start_cycle);
        readCycleRespIdx <= readCycleRespIdx + 1;

        if (readCycleRespIdx == 7)
        begin
            state <= STATE_read_timing_emit;
        end
    endrule
    
    rule readTimeEmit1 (state == STATE_read_timing_emit);
        Bit#(128) latency = pack(readCycles);
        stdio.printf(msgLatency, list2(latency[63:0], latency[127:64]));

        if (timingPass == 2)
        begin
            // Done with timing test
            state <= STATE_finished;
        end
        else
        begin
            // Another pass on a different access port
            state <= STATE_read_timing;
            addr <= `START_ADDR;
            readCycleReqIdx <= 0;
            readCycleRespIdx <= 0;
            timingPass <= timingPass + 1;
        end
    endrule


    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        stdio.printf(msgDone, List::nil);
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule
