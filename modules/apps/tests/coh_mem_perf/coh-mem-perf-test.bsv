//
// Copyright (C) 2013 Intel Corporation
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
import FIFOF::*;
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
`include "awb/provides/scratchpad_memory_common.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "awb/provides/coherent_scratchpad_performance_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
//`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"
`include "asim/dict/PARAMS_COHERENT_SCRATCHPAD_PERFORMANCE_COMMON.bsh"

// It is normally NOT necessary to include scratchpad_memory.bsh to use
// scratchpads.  mem-test includes it only to get the value of
// SCRATCHPAD_MEM_VALUE in order to pick data sizes that will force
// the three possible container scenarios:  multiple containers per
// datum, one container per datum, multiple data per container.
`include "asim/provides/scratchpad_memory.bsh"

`define TEST_NUM   512

typedef enum
{
    STATE_init,
    STATE_latecy_test,
    STATE_write_seq,
    STATE_write_random,
    STATE_read_seq,
    STATE_read_random,
    STATE_read_write_random,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);

module [CONNECTED_MODULE] mkCoherentScratchpadTest ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Alias#(Bit#(TSub#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA),
              //Alias#(MEM_DATA_SM, t_MEM_DATA),
              Bits#(t_MEM_DATA, t_MEM_DATA_SZ),
              NumAlias#(TLog#(`N_SCRATCH), t_SCRATCH_IDX_SZ),
              Alias#(Bit#(t_SCRATCH_IDX_SZ), t_SCRATCH_IDX),
              NumAlias#(TAdd#(t_SCRATCH_IDX_SZ, t_MEM_ADDR_SZ), t_COH_SCRATCH_ADDR_SZ),
              Alias#(Bit#(t_COH_SCRATCH_ADDR_SZ), t_COH_SCRATCH_ADDR));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate scratchpads
    //
    COH_SCRATCH_CONFIG conf = defaultValue;
    conf.cacheMode = (`COH_SCRATCH_MEM_PERF_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;

    // Coherent scratchpads
    NumTypeParam#(t_COH_SCRATCH_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
    
    Vector#(`N_SCRATCH, DEBUG_FILE) debugLogsCohScratch = newVector();
    Vector#(`N_SCRATCH, MEMORY_WITH_FENCE_IFC#(t_COH_SCRATCH_ADDR, t_MEM_DATA)) memoriesCohScratch = newVector();
    // Random number generators
    Vector#(`N_SCRATCH, LFSR#(Bit#(16))) lfsrsCohScratch = newVector();

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        debugLogsCohScratch[p] <- mkDebugFile("coherent_scratchpad_"+integerToString(p)+".out");
        memoriesCohScratch[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMPERF_DATA, p, conf, debugLogsCohScratch[p]);
        lfsrsCohScratch[p] <- mkLFSR_16();
    end
   
    // Private scratchpads
    Vector#(`N_SCRATCH, MEMORY_IFC#(MEM_ADDRESS, t_MEM_DATA)) memoriesScratch = newVector();
    Vector#(`N_SCRATCH, LFSR#(Bit#(16))) lfsrsScratch = newVector();
    SCRATCHPAD_CONFIG sconf = defaultValue;
    sconf.cacheMode = SCRATCHPAD_CACHED;

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        memoriesScratch[p] <- mkScratchpad((`VDEV_SCRATCH_MEMPERF_1 + p), sconf);
        lfsrsScratch[p] <- mkLFSR_16();
    end 

    DEBUG_FILE debugLog <- mkDebugFile("coh_mem_perf.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Verbose mode
    //  0 -- quiet
    //  1 -- verbose
    Param#(1) verboseMode <- mkDynamicParameter(`PARAMS_COHERENT_SCRATCHPAD_PERFORMANCE_COMMON_COH_MEM_PERF_VERBOSE, paramNode);
    let verbose = verboseMode == 1;
    Param#(16) testNumParam <-mkDynamicParameter(`PARAMS_COHERENT_SCRATCHPAD_PERFORMANCE_COMMON_COH_MEM_PERF_TEST_NUM, paramNode);
    Param#(1) testFwdMode <- mkDynamicParameter(`PARAMS_COHERENT_SCRATCHPAD_PERFORMANCE_COMMON_COH_MEM_PERF_FWD_TEST, paramNode);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();
    Reg#(CYCLE_COUNTER) cycle <- mkReg(0);
    Reg#(STATE) state <- mkReg(STATE_init);

    // Messages
    let msgCohData       <- getGlobalStringUID("cohMem[%x] [0x%8x] = 0x%08x, latency = %8d \n");
    let msgPrivData      <- getGlobalStringUID("privMem[%x] [0x%8x] = 0x%08x, latency = %8d \n");
    let msgInit          <- getGlobalStringUID("cohScratchMemPerfTest: start\n");
    let msgInitDone      <- getGlobalStringUID("cohScratchMemPerfTest: initialization done, cycle: %012d\n");
    let msgWarmCache     <- getGlobalStringUID("cohScratchMemPerfTest: central cache warm up done, cycle: %012d\n");
    let msgTestInit      <- getGlobalStringUID("cohScratchMemPerfTest: %s scratchpad %s test start (# test: %012d on %02d nodes)\n");
    let msgCohScratch    <- getGlobalStringUID("coherent");
    let msgPrivScratch   <- getGlobalStringUID("private");
    let msgLatency       <- getGlobalStringUID("latency");
    let msgWriteSeq      <- getGlobalStringUID("sequential write");
    let msgWriteRand     <- getGlobalStringUID("random write");
    let msgReadSeq       <- getGlobalStringUID("sequential read");
    let msgReadRand      <- getGlobalStringUID("random read");
    let msgReadWriteRand <- getGlobalStringUID("random read/write");
    let msgDone          <- getGlobalStringUID("cohScratchMemPerfTest: done, cycle: %012d, test cycle count: %012d, total latency: %020d\n");
    let msgExit          <- getGlobalStringUID("cohScratchMemPerfTest: done\n");

    Reg#(Bit#(16))    maxTests                 <- mkReg(`TEST_NUM);
    Reg#(Bit#(3))     initCnt                  <- mkReg(0);
    Reg#(Bit#(3))     testCnt                  <- mkReg(0);
    Reg#(Bit#(32))    cycleCnt                 <- mkReg(0);
    Reg#(Bit#(32))    initCycleCnt             <- mkReg(0);
    Reg#(Bit#(32))    startCycleCnt            <- mkReg(0);
    Reg#(Bit#(8))     idleCnt                  <- mkReg(0);  
    Reg#(Bit#(11))    testIdleCnt              <- mkReg(0);
    Reg#(Bool)        testInitialized          <- mkReg(False);
    Reg#(Bool)        testCoherentScratchpad   <- mkReg(True);
    Reg#(Bool)        testFwd                  <- mkReg(False);

    Vector#(`N_SCRATCH, Reg#(Bit#(48)))    totalLatency <- replicateM(mkReg(0));
    Vector#(`N_SCRATCH, Reg#(WORKING_SET)) testAddrs    <- replicateM(mkReg(0));
    Vector#(`N_SCRATCH, Reg#(Bit#(16)))    numTests     <- replicateM(mkReg(0));
    Vector#(`N_SCRATCH, Reg#(Bool)) testDoneSignals     <- replicateM(mkReg(True));
    Vector#(`N_SCRATCH, Reg#(Bool)) issueDoneSignals    <- replicateM(mkReg(False));
    Vector#(`N_SCRATCH, FIFOF#(Tuple3#(MEM_ADDRESS, Bit#(32), Bool))) readReqQsCohScratch <- replicateM(mkSizedFIFOF(32));
    Vector#(`N_SCRATCH, FIFOF#(Tuple3#(MEM_ADDRESS, Bit#(32), Bool))) readReqQsScratch <- replicateM(mkSizedFIFOF(32));
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycleCnt <= cycleCnt + 1;
    endrule

    (* fire_when_enabled *)
    rule doInit (state == STATE_init && fold(\&& , readVReg(testDoneSignals)));
        if (initCnt == 0)
        begin
            linkStarterStartRun.deq();
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                lfsrsCohScratch[p].seed(fromInteger(p+1));
                lfsrsScratch[p].seed(fromInteger(p+1));
            end
            initCnt <= initCnt + 1;
            stdio.printf(msgInit, List::nil);
        end
        else if (initCnt == 1)
        begin
            memoriesCohScratch[0].readReq(0);
            memoriesScratch[0].readReq(0);
            initCnt <= initCnt + 1;
        end
        else if (initCnt == 2)
        begin
            let resp0     <- memoriesScratch[0].readRsp();
            let resp1     <- memoriesCohScratch[0].readRsp();
            initCycleCnt  <= cycleCnt;
            maxTests      <= testNumParam;
            testFwd       <= unpack(testFwdMode);
            initCnt       <= initCnt + 1;
            debugLog.record($format("initialization done, cycle=%012d", cycleCnt));
            stdio.printf(msgInitDone, list1(zeroExtend(cycleCnt)));
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                testDoneSignals[p]  <= False;
            end
        end
        else if (initCnt == 3)
        begin
            initCnt       <= initCnt + 1;
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                testDoneSignals[p]  <= False;
                issueDoneSignals[p] <= False;
                testAddrs[p]        <= 0;
            end
        end
        else if (initCnt == 4)
        begin
            initCnt       <= 0;
            state         <= STATE_latecy_test;
            startCycleCnt <= cycleCnt;
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                testDoneSignals[p]  <= False;
                issueDoneSignals[p] <= False;
                testAddrs[p]        <= 0;
            end
            debugLog.record($format("cache warm up done, cycle=%012d", cycleCnt));
            stdio.printf(msgWarmCache, list1(zeroExtend(cycleCnt)));
        end
    endrule
     
    // ====================================================================
    //
    // Warm up central cache
    //
    // ====================================================================

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        rule warmCacheCohScratch (state == STATE_init && initCnt == 3 && !issueDoneSignals[p] && !testDoneSignals[p]);
            MEM_ADDRESS r_addr = zeroExtend(testAddrs[p]);
            Tuple2#(t_SCRATCH_IDX, MEM_ADDRESS) r_coh_addr = tuple2(fromInteger(p), r_addr);
            memoriesCohScratch[p].readReq(pack(r_coh_addr));
            readReqQsCohScratch[p].enq(tuple3(r_addr, cycleCnt, testAddrs[p] == maxBound)); 
            testAddrs[p] <= testAddrs[p] + 1;
            if (testAddrs[p] == maxBound)
            begin
                issueDoneSignals[p] <= True;
            end
        endrule
        rule warmCacheCohScratchRecv (state == STATE_init && initCnt == 3 && !testDoneSignals[p]);
            let resp <- memoriesCohScratch[p].readRsp();
            match {.r_addr, .s_cycle, .done}  = readReqQsCohScratch[p].first();
            readReqQsCohScratch[p].deq();
            if (done)
            begin
                testDoneSignals[p] <= True;
            end
        endrule
    end

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        rule warmCachePrivScratch (state == STATE_init && initCnt == 4 && !issueDoneSignals[p] && !testDoneSignals[p]);
            MEM_ADDRESS r_addr = zeroExtend(testAddrs[p]);
            memoriesScratch[p].readReq(r_addr);
            readReqQsScratch[p].enq(tuple3(r_addr, cycleCnt, testAddrs[p] == maxBound)); 
            testAddrs[p] <= testAddrs[p] + 1;
            if (testAddrs[p] == maxBound)
            begin
                issueDoneSignals[p] <= True;
            end
        endrule
        rule warmCachePrivScratchRecv (state == STATE_init && initCnt == 4 && !testDoneSignals[p]);
            let resp <- memoriesScratch[p].readRsp();
            match {.r_addr, .s_cycle, .done}  = readReqQsScratch[p].first();
            readReqQsScratch[p].deq();
            if (done)
            begin
                testDoneSignals[p] <= True;
            end
        endrule
    end

    // ====================================================================
    //
    // Common test rules
    //
    // ====================================================================

    (* fire_when_enabled *)
    rule testInit(state != STATE_init && state != STATE_finished && state != STATE_exit && !testInitialized);
        let msg_scratch = (testCoherentScratchpad)? msgCohScratch : msgPrivScratch;
        let msg_test = ?;
        case (state)
            STATE_latecy_test: msg_test = msgLatency;
            STATE_write_seq: msg_test = msgWriteSeq;
            STATE_write_random: msg_test = msgWriteRand;
            STATE_read_seq: msg_test = msgReadSeq;
            STATE_read_random: msg_test = msgReadRand;
            STATE_read_write_random: msg_test = msgReadWriteRand;
        endcase
        stdio.printf(msgTestInit, list4(zeroExtend(msg_scratch), zeroExtend(msg_test), zeroExtend(maxTests), fromInteger(valueOf(`N_SCRATCH))));
        testInitialized <= True;
    endrule
    
    (* fire_when_enabled *)
    rule testDone(state != STATE_init && state != STATE_finished && state != STATE_exit && testInitialized && fold(\&& , readVReg(testDoneSignals)));
        testIdleCnt <= testIdleCnt + 1;
        if (testIdleCnt == 0)
        begin
            Bit#(64) total_latency = 0;
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                total_latency        = total_latency + zeroExtend(totalLatency[p]);
            end
            stdio.printf(msgDone, list3(zeroExtend(cycleCnt), zeroExtend(cycleCnt-startCycleCnt), total_latency));
        end
        else if (testIdleCnt == maxBound)
        begin
            let new_state = ?;
            let switch_to_private = False;
            let new_test = testCoherentScratchpad;
            case (state)
                STATE_latecy_test:
                begin
                    new_state = (testCoherentScratchpad)? STATE_latecy_test : STATE_write_seq;
                    new_test  = !testCoherentScratchpad;
                end
                STATE_write_seq: new_state = STATE_write_random;
                STATE_write_random: new_state = STATE_read_seq;
                STATE_read_seq: new_state = STATE_read_random;
                STATE_read_random:
                begin
                    new_state = (testCoherentScratchpad)? STATE_write_seq : STATE_finished;
                    new_test  = !testCoherentScratchpad;
                end
            endcase
            testCoherentScratchpad <= new_test;
            testInitialized        <= False;
            state                  <= new_state;
            startCycleCnt          <= cycleCnt;
            testCnt                <= 0;
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                totalLatency[p]     <= 0;
                testDoneSignals[p]  <= False;
                issueDoneSignals[p] <= False;
                numTests[p]         <= 0;
                testAddrs[p]        <= 0;
            end
        end
    endrule


    // ====================================================================
    //
    // Latency test
    //
    // ====================================================================

    rule cohLatencyTest (state == STATE_latecy_test && (testCnt < 5) && testCoherentScratchpad);
        let new_idle_cnt = 0;
        if (testCnt == 0)
        begin
            memoriesCohScratch[0].readReq(0);
            testCnt <= testCnt + 1;
            readReqQsCohScratch[0].enq(tuple3(0, cycleCnt, False));
        end
        else
        begin
            new_idle_cnt = idleCnt + 1;
            if (idleCnt == 0)
            begin
                let resp <- memoriesCohScratch[0].readRsp();
                match {.r_addr, .s_cycle, .done}  = readReqQsCohScratch[0].first();
                readReqQsCohScratch[0].deq();
                if (testCnt != 1)
                begin
                    debugLog.record($format("cohRead[%02x]: addr 0x%x (coh addr 0x%x), data 0x%x, latency=%8d", 0, r_addr, r_addr, resp, (cycleCnt-s_cycle) ));
                    stdio.printf(msgCohData, list4(fromInteger(0), zeroExtend(r_addr), zeroExtend(resp), zeroExtend(cycleCnt-s_cycle)));
                end
            end
            if (testCnt == 4)
            begin
                testCnt <= testCnt + 1;
                if (testFwd == False || (valueOf(`N_SCRATCH)<2))
                begin
                    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
                    begin
                        testDoneSignals[p]  <= True;
                    end
                end
                new_idle_cnt = 0;
            end
            else if (idleCnt == maxBound)
            begin
                let addr = (testCnt == 1)? 0 : ( (testCnt == 2)? 1 : 31 );
                memoriesCohScratch[0].readReq(addr);
                testCnt <= testCnt + 1;
                readReqQsCohScratch[0].enq(tuple3(addr, cycleCnt, False));
                new_idle_cnt = 0;
            end
        end
        idleCnt <= new_idle_cnt;
    endrule

    rule cohLatencyFwdTest (state == STATE_latecy_test && ((testCnt == 5) || (testCnt == 6)) && testCoherentScratchpad && testFwd && (valueOf(`N_SCRATCH)>1));
        idleCnt <= idleCnt + 1;
        if (testCnt == 5 && idleCnt == maxBound)
        begin
            memoriesCohScratch[1].readReq(0);
            readReqQsCohScratch[1].enq(tuple3(0, cycleCnt, False));
            testCnt <= testCnt + 1;
        end
        else if (testCnt == 6)
        begin
            let resp <- memoriesCohScratch[1].readRsp();
            match {.r_addr, .s_cycle, .done}  = readReqQsCohScratch[1].first();
            readReqQsCohScratch[1].deq();
            debugLog.record($format("cohRead[%02x]: addr 0x%x (coh addr 0x%x), data 0x%x, latency=%8d", 1, r_addr, r_addr, resp, (cycleCnt-s_cycle) ));
            stdio.printf(msgCohData, list4(fromInteger(1), zeroExtend(r_addr), zeroExtend(resp), zeroExtend(cycleCnt-s_cycle)));
            for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
            begin
                testDoneSignals[p]  <= True;
            end
            testCnt <= testCnt + 1;
        end
    endrule


    rule privLatencyTest (state == STATE_latecy_test && (testCnt < 5) && !testCoherentScratchpad);
        let new_idle_cnt = 0;
        if (testCnt == 0)
        begin
            memoriesScratch[0].readReq(0);
            testCnt <= testCnt + 1;
            readReqQsScratch[0].enq(tuple3(0, cycleCnt, False));
        end
        else
        begin
            new_idle_cnt = idleCnt + 1;
            if (idleCnt == 0)
            begin
                let resp <- memoriesScratch[0].readRsp();
                match {.r_addr, .s_cycle, .done}  = readReqQsScratch[0].first();
                readReqQsScratch[0].deq();
                if (testCnt != 1)
                begin
                    debugLog.record($format("privRead[%02x]: addr 0x%x, data 0x%x, latency=%8d", 0, r_addr, resp, (cycleCnt-s_cycle) ));
                    stdio.printf(msgPrivData, list4(fromInteger(0), zeroExtend(r_addr), zeroExtend(resp), zeroExtend(cycleCnt-s_cycle)));
                end
            end
            if (testCnt == 4)
            begin
                testCnt <= testCnt + 1;
                for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
                begin
                    testDoneSignals[p]  <= True;
                end
            end
            else if (idleCnt == maxBound)
            begin
                let addr = (testCnt == 1)? 0 : ( (testCnt == 2)? 2 : 31 );
                memoriesScratch[0].readReq(addr);
                testCnt <= testCnt + 1;
                readReqQsScratch[0].enq(tuple3(addr, cycleCnt, False));
                new_idle_cnt = 0;
            end
        end
        idleCnt <= new_idle_cnt;
    endrule


    // ====================================================================
    //
    // Write values into coherent scratchpads
    //
    // ====================================================================

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        rule sendCohWriteSeq (state == STATE_write_seq && testCoherentScratchpad && !testDoneSignals[p]);
            MEM_ADDRESS w_addr = zeroExtend(testAddrs[p]);
            t_MEM_DATA  w_data = unpack(zeroExtend(pack(w_addr))) + 1 ;
            Tuple2#(t_SCRATCH_IDX, MEM_ADDRESS) w_coh_addr = tuple2(fromInteger(p), w_addr);
            memoriesCohScratch[p].write(pack(w_coh_addr), w_data);
            debugLog.record($format("cohWrite[%02x]: addr 0x%x (coh addr 0x%x), data 0x%x", p, w_addr, w_coh_addr, w_data));
            numTests[p]  <= numTests[p] + 1;
            testAddrs[p] <= testAddrs[p] + 1;
            if (numTests[p] == (maxTests-1))
            begin
                testDoneSignals[p] <= True;
            end
        endrule
        rule sendCohWriteRand (state == STATE_write_random && testCoherentScratchpad && !testDoneSignals[p]);
            WORKING_SET test_addr = truncate(lfsrsCohScratch[p].value());
            MEM_ADDRESS w_addr = zeroExtend(test_addr);
            t_MEM_DATA  w_data = unpack(zeroExtend(pack(w_addr))) + 1 ;
            Tuple2#(t_SCRATCH_IDX, MEM_ADDRESS) w_coh_addr = tuple2(fromInteger(p), w_addr);
            memoriesCohScratch[p].write(pack(w_coh_addr), w_data);
            debugLog.record($format("cohWrite[%02x]: addr 0x%x (coh addr 0x%x), data 0x%x", p, w_addr, w_coh_addr, w_data ));
            numTests[p] <= numTests[p] + 1;
            if (numTests[p] == (maxTests-1))
            begin
                testDoneSignals[p] <= True;
            end
            lfsrsCohScratch[p].next();
        endrule
    end
    
    // ====================================================================
    //
    // Read values from coherent scratchpads
    //
    // ====================================================================

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        rule issueCohReadSeq (state == STATE_read_seq && testCoherentScratchpad && !issueDoneSignals[p]);
            MEM_ADDRESS r_addr = zeroExtend(testAddrs[p]);
            Tuple2#(t_SCRATCH_IDX, MEM_ADDRESS) r_coh_addr = tuple2(fromInteger(p), r_addr);
            memoriesCohScratch[p].readReq(pack(r_coh_addr));
            readReqQsCohScratch[p].enq(tuple3(r_addr, cycleCnt, numTests[p] == (maxTests-1))); 
            debugLog.record($format("cohRead[%02x]: issue read addr 0x%x (coh addr 0x%x)", p, r_addr, r_coh_addr ));
            numTests[p]  <= numTests[p] + 1;
            testAddrs[p] <= testAddrs[p] + 1;
            if (numTests[p] == (maxTests-1))
            begin
                issueDoneSignals[p] <= True;
            end
        endrule
        rule issueCohReadRand (state == STATE_read_random && testCoherentScratchpad && !issueDoneSignals[p]);
            WORKING_SET test_addr = truncate(lfsrsCohScratch[p].value());
            MEM_ADDRESS r_addr = zeroExtend(test_addr);
            Tuple2#(t_SCRATCH_IDX, MEM_ADDRESS) r_coh_addr = tuple2(fromInteger(p), r_addr);
            memoriesCohScratch[p].readReq(pack(r_coh_addr));
            readReqQsCohScratch[p].enq(tuple3(r_addr, cycleCnt, numTests[p] == (maxTests-1))); 
            numTests[p] <= numTests[p] + 1;
            debugLog.record($format("cohRead[%02x]: issue read addr 0x%x (coh addr 0x%x)", p, r_addr, r_coh_addr ));
            if (numTests[p] == (maxTests-1))
            begin
                issueDoneSignals[p] <= True;
            end
            lfsrsCohScratch[p].next();
        endrule
        rule recvCohReadResp (((state == STATE_read_random) || (state == STATE_read_seq)) && testCoherentScratchpad && readReqQsCohScratch[p].notEmpty && !testDoneSignals[p]);
            let resp <- memoriesCohScratch[p].readRsp();
            match {.r_addr, .s_cycle, .done}  = readReqQsCohScratch[p].first();
            Tuple2#(t_SCRATCH_IDX, MEM_ADDRESS) r_coh_addr = tuple2(fromInteger(p), r_addr);
            readReqQsCohScratch[p].deq();
            debugLog.record($format("cohRead[%02x]: addr 0x%x (coh addr 0x%x), data 0x%x, latency=%8d", p, r_addr, r_coh_addr, resp, (cycleCnt-s_cycle) ));
            totalLatency[p] <= totalLatency[p] + zeroExtend(cycleCnt-s_cycle);
            //if (verbose)
            //begin
            //    stdio.printf(msgCohData, list4(fromInteger(p), zeroExtend(r_addr), zeroExtend(resp), zeroExtend(cycleCnt-s_cycle)));
            //end
            if (done)
            begin
                testDoneSignals[p] <= True;
            end
        endrule
    end

    // ====================================================================
    //
    // Write values into scratchpads
    //
    // ====================================================================

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        rule sendPrivWriteSeq (state == STATE_write_seq && !testCoherentScratchpad && !testDoneSignals[p]);
            MEM_ADDRESS w_addr = zeroExtend(testAddrs[p]); 
            t_MEM_DATA  w_data = unpack(zeroExtend(pack(w_addr))) + 1 ;
            memoriesScratch[p].write(w_addr, w_data);
            debugLog.record($format("privWrite[%02x]: addr 0x%x, data 0x%x", p, w_addr, w_data ));
            numTests[p]  <= numTests[p] + 1;
            testAddrs[p] <= testAddrs[p] + 1;
            if (numTests[p] == (maxTests-1))
            begin
                testDoneSignals[p] <= True;
            end
        endrule
        rule sendPrivWriteRand (state == STATE_write_random && !testCoherentScratchpad && !testDoneSignals[p]);
            WORKING_SET test_addr = truncate(lfsrsScratch[p].value()); 
            MEM_ADDRESS w_addr = zeroExtend(test_addr);
            t_MEM_DATA  w_data = unpack(zeroExtend(pack(w_addr))) + 1 ;
            memoriesScratch[p].write(w_addr, w_data);
            debugLog.record($format("privWrite[%02x]: addr 0x%x, data 0x%x", p, w_addr, w_data ));
            numTests[p] <= numTests[p] + 1;
            if (numTests[p] == (maxTests-1))
            begin
                testDoneSignals[p] <= True;
            end
            lfsrsScratch[p].next();
        endrule
    end
    
    // ====================================================================
    //
    // Read values from private scratchpads
    //
    // ====================================================================

    for(Integer p = 0; p < valueOf(`N_SCRATCH); p = p + 1)
    begin
        rule issuePrivReadSeq (state == STATE_read_seq && !testCoherentScratchpad && !issueDoneSignals[p]);
            MEM_ADDRESS r_addr = zeroExtend(testAddrs[p]);
            memoriesScratch[p].readReq(r_addr);
            readReqQsScratch[p].enq(tuple3(r_addr, cycleCnt, numTests[p] == (maxTests-1))); 
            numTests[p]  <= numTests[p] + 1;
            testAddrs[p] <= testAddrs[p] + 1;
            debugLog.record($format("privRead[%02x]: issue read addr 0x%x", p, r_addr));
            if (numTests[p] == (maxTests-1))
            begin
                issueDoneSignals[p] <= True;
            end
        endrule
        rule issuePrivReadRand (state == STATE_read_random && !testCoherentScratchpad && !issueDoneSignals[p]);
            WORKING_SET test_addr = truncate(lfsrsScratch[p].value()); 
            MEM_ADDRESS r_addr = zeroExtend(test_addr);
            memoriesScratch[p].readReq(r_addr);
            readReqQsScratch[p].enq(tuple3(r_addr, cycleCnt, numTests[p] == (maxTests-1))); 
            numTests[p] <= numTests[p] + 1;
            debugLog.record($format("privRead[%02x]: issue read addr 0x%x", p, r_addr));
            if (numTests[p] == (maxTests-1))
            begin
                issueDoneSignals[p] <= True;
            end
            lfsrsScratch[p].next();
        endrule
        rule recvPrivReadResp (((state == STATE_read_random) || (state == STATE_read_seq)) && !testCoherentScratchpad && readReqQsScratch[p].notEmpty && !testDoneSignals[p]);
            let resp <- memoriesScratch[p].readRsp();
            match {.r_addr, .s_cycle, .done}  = readReqQsScratch[p].first();
            readReqQsScratch[p].deq();
            debugLog.record($format("privRead[%02x]: addr 0x%x, data 0x%x, latency=%8d", p, r_addr, resp, (cycleCnt-s_cycle) ));
            totalLatency[p] <= totalLatency[p] + zeroExtend(cycleCnt-s_cycle);
            // if (verbose)
            // begin
            //     stdio.printf(msgPrivData, list4(fromInteger(p), zeroExtend(r_addr), zeroExtend(resp), zeroExtend(cycleCnt-s_cycle)));
            // end
            if (done)
            begin
                testDoneSignals[p] <= True;
            end
        endrule
    end
    
    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        stdio.printf(msgExit, List::nil);
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule
