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
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"


//
// Implement shared queue (producer-consumer model) to test coherent scratchpads' functionality
// This implementation does not use the lock and synchronization services. It uses 
// global arbiters instead and therefore cannot be split across FPGAs.
// 
module [CONNECTED_MODULE] mkSharedQueueTestNoLock ()
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
    
    COH_SCRATCH_CLIENT_CONFIG clientConf = defaultValue;
    clientConf.cacheMode = (`SHARED_QUEUE_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
    mkCoherentScratchpadController(`VDEV_SCRATCH_SHARED_QUEUE_DATA, `VDEV_SCRATCH_SHARED_QUEUE_BITS, addr_size, data_size, controllerConf);
    
    Vector#(N_PRODUCERS, DEBUG_FILE) debugLogsP = newVector();
    Vector#(N_PRODUCERS, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA)) memoriesP = newVector();
    // Random number generators
    Vector#(N_PRODUCERS, LFSR#(Bit#(16))) lfsrs = newVector();

    for(Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
    begin
        debugLogsP[p] <- mkDebugFile("producer_"+integerToString(p)+".out");
        memoriesP[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_SHARED_QUEUE_DATA, p, clientConf, debugLogsP[p]);
        lfsrs[p] <- mkLFSR_16();
    end

    Vector#(N_CONSUMERS, DEBUG_FILE) debugLogsC = newVector();
    Vector#(N_CONSUMERS, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, t_MEM_DATA)) memoriesC = newVector();

    for(Integer p = 0; p < valueOf(N_CONSUMERS); p = p + 1)
    begin
        debugLogsC[p] <- mkDebugFile("consumer_"+integerToString(p)+".out");
        memoriesC[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_SHARED_QUEUE_DATA, (p + valueOf(N_PRODUCERS)), clientConf, debugLogsC[p]);
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
    let msgData <- getGlobalStringUID("deq: consumer id=%x, producer id=%x, data=0x%x\n");
    let msgDataErr <- getGlobalStringUID("deq: consumer id=%x, producer id=%x, data=0x%x, (expected: p_id=%x, data=0x%x) ERROR! \n");
    let msgInit <- getGlobalStringUID("sharedQueueTest: start\n");
    let msgInitDone <- getGlobalStringUID("sharedQueueTest: initialization done, cycle: %012d\n");
    // let msgDone <- getGlobalStringUID("sharedQueueTest: done (# test: %08d, queue size: %08d), cycle: %012d, test cycle count: %012d, totalLatency: %012d\n");
    let msgDone <- getGlobalStringUID("sharedQueueTest: done (# test: %08d, # producers: %03d, # consumers: %03d, queue size: %08d), cycle: %012d, test cycle count: %012d\n");
    //let msgDone <- getGlobalStringUID("sharedQueueTest: done\n");
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    Reg#(Bool) done                               <- mkReg(False);
    Reg#(Bool) warmCacheIssueDone                 <- mkReg(False);
    Reg#(Bool) warmCacheDone                      <- mkReg(True);
    Reg#(Bit#(16)) numTests                       <- mkReg(0);
    Reg#(Bit#(16)) maxTests                       <- mkReg(`TEST_NUM);
    Reg#(Bit#(16)) completeTests                  <- mkReg(0);
    FIFO#(Tuple2#(TEST_DATA, Bit#(32))) expected  <- mkSizedBRAMFIFO(valueOf(n_ENTRIES));
    COUNTER#(t_QUEUE_IDX_SZ) numItems             <- mkLCounter(0);
    Reg#(t_QUEUE_IDX) maxQueueSize                <- mkReg(fromInteger(valueOf(n_ENTRIES)));
    Reg#(Tuple2#(Bool, t_QUEUE_IDX)) head         <- mkReg(unpack(0));
    Reg#(Tuple2#(Bool, t_QUEUE_IDX)) tail         <- mkReg(unpack(0));
    Reg#(Bit#(3)) initCnt                         <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt                       <- mkReg(0);
    Reg#(Bit#(32)) initCycleCnt                   <- mkReg(0);
    Reg#(Bit#(48)) totalLatency                   <- mkReg(0);
    Reg#(WORKING_SET) testAddr                    <- mkReg(0);

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule

    rule doInit (state == STATE_init && warmCacheDone);
        if (initCnt == 0)
        begin
            linkStarterStartRun.deq();
            initCnt <= initCnt + 1;
            stdio.printf(msgInit, List::nil);
        end
        else if (initCnt == 1)
        begin
            for(Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
            begin
                lfsrs[p].seed(fromInteger(p+1));
            end
            memoriesP[0].write(`TAIL_ADDR, zeroExtend(pack(tail)));
            initCnt <= initCnt + 1;
            debugLog.record($format("write initial tail value"));
        end
        else if (initCnt == 2)
        begin
            memoriesC[0].write(`HEAD_ADDR, zeroExtend(pack(head)));
            initCnt <= initCnt + 1;
            debugLog.record($format("write initial head value"));
        end
        else if (initCnt == 3 && !memoriesP[0].writePending() && !memoriesC[0].writePending())
        begin
            initCnt <= initCnt + 1;
            maxTests <= testNumParam;
            warmCacheDone <= False;
            maxQueueSize <= unpack(queueSizeNumParam);
            debugLog.record($format("initialization done, cycle=0x%11d", cycleCnt));
            debugLog.record($format("start warm up central cache"));
        end
        else if (initCnt == 4)
        begin    
            initCnt <= 0;
            state <= STATE_test;
            initCycleCnt <= cycleCnt;
            debugLog.record($format("central cache warm up done, cycle=0x%11d", cycleCnt));
            stdio.printf(msgInitDone, list1(zeroExtend(cycleCnt)));
        end
    endrule

    // ====================================================================
    //
    // Warm up central cache
    //
    // ====================================================================

    FIFOF#(Tuple2#(WORKING_SET, Bool)) warmCacheReqQ <- mkSizedFIFOF(32);

    rule warmCacheIssue (state == STATE_init && initCnt == 4 && !warmCacheIssueDone);
        MEM_ADDRESS r_addr = zeroExtend(testAddr);
        memoriesP[0].readReq(r_addr);
        warmCacheReqQ.enq(tuple2(testAddr, testAddr == maxBound));
        testAddr <= testAddr + 1;
        debugLog.record($format("warm up central cache: addr=0x%x", testAddr));
        if (testAddr == maxBound)
        begin
            warmCacheIssueDone <= True;
        end
    endrule
    rule warmCacheRecv (state == STATE_init && initCnt == 4 && !warmCacheDone);
        let resp <- memoriesP[0].readRsp();
        match {.addr, .is_done} = warmCacheReqQ.first();
        warmCacheReqQ.deq();
        debugLog.record($format("warm up central cache resp: addr=0x%x", addr));
        if (is_done)
        begin
            warmCacheDone <= True;
        end
    endrule

    // ====================================================================
    //
    // Producers write data into the shared queue
    //
    // ====================================================================

    Vector#(N_PRODUCERS, FIFOF#(TEST_DATA)) producers <- replicateM(mkFIFOF());
    Vector#(N_PRODUCERS, Reg#(Bit#(16))) numTestsP    <- replicateM(mkReg(0));
    Reg#(PRODUCER_IDX) producer                       <- mkReg(0); 
    Reg#(Bit#(2)) producerPhase                       <- mkReg(0);
    LOCAL_ARBITER#(N_PRODUCERS) producerArb           <- mkLocalArbiter();
    Reg#(Bool) producerAllDone                        <- mkReg(False);

    for (Integer r = 0; r < valueOf(N_PRODUCERS); r = r + 1)
    begin
        rule produceItem (state == STATE_test && producers[r].notFull() && numTestsP[r] < maxTests);
            TEST_DATA d = ?;
            d.idx  = fromInteger(r);
            d.data = resize(lfsrs[r].value);
            producers[r].enq(d);
            lfsrs[r].next();
            numTestsP[r] <= numTestsP[r] + 1;
            debugLog.record($format("produceItem: producer id=%x, numTests=%08d, maxTests=%08d", 
                            r, numTestsP[r], maxTests));
        endrule
    end

    rule pickProducer (!done && state == STATE_test && producerPhase == 0);
        // Note which producers have a item available
        LOCAL_ARBITER_CLIENT_MASK#(N_PRODUCERS) req = newVector();
        for (Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
        begin
            req[p] = producers[p].notEmpty();
        end
        let winner_idx <- producerArb.arbitrate(req, False);
        if (winner_idx matches tagged Valid .idx &&& producers[idx].notEmpty())
        begin
            debugLog.record($format("pickProducer: producer id=%x", idx));
            producer <= zeroExtend(pack(idx));
            producerPhase <= producerPhase + 1;
            memoriesP[idx].readReq(`HEAD_ADDR);
        end
    endrule

    rule insertItem (producerPhase == 1);
        t_MEM_DATA head_resp <- memoriesP[producer].readRsp();
        Tuple2#(Bool, t_QUEUE_IDX) head_tuple = unpack(truncate(head_resp));
        match {.head_looped, .head_val} = head_tuple;
        match {.tail_looped, .tail_val} = tail;
        if ((head_looped != tail_looped) && (head_val == tail_val)) // full
        begin
            debugLog.record($format("checkFull: Full! head=0x%x, tail=0x%x, numItems=%x ", head_val, tail_val, numItems.value()));
            producerPhase <= 0;
        end
        else // insert item into shared queue
        begin
            let d = producers[producer].first();
            producers[producer].deq();
            memoriesP[producer].write(`START_ADDR + zeroExtend(pack(tail_val)), zeroExtend(pack(d)));
            memoriesP[producer].writeFence();
            expected.enq(tuple2(d, cycleCnt));
            debugLog.record($format("enq[%8x]: producer id=%x, data=0x%x, tail=0x%x", numItems.value(), d.idx, d.data, tail_val));
            if (tail_val == (maxQueueSize-1))
            begin
                tail <= tuple2(!tail_looped, 0);
            end
            else
            begin
                tail <= tuple2(tail_looped, tail_val + 1); 
            end
            producerPhase <= producerPhase + 1;
        end
    endrule
    
    (* mutually_exclusive = "doInit, insertItem, updateTail" *)
    rule updateTail (producerPhase == 2);
        match {.tail_looped, .tail_val} = tail;
        numItems.up();
        numTests <= numTests + 1;
        memoriesP[producer].write(`TAIL_ADDR, zeroExtend(pack(tail)));
        debugLog.record($format("updateTail: tail=0x%x, numTests=%8d", tail_val, numTests));
        producerPhase <= 0;
        // check producer done
        Bool done_signal = True;
        for(Integer p = 0; p < valueOf(N_PRODUCERS); p = p + 1)
        begin
            done_signal = done_signal && (!producers[p].notEmpty) && (numTestsP[p] == maxTests);
        end
        if (done_signal)
        begin
            done <= True;
            debugLog.record($format("updateTail: producer all complete!"));
        end
    endrule

    // ====================================================================
    //
    // Consumers read data from the shared queue
    //
    // ====================================================================

    Vector#(N_CONSUMERS, FIFOF#(Tuple2#(TEST_DATA, Bit#(32)))) consumers  <- replicateM(mkSizedFIFOF(8));
    Vector#(N_CONSUMERS, FIFOF#(Bool)) consumerReqInfo                    <- replicateM(mkSizedFIFOF(8));
    Reg#(CONSUMER_IDX) consumer                                           <- mkReg(0); 
    Reg#(Bit#(2)) consumerPhase                                           <- mkReg(0);
    LOCAL_ARBITER#(N_CONSUMERS) consumerArb                               <- mkLocalArbiter();
    PulseWire queueNotEmptyW                                              <- mkPulseWire();
    Reg#(Bool) queueNotEmpty                                              <- mkReg(False);

    for (Integer c = 0; c < valueOf(N_CONSUMERS); c = c + 1)
    begin
        rule recvItem (state == STATE_test && consumers[c].notEmpty() && consumerReqInfo[c].first());
            match {.ans, .s_cycle} = consumers[c].first();
            consumers[c].deq();
            let resp <- memoriesC[c].readRsp();
            consumerReqInfo[c].deq();
            TEST_DATA d = unpack(truncate(resp));

            if (pack(d) != pack(ans)) // Error
            begin
                debugLog.record($format("recvItem: consumer idx=%x, producer idx=%x, data=0x%x, (expected: p_id=%x, data=0x%x) ERROR!", 
                                c, d.idx, d.data, ans.idx, ans.data));
                stdio.printf(msgDataErr, list5(fromInteger(c), zeroExtend(d.idx), resize(pack(d.data)), zeroExtend(ans.idx), zeroExtend(ans.data)));
                // stdio.printf(msgDataErr, list5(fromInteger(c), d.idx, pack(d.data), ans.idx, ans.data));
            end
            else
            begin
                debugLog.record($format("recvItem: consumer idx=%x, producer idx=%x, data=0x%x, latency=%d, completeTests=%8d", 
                                c, d.idx, d.data, (cycleCnt-s_cycle), completeTests));
                if (verbose)
                begin
                    stdio.printf(msgData, list3(fromInteger(c), zeroExtend(d.idx), resize(pack(d.data))));
                end
            end
            completeTests <= completeTests + 1;
            totalLatency <= totalLatency + zeroExtend(cycleCnt - s_cycle);
            if ( (completeTests == numTests - 1) && done)
            begin
                state <= STATE_finished;
            end
        endrule
    end

    rule pickConsumer (state == STATE_test && consumerPhase == 0);
        // Note which consumers have available slots
        LOCAL_ARBITER_CLIENT_MASK#(N_CONSUMERS) req = newVector();
        for (Integer p = 0; p < valueOf(N_CONSUMERS); p = p + 1)
        begin
            req[p] = consumers[p].notFull();
        end
        let winner_idx <- consumerArb.arbitrate(req, False);
        if (winner_idx matches tagged Valid .idx &&& consumers[idx].notFull())
        begin
            debugLog.record($format("pickConsumer: consumer id=%x", idx));
            consumer <= zeroExtend(pack(idx));
            consumerPhase <= consumerPhase + 1;
            memoriesC[idx].readReq(`TAIL_ADDR);
            consumerReqInfo[idx].enq(False);
        end
    endrule

    rule checkEmpty (consumerPhase == 1 && !consumerReqInfo[consumer].first());
        match {.head_looped, .head_val} = head;
        t_MEM_DATA tail_resp <- memoriesC[consumer].readRsp();
        Tuple2#(Bool, t_QUEUE_IDX) tail_tuple = unpack(truncate(tail_resp));
        match {.tail_looped, .tail_val} = tail_tuple;
        consumerReqInfo[consumer].deq();
        if ((head_looped == tail_looped) && (head_val == tail_val)) // empty
        begin
            debugLog.record($format("checkEmpty: Empty! head=0x%x, tail=0x%x, numItems=%x ", head_val, tail_val, numItems.value()));
            consumerPhase <= 0;
        end
        else
        begin
            debugLog.record($format("checkEmpty: Not empty! head=0x%x, tail=0x%x, numItems=%x ", head_val, tail_val, numItems.value()));
            queueNotEmptyW.send();
            queueNotEmpty <= True;
        end
    endrule 

    rule popItem (consumerPhase == 1 && (queueNotEmptyW || queueNotEmpty));    
        match {.head_looped, .head_val} = head;
        memoriesC[consumer].readReq(`START_ADDR + zeroExtend(pack(head_val)));
        memoriesC[consumer].readFence();
        consumerReqInfo[consumer].enq(True);
        let d = expected.first();
        consumers[consumer].enq(d);
        expected.deq();
        debugLog.record($format("deq: consumer id=%x, head=0x%x, numItems=%x", consumer, head_val, numItems.value()));
        if (head_val == (maxQueueSize-1))
        begin
            head <= tuple2(!head_looped, 0);
        end
        else
        begin
            head <= tuple2(head_looped, head_val + 1); 
        end
        consumerPhase <= consumerPhase + 1;
    endrule

    (* mutually_exclusive = "doInit, checkEmpty, popItem, updateHead" *)
    rule updateHead (consumerPhase == 2);
        match {.head_looped, .head_val} = head;
        numItems.down();
        memoriesC[consumer].write(`HEAD_ADDR, unpack(zeroExtend(pack(head))));
        debugLog.record($format("updateHead: head=0x%x", head_val));
        consumerPhase <= 0;
        queueNotEmpty <= False;
    endrule

    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        // stdio.printf(msgDone, List::nili);
        // stdio.printf(msgDone, list6(zeroExtend(maxTests), zeroExtend(pack(maxQueueSize)), zeroExtend(cycleCnt), zeroExtend(cycleCnt-initCycleCnt), zeroExtend(totalLatency)));
        stdio.printf(msgDone, list6(zeroExtend(maxTests), fromInteger(valueOf(N_PRODUCERS)), fromInteger(valueOf(N_CONSUMERS)), zeroExtend(pack(maxQueueSize)), zeroExtend(cycleCnt), zeroExtend(cycleCnt-initCycleCnt)));
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule
