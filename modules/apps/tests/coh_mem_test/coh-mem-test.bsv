//
// Copyright (C) 2009 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//


import FIFO::*;
import Vector::*;
import GetPut::*;
import LFSR::*;
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"

// It is normally NOT necessary to include scratchpad_memory.bsh to use
// scratchpads.  mem-test includes it only to get the value of
// SCRATCHPAD_MEM_VALUE in order to pick data sizes that will force
// the three possible container scenarios:  multiple containers per
// datum, one container per datum, multiple data per container.
`include "asim/provides/scratchpad_memory.bsh"

`define START_ADDR 0
`define LAST_ADDR  'h7ff

typedef enum
{
    STATE_init,
    STATE_writing,
    STATE_read_random,
    STATE_read_sequential,
    STATE_coherence_test1,
    STATE_coh_read_sequential, 
    STATE_coherence_test2,
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
              Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              // Large data (multiple containers for single datum)
              Alias#(Int#(TAdd#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA_LG),
              Bits#(t_MEM_DATA_LG, t_MEM_DATA_LG_SZ),
              // Medium data (same container size as data)
              Alias#(Bit#(TSub#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA_MD),
              Bits#(t_MEM_DATA_MD, t_MEM_DATA_MD_SZ),
              // Small data (multiple data per container)
              Alias#(MEM_DATA_SM, t_MEM_DATA_SM),
              Bits#(t_MEM_DATA_SM, t_MEM_DATA_SM_SZ));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate scratchpads
    //
    COH_SCRATCH_CONFIG conf = defaultValue;
    conf.cacheMode = (`COH_MEM_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;

    // Medium data (same container size as data)
    NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_MD_SZ) data_md_size = ?;
    mkCoherentScratchpadController(`VDEV_SCRATCH_COH_MEMTEST_MD_DATA, `VDEV_SCRATCH_COH_MEMTEST_MD_BITS, addr_size, data_md_size, conf);
    DEBUG_FILE debugLogMD0 <- mkDebugFile("coherent_scratchpad_md_0.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_MD) memoryMD0 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_MD_DATA, 0, conf, debugLogMD0);
    DEBUG_FILE debugLogMD1 <- mkDebugFile("coherent_scratchpad_md_1.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_MD) memoryMD1 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_MD_DATA, 1, conf, debugLogMD1);
    DEBUG_FILE debugLogMD2 <- mkDebugFile("coherent_scratchpad_md_2.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_MD) memoryMD2 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_MD_DATA, 2, conf, debugLogMD2);
    DEBUG_FILE debugLogMD3 <- mkDebugFile("coherent_scratchpad_md_3.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_MD) memoryMD3 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_MD_DATA, 3, conf, debugLogMD3);

    // Small data (multiple data per container)
    NumTypeParam#(t_MEM_DATA_SM_SZ) data_sm_size = ?;
    mkCoherentScratchpadController(`VDEV_SCRATCH_COH_MEMTEST_SM_DATA, `VDEV_SCRATCH_COH_MEMTEST_SM_BITS, addr_size, data_sm_size, conf);
    DEBUG_FILE debugLogSM0 <- mkDebugFile("coherent_scratchpad_sm_0.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_SM) memorySM0 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_SM_DATA, 0, conf, debugLogSM0);
    DEBUG_FILE debugLogSM1 <- mkDebugFile("coherent_scratchpad_sm_1.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_SM) memorySM1 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_SM_DATA, 1, conf, debugLogSM1);
    DEBUG_FILE debugLogSM2 <- mkDebugFile("coherent_scratchpad_sm_2.out");
    MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA_SM) memorySM2 <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMTEST_SM_DATA, 2, conf, debugLogSM2);
    
    DEBUG_FILE debugLog <- mkDebugFile("coh_mem_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Verbose mode
    //  0 -- quiet
    //  1 -- verbose
    Param#(1) verboseMode <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_COH_MEM_TEST_VERBOSE, paramNode);
    let verbose = verboseMode == 1;

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(CYCLE_COUNTER) cycle <- mkReg(0);
    Reg#(STATE) state <- mkReg(STATE_init);

    Reg#(MEM_ADDRESS) addr <- mkReg(`START_ADDR);

    // Random number generators
    LFSR#(Bit#(16)) lfsr  <- mkLFSR_16();
    LFSR#(Bit#(16)) lfsr2 <- mkLFSR_16();

    Reg#(Bit#(2)) nCompleteReads <- mkReg(2);
    function Bit#(2) completeReadsInitVal() = 2;

    // Messages
    let msgData <- getGlobalStringUID("mem%s [0x%8x] = 0x%08x\n");
    let msgDataErr <- getGlobalStringUID("mem%s [0x%8x] = 0x%08x  ERROR\n");
    // let msgLG <- getGlobalStringUID("LG");
    let msgMD <- getGlobalStringUID("MD");
    let msgSM <- getGlobalStringUID("SM");
    let msgLatency <- getGlobalStringUID("latency (4 loads, 2 bytes per load) = 0x%016llx\n                                      0x%016llx\n");
    let msgDone <- getGlobalStringUID("cohMemTest: done\n");
    let msgInit <- getGlobalStringUID("cohMemTest: start\n");
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doInit (state == STATE_init);
        linkStarterStartRun.deq();
        lfsr.seed(1);
        lfsr2.seed(2);
        state <= STATE_writing;
        stdio.printf(msgInit, List::nil);
    endrule


    // ====================================================================
    //
    // Write values into memory
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule sendWrite (state == STATE_writing);
        //
        // Store different values in each of the memories to increase confidence
        // that data are being directed to the right places.
        //
        t_MEM_DATA_MD dataMD = unpack(zeroExtend(pack(addr))) + 1;
        t_MEM_DATA_SM dataSM = unpack(truncate(pack(addr)));

        memoryMD0.write(addr, dataMD);
        debugLog.record($format("writeMD0: addr 0x%x, data 0x%x", addr, dataMD));

        memorySM0.write(addr, dataSM);
        debugLog.record($format("writeSM0: addr 0x%x, data 0x%x", addr, dataSM));
        
        if (addr == `LAST_ADDR)
        begin
            addr <= `START_ADDR;
            state <= STATE_read_random;
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

    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrMDQ  <- mkSizedFIFO(64);
    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrMD2Q <- mkSizedFIFO(64);
    FIFO#(Tuple2#(MEM_ADDRESS, Bool)) readAddrSMQ  <- mkSizedFIFO(64);
    Reg#(Bool) readSeqDone <- mkReg(False);
    Reg#(Bit#(10)) randTrip <- mkReg(0);

    //
    // Initiate random read request on each memory in parallel.  This is mostly
    // a cache test.
    //
    rule readRandomReq (state == STATE_read_random && (randTrip != maxBound));
        MEM_ADDRESS r_addr = truncate(lfsr.value) & `LAST_ADDR;
        lfsr.next();

        //memoryLG.readReq(r_addr);
        memoryMD0.readReq(r_addr);
        memorySM0.readReq(r_addr);
        let done = ((randTrip + 1) == maxBound);

        //readAddrLGQ.enq(tuple2(r_addr, done));
        readAddrMDQ.enq(tuple2(r_addr, done));
        readAddrSMQ.enq(tuple2(r_addr, done));

        debugLog.record($format("read RAND from all: addr 0x%x", r_addr));

        randTrip <= randTrip + 1;
    endrule

    //
    // Initiate sequential read request on each memory in parallel.
    //
    rule readSequentialReq (state == STATE_read_sequential && ! readSeqDone);
        //memoryLG.readReq(addr);
        memoryMD0.readReq(addr);
        memorySM0.readReq(addr);
        let done = (addr == `LAST_ADDR);

        //readAddrLGQ.enq(tuple2(addr, done));
        readAddrMDQ.enq(tuple2(addr, done));
        readAddrSMQ.enq(tuple2(addr, done));
        debugLog.record($format("read SEQ from all: addr 0x%x", addr));

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
    rule readRecvMD0 ((state == STATE_read_random) || (state == STATE_read_sequential));
        match {.r_addr, .done} = readAddrMDQ.first();
        readAddrMDQ.deq();

        let v <- memoryMD0.readRsp();
        debugLog.record($format("readMD0: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        v = v - 1;

        Bool error = False;
        if (v != unpack(zeroExtend(pack(r_addr)))) 
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgMD), zeroExtend(r_addr), resize(pack(v))));
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

    rule readRecvSM0 ((state == STATE_read_random) || (state == STATE_read_sequential));
        match {.r_addr, .done} = readAddrSMQ.first();
        readAddrSMQ.deq();

        let v <- memorySM0.readRsp();
        debugLog.record($format("readSM0: addr 0x%x, data 0x%x", r_addr, v));

        Bool error = False;
        if (v != unpack(truncate(pack(r_addr)))) 
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgSM), zeroExtend(r_addr), resize(pack(v))));
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

    // ====================================================================
    //
    // Coherence test
    //
    // ====================================================================
  
    Reg#(Bool) cohReqDone <- mkReg(False);

    (* conservative_implicit_conditions *)
    rule issueCoherentReqs (state == STATE_coherence_test1 && !cohReqDone);
        // issue writes 
        t_MEM_DATA_MD  dataMD = unpack(zeroExtend(pack(addr)+2));
        t_MEM_DATA_SM  dataSM = unpack(truncate(pack(addr)+3));

        memoryMD1.write(addr, dataMD);
        debugLog.record($format("writeMD1: addr 0x%x, data 0x%x", addr, dataMD));

        memorySM1.write(addr, dataSM);
        debugLog.record($format("writeSM1: addr 0x%x, data 0x%x", addr, dataSM));

        // issue reads
        MEM_ADDRESS r_addr = truncate(lfsr.value) & `LAST_ADDR;
        lfsr.next();
        memoryMD0.readReq(r_addr);
        memorySM0.readReq(r_addr);
        let done = (addr == `LAST_ADDR);
        readAddrMDQ.enq(tuple2(r_addr, done));
        readAddrSMQ.enq(tuple2(r_addr, done));
        debugLog.record($format("read RAND from all: addr 0x%x", r_addr));

        if (addr == `LAST_ADDR)
        begin
            addr  <= `START_ADDR;
            cohReqDone <= True;
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
    rule cohReadRecvMD0 (state == STATE_coherence_test1);
        match {.r_addr, .done} = readAddrMDQ.first();
        readAddrMDQ.deq();

        let v <- memoryMD0.readRsp();
        debugLog.record($format("cohReadMD0: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        t_MEM_DATA_MD v0 = v - 1;
        t_MEM_DATA_MD v1 = v - 2;

        Bool error = False;
        if ((v0 != unpack(zeroExtend(pack(r_addr)))) && (v1 != unpack(zeroExtend(pack(r_addr)))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgMD), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule
    
    rule cohReadRecvSM0 (state == STATE_coherence_test1);
        match {.r_addr, .done} = readAddrSMQ.first();
        readAddrSMQ.deq();

        let v <- memorySM0.readRsp();
        debugLog.record($format("cohReadSM0: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        t_MEM_DATA_SM v0 = v;
        t_MEM_DATA_SM v1 = unpack(pack(v) - 3);
        
        Bool error = False;
        if ((pack(v0) != truncate(pack(r_addr))) && (pack(v1) != truncate(pack(r_addr))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgSM), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    //
    // Initiate sequential read request on each memory in parallel.
    //
    rule cohReadSequentialReq (state == STATE_coh_read_sequential && !cohReqDone);
        memoryMD1.readReq(addr);
        memorySM1.readReq(addr);
        
        let done = (addr == `LAST_ADDR);

        readAddrMDQ.enq(tuple2(addr, done));
        readAddrSMQ.enq(tuple2(addr, done));
        debugLog.record($format("read SEQ from all: addr 0x%x", addr));

        if (done)
        begin
            addr <= `START_ADDR;
            cohReqDone <= True;
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
    rule cohReadSequentialRecvMD1 (state == STATE_coh_read_sequential);
        match {.r_addr, .done} = readAddrMDQ.first();
        readAddrMDQ.deq();

        let v <- memoryMD1.readRsp();
        debugLog.record($format("cohReadSeqMD1: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        v = v - 2;

        Bool error = False;
        if (v != unpack(zeroExtend(pack(r_addr)))) 
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgMD), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= 1;
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    rule cohReadSequentialRecvSM1 (state == STATE_coh_read_sequential);
        match {.r_addr, .done} = readAddrSMQ.first();
        readAddrSMQ.deq();

        t_MEM_DATA_SM v <- memorySM1.readRsp();
        debugLog.record($format("cohReadSeqSM1: addr 0x%x, data 0x%x", r_addr, v));
 
        v = unpack(pack(v)-3);
                
        Bool error = False;
        if (v != unpack(truncate(pack(r_addr)))) 
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgSM), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= 1;
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    (* conservative_implicit_conditions *)
    rule issueCoherentTest2Reqs (state == STATE_coherence_test2 && !cohReqDone);
        // issue writes 
        MEM_ADDRESS w_addr0 = addr;
        MEM_ADDRESS w_addr1 = truncate(lfsr2.value) & `LAST_ADDR;
        lfsr2.next();
        
        t_MEM_DATA_MD  dataMD0 = unpack(zeroExtend(pack(w_addr0)+5));
        t_MEM_DATA_MD  dataMD1 = unpack(zeroExtend(pack(w_addr1)+6));
        t_MEM_DATA_SM  dataSM0 = unpack(truncate(pack(w_addr0)+7));
        t_MEM_DATA_SM  dataSM1 = unpack(truncate(pack(w_addr1)+8));

        memoryMD0.write(w_addr0, dataMD0);
        debugLog.record($format("writeMD0: addr 0x%x, data 0x%x", w_addr0, dataMD0));
        memoryMD3.write(w_addr1, dataMD1);
        debugLog.record($format("writeMD3: addr 0x%x, data 0x%x", w_addr1, dataMD1));

        memorySM0.write(w_addr0, dataSM0);
        debugLog.record($format("writeSM0: addr 0x%x, data 0x%x", w_addr0, dataSM0));
        memorySM2.write(w_addr1, dataSM1);
        debugLog.record($format("writeSM2: addr 0x%x, data 0x%x", w_addr1, dataSM1));

        // issue reads
        MEM_ADDRESS r_addr = truncate(lfsr.value) & `LAST_ADDR;
        lfsr.next();
        memoryMD1.readReq(r_addr);
        memoryMD2.readReq(addr);
        memorySM1.readReq(r_addr);
        
        let done = (addr == `LAST_ADDR);
        
        readAddrMDQ.enq(tuple2(r_addr, done));
        readAddrMD2Q.enq(tuple2(addr, done));
        readAddrSMQ.enq(tuple2(r_addr, done));
        debugLog.record($format("read RAND from MD1 and SM1: addr 0x%x", r_addr));
        debugLog.record($format("read sequential from MD2: addr 0x%x", addr));

        if (addr == `LAST_ADDR)
        begin
            addr  <= `START_ADDR;
            cohReqDone <= True;
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
    rule cohTest2ReadRecvMD1 (state == STATE_coherence_test2);
        match {.r_addr, .done} = readAddrMDQ.first();
        readAddrMDQ.deq();

        let v <- memoryMD1.readRsp();
        debugLog.record($format("cohTest2ReadMD1: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        t_MEM_DATA_MD v0 = v - 2;
        t_MEM_DATA_MD v1 = v - 5;
        t_MEM_DATA_MD v2 = v - 6;

        Bool error = False;
        if ((v0 != unpack(zeroExtend(pack(r_addr)))) && 
            (v1 != unpack(zeroExtend(pack(r_addr)))) &&
            (v2 != unpack(zeroExtend(pack(r_addr)))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgMD), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    rule cohTest2ReadRecvMD2 (state == STATE_coherence_test2);
        match {.r_addr, .done} = readAddrMD2Q.first();
        readAddrMD2Q.deq();

        let v <- memoryMD2.readRsp();
        debugLog.record($format("cohTest2ReadMD2: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        t_MEM_DATA_MD v0 = v - 2;
        t_MEM_DATA_MD v1 = v - 5;
        t_MEM_DATA_MD v2 = v - 6;

        Bool error = False;
        if ((v0 != unpack(zeroExtend(pack(r_addr)))) && 
            (v1 != unpack(zeroExtend(pack(r_addr)))) &&
            (v2 != unpack(zeroExtend(pack(r_addr)))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgMD), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
        end
    endrule

    rule cohTest2ReadRecvSM1 (state == STATE_coherence_test2);
        match {.r_addr, .done} = readAddrSMQ.first();
        readAddrSMQ.deq();

        let v <- memorySM1.readRsp();
        debugLog.record($format("cohTest2ReadSM1: addr 0x%x, data 0x%x", r_addr, v));

        // Convert value so it equals r_addr
        t_MEM_DATA_SM v0 = unpack(pack(v) - 3);
        t_MEM_DATA_SM v1 = unpack(pack(v) - 7);
        t_MEM_DATA_SM v2 = unpack(pack(v) - 8);
        
        Bool error = False;
        if ((pack(v0) != truncate(pack(r_addr))) && 
            (pack(v1) != truncate(pack(r_addr))) &&
            (pack(v2) != truncate(pack(r_addr))))
        begin
            error = True;
        end

        if (verbose || error)
        begin
            let msg = (! error ? msgData : msgDataErr);
            stdio.printf(msg, list3(zeroExtend(msgSM), zeroExtend(r_addr), resize(pack(v))));
        end
        
        if (done)
        begin
            // All readers done?
            if (nCompleteReads == 3)
            begin
                state <= unpack(pack(state) + 1);
                nCompleteReads <= completeReadsInitVal();
                cohReqDone <= False;
            end
            else
            begin
                nCompleteReads <= nCompleteReads + 1;
            end
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
