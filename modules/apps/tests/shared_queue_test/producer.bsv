//
// Copyright (C) 2013 MIT
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

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "asim/provides/lock_sync_service.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/VDEV_LOCKGROUP.bsh"
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"


typedef enum
{
    PRODUCER_LOCK = 0
}
PRODUCER_LOCK_TYPE
    deriving (Eq, Bits);


interface PRODUCER_IFC#(type t_QUEUE_IDX);
    method Action setTestNum(Bit#(16) num);
    method Action setQueueSize(t_QUEUE_IDX size);
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
    method Bool initialized();
    method Bool done();
endinterface

//
// Producer implementation
//
module [CONNECTED_MODULE] mkProducer#(Integer producerID, 
                                      MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) cohMem,
                                      DEBUG_FILE debugLog,
                                      Bool isMaster)
    // interface:
    (PRODUCER_IFC#(t_QUEUE_IDX))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_QUEUE_IDX, t_QUEUE_IDX_SZ));

    // =======================================================================
    //
    // Lock and synchronization services
    //
    // =======================================================================
    
    DEBUG_FILE lockDebugLog <- mkDebugFile("lock_service_producer_" + integerToString(producerID) + ".out");
    LOCK_IFC#(PRODUCER_LOCK_TYPE) lock <- mkLockNodeDebug(`VDEV_LOCKGROUP_PRODUCER, isMaster, lockDebugLog);
    SYNC_SERVICE_IFC sync <- mkSyncNode(`VDEV_LOCKGROUP_PRODUCER, isMaster); 

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    // Random number generator
    LFSR#(Bit#(16)) lfsr                       <- mkLFSR_16();
    Reg#(Bool) initDone                        <- mkReg(False);
    Reg#(Bool) masterInitDone                  <- mkReg(!isMaster);
    Reg#(Bit#(16)) numTests                    <- mkReg(0);
    Reg#(Bit#(16)) maxTests                    <- mkReg(0);
    Reg#(Tuple2#(Bool, t_QUEUE_IDX)) tail      <- mkReg(unpack(0));
    Reg#(Bit#(32)) cycleCnt                    <- mkReg(0);
    Reg#(WORKING_SET) testAddr                 <- mkReg(0);
    Reg#(t_QUEUE_IDX) maxQueueSize             <- mkReg(unpack(0));
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue  <- mkReg(0);
    
    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && maxTests != 0 && sync.initialized() && pack(maxQueueSize) != 0);
        initDone <= True;
        lfsr.seed(fromInteger(producerID)+1);
        lock.acquireLockReq(PRODUCER_LOCK);
        debugLog.record($format("doInit: initialization done, cycle=0x%11d", cycleCnt));
    endrule

    if (isMaster == True)
    begin
        Reg#(Bit#(2)) masterInitCnt               <- mkReg(0);
        Reg#(Bool) warmCacheDone                  <- mkReg(True);
        Reg#(Bool) warmCacheIssueDone             <- mkReg(False);

        (* mutually_exclusive = "doMasterInit, doInit" *)
        rule doMasterInit (!masterInitDone && warmCacheDone);
            if (masterInitCnt == 0)
            begin
                cohMem.write(unpack(`TAIL_ADDR), resize(pack(tail)));
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("write initial tail value"));
            end
            else if (masterInitCnt == 1 && !cohMem.writePending())
            begin
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("tail initialization done, cycle=0x%11d", cycleCnt));
                debugLog.record($format("start warm up central cache"));
                warmCacheDone <= False;
            end
            else if (masterInitCnt == 2)
            begin
                masterInitCnt  <= 0;
                masterInitDone <= True;
                sync.setSyncBarrier(barrierInitValue);
                debugLog.record($format("central cache warm up done, cycle=0x%11d", cycleCnt));
                debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
            end
        endrule

        // ====================================================================
        //
        // Warm up central cache
        //
        // ====================================================================

        FIFOF#(Tuple2#(WORKING_SET, Bool)) warmCacheReqQ <- mkSizedFIFOF(32);
        rule warmCacheIssue (!masterInitDone && masterInitCnt == 2 && !warmCacheIssueDone);
            t_ADDR r_addr = resize(testAddr);
            cohMem.readReq(r_addr);
            warmCacheReqQ.enq(tuple2(testAddr, testAddr == maxBound));
            testAddr <= testAddr + 1;
            debugLog.record($format("warm up central cache: addr=0x%x", testAddr));
            if (testAddr == maxBound)
            begin
                warmCacheIssueDone <= True;
            end
        endrule
        rule warmCacheRecv (!masterInitDone && masterInitCnt == 2 && !warmCacheDone);
            let resp <- cohMem.readRsp();
            match {.addr, .is_done} = warmCacheReqQ.first();
            warmCacheReqQ.deq();
            debugLog.record($format("warm up central cache resp: addr=0x%x", addr));
            if (is_done)
            begin
                warmCacheDone <= True;
            end
        endrule
    end

    // =======================================================================
    //
    // Tests: producer write data into the shared queue
    //
    // ====================================================================

    FIFOF#(TEST_DATA) producerReqQ   <- mkFIFOF();
    Reg#(Bit#(2)) producerPhase      <- mkReg(0);
    Reg#(Bool) testDone              <- mkReg(False);
    Reg#(Bool) hasLock               <- mkReg(False);

    rule produceItem (initDone && producerReqQ.notFull());
        TEST_DATA d = ?;
        d.idx  = fromInteger(producerID);
        d.data = resize(lfsr.value);
        producerReqQ.enq(d);
        lfsr.next();
    endrule

    rule getProducerLock (initDone && !testDone && producerPhase == 0);
        if (!hasLock)
        begin
            let resp <- lock.lockResp();
            hasLock <= True;
        end
        cohMem.readReq(unpack(`HEAD_ADDR));
        producerPhase <= producerPhase + 1;
    endrule

    rule insertItem (initDone && producerPhase == 1);
        t_DATA head_resp <- cohMem.readRsp();
        Tuple2#(Bool, t_QUEUE_IDX) head_tuple = unpack(resize(pack(head_resp)));
        match {.head_looped, .head_val} = head_tuple;
        match {.tail_looped, .tail_val} = tail;
        if ((head_looped != tail_looped) && (pack(head_val) == pack(tail_val))) // full
        begin
            debugLog.record($format("checkFull: Full! head=0x%x, tail=0x%x", head_val, tail_val));
            producerPhase <= 0;
        end
        else // insert item into shared queue
        begin
            let d = producerReqQ.first();
            producerReqQ.deq();
            cohMem.write(unpack(`START_ADDR + resize(pack(tail_val))), resize(pack(d)));
            cohMem.writeFence();
            debugLog.record($format("enq: producer id=%x, data=0x%x, tail=0x%x", d.idx, d.data, tail_val));
            if (pack(tail_val) == (pack(maxQueueSize)-1))
            begin
                tail <= tuple2(!tail_looped, unpack(0));
            end
            else
            begin
                tail <= tuple2(tail_looped, unpack(pack(tail_val) + 1)); 
            end
            producerPhase <= producerPhase + 1;
        end
    endrule
    
    (* mutually_exclusive = "doInit, insertItem, updateTail" *)
    rule updateTail (initDone && producerPhase == 2);
        match {.tail_looped, .tail_val} = tail;
        numTests <= numTests + 1;
        cohMem.write(unpack(`TAIL_ADDR), resize(pack(tail)));
        debugLog.record($format("updateTail: tail=0x%x, numTests=%8d", tail_val, numTests));
        producerPhase <= 0;
        lock.releaseLock(PRODUCER_LOCK);
        hasLock <= False;
        if (numTests == maxTests - 1)
        begin
            testDone <= True;
            sync.signalSyncReached();
            debugLog.record($format("updateTail: test done... send synchronization signal"));
        end
        else
        begin
            lock.acquireLockReq(PRODUCER_LOCK); 
        end
    endrule
    
    // =======================================================================
    //
    // Master node: wait for all producers completion
    //
    // ====================================================================
    
    Reg#(Bool) allDone <- mkReg(False);
    
    if (isMaster == True)
    begin
        rule waitForAllDone (True);
            sync.waitForSync();
            allDone <= True;
            debugLog.record($format("waitForAllDone: all producers have finished..."));
        endrule
    end

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action setTestNum(Bit#(16) num);
        maxTests <= num;
        debugLog.record($format("setTestNum: maxTests = %08d", num));
    endmethod

    method Action setQueueSize(t_QUEUE_IDX size);
        maxQueueSize <= size;
        debugLog.record($format("setTestNum: maxQueueSize = %08d", size));
    endmethod

    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
        if (isMaster)
        begin
            barrierInitValue <= barrier;
        end
    endmethod

    method Bool initialized() = initDone;
    method Bool done() = allDone;

endmodule

