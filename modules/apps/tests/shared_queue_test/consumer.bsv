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

typedef enum
{
    CONSUMER_LOCK = 0
}
CONSUMER_LOCK_TYPE
    deriving (Eq, Bits);

interface CONSUMER_IFC#(type t_QUEUE_IDX);
    method Action setQueueSize(t_QUEUE_IDX size);
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
    method Action producerDone();
    method Bool initialized();
    method Bool done();
endinterface

//
// Consumer implementation
//
module [CONNECTED_MODULE] mkConsumer#(Integer consumerID,
                                      MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) cohMem,
                                      DEBUG_FILE debugLog,
                                      Bool isMaster)
    // interface:
    (CONSUMER_IFC#(t_QUEUE_IDX))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_QUEUE_IDX, t_QUEUE_IDX_SZ));

    // =======================================================================
    //
    // Lock and synchronization services
    //
    // =======================================================================
    
    DEBUG_FILE lockDebugLog <- mkDebugFile("lock_service_consumer_" + integerToString(consumerID) + ".out");
    LOCK_IFC#(CONSUMER_LOCK_TYPE) lock <- mkLockNodeDebug(`VDEV_LOCKGROUP_CONSUMER, isMaster, lockDebugLog);
    SYNC_SERVICE_IFC sync <- mkSyncNode(`VDEV_LOCKGROUP_CONSUMER, isMaster); 

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool) initDone                       <- mkReg(False);
    Reg#(Bool) masterInitDone                 <- mkReg(!isMaster);
    Reg#(Tuple2#(Bool, t_QUEUE_IDX)) head     <- mkReg(unpack(0));
    Reg#(Bit#(32)) cycleCnt                   <- mkReg(0);
    Reg#(WORKING_SET) testAddr                <- mkReg(0);
    Reg#(t_QUEUE_IDX) maxQueueSize            <- mkReg(unpack(0));
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue <- mkReg(0);
    
    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && sync.initialized() && pack(maxQueueSize) != 0);
        initDone <= True;
        debugLog.record($format("initialization done, cycle=0x%11d", cycleCnt));
        lock.acquireLockReq(CONSUMER_LOCK);
    endrule

    if (isMaster == True)
    begin
        Reg#(Bit#(1)) masterInitCnt <- mkReg(0);
        (* mutually_exclusive = "doMasterInit, doInit" *)
        rule doMasterInit (!masterInitDone);
            if (masterInitCnt == 0)
            begin
                cohMem.write(unpack(`HEAD_ADDR), resize(pack(head)));
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("write initial head value"));
            end
            else if (masterInitCnt == 1 && !cohMem.writePending())
            begin
                masterInitDone <= True;
                masterInitCnt  <= 0;
                sync.setSyncBarrier(barrierInitValue);
                debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
            end
        endrule
    end

    // =======================================================================
    //
    // Tests: consumers read data from the shared queue
    //
    // =======================================================================

    FIFOF#(Bool) consumerReqInfo     <- mkSizedFIFOF(8);
    Reg#(Bit#(2)) consumerPhase      <- mkReg(0);
    PulseWire queueNotEmptyW         <- mkPulseWire();
    Reg#(Bool) queueNotEmpty         <- mkReg(False);
    Reg#(Bool) testDone              <- mkReg(False);
    Reg#(Bool) hasLock               <- mkReg(False);
    Reg#(Bool) producerIsDone        <- mkReg(False);

    rule waitForProducer (!producerIsDone);
        sync.waitForSync();
        producerIsDone <= True;
        debugLog.record($format("waitForProducer: producers are done..."));
    endrule

    rule recvItem (initDone && consumerReqInfo.first());
        let resp <- cohMem.readRsp();
        consumerReqInfo.deq();
        TEST_DATA d = unpack(resize(pack(resp)));
        debugLog.record($format("recvItem: consumer idx=%x, producer idx=%x, data=0x%x", consumerID, d.idx, d.data));
    endrule

    rule getConsumerLock (initDone && !testDone && consumerPhase == 0);
        if (!hasLock)
        begin
            let r <- lock.lockResp();
            hasLock <= True;
        end
        consumerPhase <= consumerPhase + 1;
        cohMem.readReq(unpack(`TAIL_ADDR));
        consumerReqInfo.enq(False);
    endrule

    rule checkEmpty (consumerPhase == 1 && !consumerReqInfo.first());
        match {.head_looped, .head_val} = head;
        t_DATA tail_resp <- cohMem.readRsp();
        Tuple2#(Bool, t_QUEUE_IDX) tail_tuple = unpack(resize(tail_resp));
        match {.tail_looped, .tail_val} = tail_tuple;
        consumerReqInfo.deq();
        if ((head_looped == tail_looped) && (pack(head_val) == pack(tail_val))) // empty
        begin
            debugLog.record($format("checkEmpty: Empty! head=0x%x, tail=0x%x", head_val, tail_val));
            consumerPhase <= 0;
            if (producerIsDone)
            begin
                lock.releaseLock(CONSUMER_LOCK);
                hasLock <= False;
                testDone <= True;
                debugLog.record($format("checkEmpty: Empty! test finished"));
            end
        end
        else
        begin
            debugLog.record($format("checkEmpty: Not empty! head=0x%x, tail=0x%x", head_val, tail_val));
            queueNotEmptyW.send();
            queueNotEmpty <= True;
        end
    endrule 

    rule popItem (consumerPhase == 1 && (queueNotEmptyW || queueNotEmpty));    
        match {.head_looped, .head_val} = head;
        cohMem.readReq(unpack(`START_ADDR + resize(pack(head_val))));
        cohMem.readFence();
        consumerReqInfo.enq(True);
        debugLog.record($format("deq: consumer id=%x, head=0x%x", consumerID, head_val));
        if (pack(head_val) == (pack(maxQueueSize)-1))
        begin
            head <= tuple2(!head_looped, unpack(0));
        end
        else
        begin
            head <= tuple2(head_looped, unpack(pack(head_val) + 1)); 
        end
        consumerPhase <= consumerPhase + 1;
    endrule

    (* mutually_exclusive = "doInit, checkEmpty, popItem, updateHead" *)
    rule updateHead (consumerPhase == 2);
        match {.head_looped, .head_val} = head;
        cohMem.write(unpack(`HEAD_ADDR), unpack(resize(pack(head))));
        debugLog.record($format("updateHead: head=0x%x", head_val));
        consumerPhase <= 0;
        queueNotEmpty <= False;
        lock.releaseLock(CONSUMER_LOCK);
        lock.acquireLockReq(CONSUMER_LOCK);
        hasLock <= False;
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

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
    
    method Action producerDone();
        if (isMaster)
        begin
            sync.signalSyncReached();
            debugLog.record($format("producerDone: notify consumers that producers are done"));
        end
    endmethod

    method Bool initialized() = initDone;

    method Bool done() = testDone;
endmodule

