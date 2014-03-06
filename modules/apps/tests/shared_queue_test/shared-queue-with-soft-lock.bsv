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
`include "asim/dict/VDEV_LOCKGROUP.bsh"
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"

//
// Implement shared queue (producer-consumer model) to test coherent scratchpads' functionality
// This implementation uses lock and synchronization services.
//
module [CONNECTED_MODULE] mkSharedQueueTestWithSoftLock ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_DATA_SZ),
              NumAlias#(TExp#(SHARED_QUEUE_SIZE_LOG), n_ENTRIES),
              NumAlias#(TLog#(TAdd#(n_ENTRIES,1)), t_QUEUE_IDX_SZ),
              Max#(t_DATA_SZ, TAdd#(t_QUEUE_IDX_SZ,1), t_MEM_DATA_SZ),
              Alias#(UInt#(t_QUEUE_IDX_SZ), t_QUEUE_IDX),
              Alias#(Bit#(t_MEM_DATA_SZ), t_MEM_DATA));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate coherent scratchpads (producers and consumers)
    //
    COH_SCRATCH_CONTROLLER_CONFIG controllerConf = defaultValue;
    controllerConf.cacheMode = (`SHARED_QUEUE_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
    mkCoherentScratchpadController(`VDEV_SCRATCH_SHARED_QUEUE_DATA, `VDEV_SCRATCH_SHARED_QUEUE_BITS, addr_size, data_size, controllerConf);

    COH_SCRATCH_CLIENT_CONFIG clientConf = defaultValue;
    clientConf.cacheMode = (`SHARED_QUEUE_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    Vector#(N_PRODUCERS, DEBUG_FILE) debugLogsP = newVector();
    Vector#(N_PRODUCERS, DEBUG_FILE) debugLogsPM = newVector();
    Vector#(N_PRODUCERS, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA)) memoriesP = newVector();
    Vector#(N_PRODUCERS, PRODUCER_IFC#(t_QUEUE_IDX)) producers = newVector();

    for(Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
    begin
        debugLogsP[p] <- mkDebugFile("producer_"+integerToString(p)+".out");
        debugLogsPM[p] <- mkDebugFile("producer_memory_"+integerToString(p)+".out");
        memoriesP[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_SHARED_QUEUE_DATA, p, clientConf, debugLogsPM[p]);
        producers[p] <- mkProducerSoftLock(p, memoriesP[p], debugLogsP[p], p == 0);
    end

    Vector#(N_CONSUMERS, DEBUG_FILE) debugLogsC = newVector();
    Vector#(N_CONSUMERS, DEBUG_FILE) debugLogsCM = newVector();
    Vector#(N_CONSUMERS, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA)) memoriesC = newVector();
    Vector#(N_CONSUMERS, CONSUMER_IFC#(t_QUEUE_IDX)) consumers = newVector();

    for(Integer p = 0; p < valueOf(N_CONSUMERS); p = p + 1)
    begin
        debugLogsC[p] <- mkDebugFile("consumer_"+integerToString(p)+".out");
        debugLogsCM[p] <- mkDebugFile("consumer_memory_"+integerToString(p)+".out");
        memoriesC[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_SHARED_QUEUE_DATA, (p + valueOf(N_PRODUCERS)), clientConf, debugLogsCM[p]);
        consumers[p] <- mkConsumerSoftLock(p, memoriesC[p], debugLogsC[p], p == 0);
    end

    DEBUG_FILE debugLog <- mkDebugFile("shared_queue_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Verbose mode
    //  0 -- quiet
    //  1 -- verbose
    Param#(1) verboseMode <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_SHARED_QUEUE_TEST_VERBOSE, paramNode);
    let verbose = verboseMode == 1;

    Param#(16) testNumParam <-mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_SHARED_QUEUE_TEST_TEST_NUM, paramNode);
    Param#(16) queueSizeNumParam <-mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_SHARED_QUEUE_TEST_QUEUE_SIZE, paramNode);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(CYCLE_COUNTER) cycle <- mkReg(0);
    Reg#(STATE) state <- mkReg(STATE_init);

    // Messages
    let msgInit <- getGlobalStringUID("sharedQueueTest: start\n");
    let msgInitDone <- getGlobalStringUID("sharedQueueTest: initialization done, cycle: %012d\n");
    let msgDone <- getGlobalStringUID("sharedQueueTest: done (# test: %08d, # producers: %03d, # consumers: %03d, queue size: %08d), cycle: %012d, test cycle count: %012d\n");
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    Reg#(Bit#(3)) initCnt             <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt           <- mkReg(0);
    Reg#(Bit#(32)) initCycleCnt       <- mkReg(0);
    Reg#(Bool) producerAllDone        <- mkReg(False);
    Reg#(Bit#(16)) maxTests           <- mkReg(0);
    Reg#(t_QUEUE_IDX) maxQueueSize    <- mkReg(0);

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule

    rule doInit0 (state == STATE_init && initCnt == 0);
        linkStarterStartRun.deq();
        initCnt <= initCnt + 1;
        stdio.printf(msgInit, List::nil);
        debugLog.record($format("doInit: initCnt = 0"));
    endrule

    rule doInit1 (state == STATE_init && initCnt == 1);
        for(Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
        begin 
            producers[p].setTestNum(testNumParam);
            producers[p].setQueueSize(unpack(queueSizeNumParam));
        end
        for(Integer c = 0; c < valueOf(N_CONSUMERS); c = c + 1)
        begin 
            consumers[c].setQueueSize(unpack(queueSizeNumParam));
        end
        initCnt <= initCnt + 1;
        maxTests <= testNumParam;
        maxQueueSize <= unpack(queueSizeNumParam);
        debugLog.record($format("doInit: initCnt = 1"));
    endrule

    rule doInit2 (state == STATE_init && initCnt == 2);
        Vector#(N_PRODUCERS, Bool) done_p = newVector();
        Vector#(N_CONSUMERS, Bool) done_c = newVector();
        for(Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
        begin 
            done_p[p] = producers[p].initialized(); 
        end
        for(Integer c = 0; c < valueOf(N_CONSUMERS); c = c + 1)
        begin 
            done_c[c] = consumers[c].initialized();
        end
        if (fold(\&& , done_p) && fold(\&& , done_c)) // all initialized
        begin
            initCnt <= 0;
            state <= STATE_test;
            initCycleCnt <= cycleCnt;
            stdio.printf(msgInitDone, list1(zeroExtend(cycleCnt)));
            debugLog.record($format("initialization done, cycle=0x%11d", cycleCnt));
        end
    endrule

    rule waitForProducer (state == STATE_test && !producerAllDone);
        if (producers[0].done())
        begin
            consumers[0].producerDone();
            producerAllDone <= True;
        end
    endrule

    rule waitForConsumer (state == STATE_test);
        if (consumers[0].done())
        begin
            state <= STATE_finished;
        end
    endrule

    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        stdio.printf(msgDone, list6(zeroExtend(maxTests), fromInteger(valueOf(N_PRODUCERS)), fromInteger(valueOf(N_CONSUMERS)), zeroExtend(pack(maxQueueSize)), zeroExtend(cycleCnt), zeroExtend(cycleCnt-initCycleCnt)));
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule

