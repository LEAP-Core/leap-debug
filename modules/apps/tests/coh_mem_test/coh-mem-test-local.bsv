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
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "asim/provides/coh_mem_test_common_params.bsh"
`include "awb/provides/coh_mem_test_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_COH_MEM_TEST_COMMON.bsh"


typedef enum
{
    STATE_init,
    STATE_print_info,
    STATE_engine_init,
    STATE_test,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);


typedef enum
{
    TEST_WRITE_SEQ,
    TEST_FENCE1,
    TEST_READ_SEQ,
    TEST_READ_RAND,
    TEST_ONE_W_N_R,
    TEST_FENCE2,
    TEST_TORTURE,
    TEST_FENCE3,
    TEST_TORTURE_FENCE,
    TEST_FENCE4
}
COH_TEST_STATE
    deriving (Bits, Eq);


// Coherent scratchpad memory test local module
module [CONNECTED_MODULE] mkCohMemTestLocal ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate coherent scratchpads
    //
    COH_SCRATCH_CONFIG controllerConf = defaultValue;
    controllerConf.cacheMode = (`COH_MEM_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    COH_SCRATCH_CONFIG clientConf = defaultValue;
    clientConf.cacheMode = (`COH_MEM_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
    mkCoherentScratchpadController(`VDEV_SCRATCH_COH_MEMTEST_DATA, `VDEV_SCRATCH_COH_MEMTEST_BITS, addr_size, data_size, controllerConf);
   
    Vector#(N_ENGINES, DEBUG_FILE) debugLogMs = newVector();
    Vector#(N_ENGINES, DEBUG_FILE) debugLogEs = newVector();
    Vector#(N_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) memories = newVector();
    Vector#(N_ENGINES, COH_MEM_TEST_ENGINE_IFC#(MEM_ADDRESS)) engines = newVector();

    if (valueOf(N_ENGINES) < 2)
    begin
        // N_ENGINES should be at least 2
        error("Invalid number of test engines");
    end
    
    function String genDebugMemoryFileName(Integer id);
        return "coh_memory_"+integerToString(id)+".out";
    endfunction
    
    function String genDebugEngineFileName(Integer id);
        return "coh_test_engine_"+integerToString(id)+".out";
    endfunction

    function ActionValue#(MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) doCurryCohClient(mFunction, x, y);
        actionvalue
            let m <- mFunction(`VDEV_SCRATCH_COH_MEMTEST_DATA, x, clientConf, y);
            return m;
        endactionvalue
    endfunction

    function doCurryTestEngineConstructor(mFunction, x, y);
        return mFunction(x,y);
    endfunction

    function ActionValue#(COH_MEM_TEST_ENGINE_IFC#(MEM_ADDRESS)) doCurryTestEngine(mFunction, x);
        actionvalue
            let m <- mFunction(x);
            return m;
        endactionvalue
    endfunction

    Vector#(N_ENGINES, String) debugLogMNames = genWith(genDebugMemoryFileName);
    Vector#(N_ENGINES, String) debugLogENames = genWith(genDebugEngineFileName);
    debugLogMs <- mapM(mkDebugFile, debugLogMNames);
    debugLogEs <- mapM(mkDebugFile, debugLogENames);
    
    Vector#(N_ENGINES, Integer) clientIds = genVector();
    let mkCohClientVec = replicate(mkDebugCoherentScratchpadClient);
    memories <- zipWith3M(doCurryCohClient, mkCohClientVec, clientIds, debugLogMs);

    let mkTestEngineVec = replicate(mkCohMemTestEngine);
    let engineConstructors = zipWith3(doCurryTestEngineConstructor, mkTestEngineVec, memories, genVector());
    engines <- zipWithM(doCurryTestEngine, engineConstructors, debugLogEs);

    DEBUG_FILE debugLog <- mkDebugFile("coh_mem_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Verbose mode
    //  0 -- quiet
    //  1 -- verbose
    Param#(1) verboseMode <- mkDynamicParameter(`PARAMS_COH_MEM_TEST_COMMON_COH_MEM_TEST_VERBOSE, paramNode);
    let verbose = verboseMode == 1;

    Param#(24) iterParam   <- mkDynamicParameter(`PARAMS_COH_MEM_TEST_COMMON_COH_MEM_TEST_NUM, paramNode);
    Param#(5) wsetBitParam <- mkDynamicParameter(`PARAMS_COH_MEM_TEST_COMMON_COH_MEM_TEST_WORKING_SET_BIT, paramNode);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(CYCLE_COUNTER) cycle <- mkReg(0);
    Reg#(STATE) state <- mkReg(STATE_init);
    Reg#(COH_TEST_STATE) testState <- mkReg(TEST_WRITE_SEQ);
    Reg#(Bit#(24)) maxIter <- mkReg(0);
    Reg#(MEM_ADDRESS) wset <- mkReg(unpack(0));
    Reg#(Bit#(24))  errNum <- mkReg(0);
    Vector#(N_ENGINES, Reg#(Bool)) engineStates <- replicateM(mkReg(False));

    // Messages
    let msgTest         <- getGlobalStringUID("cohMemTest: memory: 0x%08x, working set: 0x%08x, # engines: %03d, # iter per test: %06d\n");
    let msgTestErr      <- getGlobalStringUID("Test error: errNum=%06d\n");
    let msgTestWriteSeq <- getGlobalStringUID("Write Sequential");
    let msgTestReadRand <- getGlobalStringUID("Read Random");
    let msgTestReadSeq  <- getGlobalStringUID("Read Sequential");
    let msgTestFence    <- getGlobalStringUID("Fence");
    let msgTest1WNR     <- getGlobalStringUID("One Writer N Reader");
    let msgTestTorture  <- getGlobalStringUID("Torture Test");
    let msgTestTortureFence  <- getGlobalStringUID("Torture Test with Fence");

    let msgInit <- getGlobalStringUID("cohMemTest: start\n");
    let msgTestInit <- getGlobalStringUID("cohMemTest: Running test: %s \n");
    let msgDone <- getGlobalStringUID("cohMemTest: done\n");
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doInit (state == STATE_init);
        linkStarterStartRun.deq();
        state <= STATE_print_info;
        stdio.printf(msgInit, List::nil);
    endrule

    rule doPrint (state == STATE_print_info);
        MEM_ADDRESS w_set = 1 << wsetBitParam;
        MEM_ADDRESS memory_bound = maxBound;

        stdio.printf(msgTest, list4(zeroExtend(memory_bound), 
                                    zeroExtend(w_set),
                                    fromInteger(valueOf(N_ENGINES)), 
                                    zeroExtend(iterParam)));
    
        state <= STATE_engine_init;
        wset <= w_set;
        maxIter <= iterParam;
    endrule

    Reg#(ENGINE_PORT_NUM) engineId <- mkReg(0);

    rule engineInit (state == STATE_engine_init);
        engines[resize(engineId)].setIter(maxIter);
        engines[resize(engineId)].setWorkingSet(wset);
        engineId <= engineId + 1;
        if (engineId == fromInteger(valueOf(N_ENGINES)-1))
        begin
            state <= STATE_test;
        end
    endrule

    // Test request and response network 
    CONNECTION_ADDR_RING#(ENGINE_PORT_NUM, Tuple2#(COH_MEM_ENGINE_TEST_REQ, MEM_ADDRESS)) link_test_req <-
        mkConnectionAddrRingNode("Coh_mem_test_req", 0);
    CONNECTION_ADDR_RING#(ENGINE_PORT_NUM, Tuple2#(ENGINE_PORT_NUM, Bit#(24))) link_test_resp <-
        mkConnectionAddrRingNode("Coh_mem_test_resp", 0);


    // ====================================================================
    //
    // Running tests
    //
    // ====================================================================

    Reg#(Bool) testInitialized <- mkReg(False);
    Reg#(Bool) testReqSent <- mkReg(False);
    Reg#(ENGINE_PORT_NUM) reqSendState <- mkReg(0);

    rule testInit (state == STATE_test && !testInitialized);
        let test_name = ?;
        case (testState)
            TEST_WRITE_SEQ: test_name = msgTestWriteSeq;
            TEST_FENCE1: test_name = msgTestFence;
            TEST_READ_SEQ: test_name = msgTestReadSeq;
            TEST_READ_RAND: test_name = msgTestReadRand;
            TEST_ONE_W_N_R: test_name = msgTest1WNR;
            TEST_FENCE2: test_name = msgTestFence;
            TEST_TORTURE: test_name = msgTestTorture;
            TEST_FENCE3: test_name = msgTestFence;
            TEST_TORTURE_FENCE: test_name = msgTestTortureFence;
            TEST_FENCE4: test_name = msgTestFence;
        endcase
        stdio.printf(msgTestInit, list1(zeroExtend(test_name)));
        testInitialized <= True;
        debugLog.record($format("testInit: testState=%03d", testState));
    endrule

    rule testWriteSeq (state == STATE_test && testInitialized && testState == TEST_WRITE_SEQ && !testReqSent);
        link_test_req.enq(1, tuple2(COH_TEST_REQ_WRITE_SEQ, unpack(1)));
        testReqSent <= True;
        engineStates[0] <= True;
        debugLog.record($format("testWriteSeq: send request to network..."));
    endrule

    rule testFence1 (state == STATE_test && testInitialized && testState == TEST_FENCE1 && !testReqSent);
        link_test_req.enq(1, tuple2(COH_TEST_REQ_FENCE, unpack(0)));
        testReqSent <= True;
        engineStates[0] <= True;
        debugLog.record($format("testFence1: send request to network..."));
    endrule

    rule testFence2 (state == STATE_test && testInitialized && testState == TEST_FENCE2 && !testReqSent);
        link_test_req.enq(fromInteger(valueOf(N_ENGINES)), tuple2(COH_TEST_REQ_FENCE, unpack(0)));
        testReqSent <= True;
        engineStates[fromInteger(valueOf(N_ENGINES)-1)] <= True;
        debugLog.record($format("testFence2: send request to network..."));
    endrule
    
    rule testFence34 (state == STATE_test && testInitialized && (testState == TEST_FENCE3 || testState == TEST_FENCE4) && !testReqSent);
        let engine_id = reqSendState + 1;
        link_test_req.enq(engine_id, tuple2(COH_TEST_REQ_FENCE, unpack(0)));
        engineStates[reqSendState] <= True;
        debugLog.record($format("testFence34: send request to network..., sendState=%03d", reqSendState));
        if (reqSendState == fromInteger(valueof(N_ENGINES)-1))
        begin
            testReqSent <= True;
            reqSendState <= 0;
        end
        else
        begin
            reqSendState <= reqSendState + 1;
        end
    endrule

    rule testReadSeq (state == STATE_test && testInitialized && testState == TEST_READ_SEQ && !testReqSent);
        link_test_req.enq(2, tuple2(COH_TEST_REQ_READ_SEQ, unpack(1)));
        testReqSent <= True;
        engineStates[1] <= True;
        debugLog.record($format("testReadSeq: send request to network..."));
    endrule
    
    rule testReadRand (state == STATE_test && testInitialized && testState == TEST_READ_RAND && !testReqSent);
        link_test_req.enq(2, tuple2(COH_TEST_REQ_READ_RAND, unpack(1)));
        testReqSent <= True;
        engineStates[1] <= True;
        debugLog.record($format("testReadRand: send request to network..."));
    endrule
    
    rule test1WnR (state == STATE_test && testInitialized && testState == TEST_ONE_W_N_R && !testReqSent);
        ENGINE_PORT_NUM engine_id = reqSendState + 1;
        COH_MEM_ENGINE_TEST_REQ engine_req = ?;
        MEM_ADDRESS diff = unpack(0);
        if (reqSendState == fromInteger(valueof(N_ENGINES)-1))
        begin
            engine_req = COH_TEST_REQ_WRITE_RAND;
            diff = unpack(3);
            testReqSent <= True;
            reqSendState <= 0;
        end
        else if (reqSendState == 0)
        begin
            engine_req = COH_TEST_REQ_READ_SEQ;
            reqSendState <= reqSendState + 1;
        end
        else
        begin
            engine_req = COH_TEST_REQ_READ_RAND;
            reqSendState <= reqSendState + 1;
        end
        link_test_req.enq(engine_id, tuple2(engine_req, diff));
        engineStates[reqSendState] <= True;
        debugLog.record($format("test1WnR: send request to network..., sendState=%03d", reqSendState));
    endrule

    rule testTorture (state == STATE_test && testInitialized && (testState == TEST_TORTURE || testState == TEST_TORTURE_FENCE) && !testReqSent);
        let engine_id = reqSendState + 1;
        let engine_req = (testState == TEST_TORTURE)? COH_TEST_REQ_RANDOM : COH_TEST_REQ_RANDOM_FENCE;
        link_test_req.enq(engine_id, tuple2(engine_req, unpack(0)));
        engineStates[reqSendState] <= True;
        debugLog.record($format("test%s: send request to network..., sendState=%03d", 
                        (testState == TEST_TORTURE)? "Torture" : "TortureWithFence",
                        reqSendState));
        if (reqSendState == fromInteger(valueof(N_ENGINES)-1))
        begin
            testReqSent <= True;
            reqSendState <= 0;
        end
        else
        begin
            reqSendState <= reqSendState + 1;
        end
    endrule

    rule testRespWait (state == STATE_test && testInitialized && testReqSent);
        match {.id, .err_num} = link_test_resp.first();
        link_test_resp.deq();
        engineStates[pack(id)-1] <= False;
        let states = readVReg(engineStates);
        states[pack(id)-1] = False;
        debugLog.record($format("testRespWait: receive response from engine %03d", pack(id)-1));
        let new_err_num = errNum + err_num;
        if (!fold(\|| , states)) // end of the test 
        begin
            if (testState == TEST_FENCE4)
            begin
                state <= STATE_finished;
            end
            testState <= unpack(pack(testState) + 1);
            testInitialized <= False;
            testReqSent <= False;
            debugLog.record($format("testRespWait: finish the current test"));
            if (new_err_num != 0)
            begin
                stdio.printf(msgTestErr, list1(zeroExtend(new_err_num)));
            end
            errNum <= 0;
        end
        else
        begin
            errNum <= new_err_num;
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
