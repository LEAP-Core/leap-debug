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

//
// Consumer implementation
//
module [CONNECTED_MODULE] mkConsumerSoftLock#(Integer consumerID,
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
    // Initialization
    //
    // =======================================================================

    Reg#(Bool) initDone                       <- mkReg(False);
    Reg#(Bool) masterInitDone                 <- mkReg(False);
    Reg#(Tuple2#(Bool, t_QUEUE_IDX)) head     <- mkReg(unpack(0));
    Reg#(Bit#(32)) cycleCnt                   <- mkReg(0);
    Reg#(WORKING_SET) testAddr                <- mkReg(0);
    Reg#(t_QUEUE_IDX) maxQueueSize            <- mkReg(unpack(0));
    Reg#(Bit#(3)) masterInitCnt               <- mkReg(0);
    
    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && pack(maxQueueSize) != 0);
        initDone <= True;
        debugLog.record($format("initialization done, cycle=0x%11d", cycleCnt));
        cohMem.testAndSetReq(unpack(`HEAD_LOCK_ADDR), unpack(1));
    endrule

    if (isMaster == True)
    begin
        (* mutually_exclusive = "doMasterInit, doInit" *)
        rule doMasterInit (!masterInitDone);
            if (masterInitCnt == 0)
            begin
                cohMem.write(unpack(`HEAD_ADDR), resize(pack(head)));
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("write initial head value"));
            end
            else if (masterInitCnt == 1)
            begin
                cohMem.write(unpack(`HEAD_LOCK_ADDR), unpack(0));
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("write initial head lock value"));
            end
            else if (masterInitCnt == 2)
            begin
                cohMem.write(unpack(`CONSUMER_DONE_ADDR), unpack(0));
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("write initial done signal value"));
            end
            else if (masterInitCnt == 3)
            begin
                cohMem.write(unpack(`CONSUMER_DONE_LOCK_ADDR), unpack(0));
                masterInitCnt <= masterInitCnt + 1;
                debugLog.record($format("write initial done lock value"));
            end
            else if (masterInitCnt == 4 && !cohMem.writePending())
            begin
                masterInitDone <= True;
                masterInitCnt  <= 0;
                cohMem.write(unpack(`INIT_CLIENT_DONE_ADDR), unpack(1));
                debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
            end
        endrule
    end
    else
    begin
        rule checkMasterInit0(!masterInitDone && masterInitCnt == 0);
            cohMem.readReq(unpack(`INIT_CLIENT_DONE_ADDR));
            masterInitCnt <= masterInitCnt + 1;
        endrule
        rule checkMasterInit1(!masterInitDone && masterInitCnt == 1);
            let resp <- cohMem.readRsp();
            if (pack(resp) == 1)
            begin
                masterInitDone <= True;
            end
            else
            begin
                masterInitCnt <= 0;
            end
        endrule
    end

    // =======================================================================
    //
    // Tests: consumers read data from the shared queue
    //
    // =======================================================================

    FIFOF#(Bool) consumerReqInfo     <- mkSizedFIFOF(8);
    Reg#(Bit#(3)) consumerPhase      <- mkReg(0);
    PulseWire queueNotEmptyW         <- mkPulseWire();
    Reg#(Bool) queueNotEmpty         <- mkReg(False);
    Reg#(Bool) testDone              <- mkReg(False);
    Reg#(Bool) hasLock               <- mkReg(False);
    Reg#(Bool) producerIsDone        <- mkReg(False);

    rule recvItem (initDone && consumerReqInfo.first());
        let resp <- cohMem.readRsp();
        consumerReqInfo.deq();
        TEST_DATA d = unpack(resize(pack(resp)));
        debugLog.record($format("recvItem: consumer idx=%x, producer idx=%x, data=0x%x", consumerID, d.idx, d.data));
    endrule

    rule getConsumerLock (initDone && !testDone && consumerPhase == 0);
        if (!hasLock)
        begin
            let resp <- cohMem.testAndSetRsp();
            debugLog.record($format("getConsumerLock: testAndSetRsp=0x%x", resp));
            if (pack(resp) == 0) // get lock!
            begin
                hasLock <= True;
                cohMem.readReq(unpack(`HEAD_ADDR));
                consumerPhase <= consumerPhase + 1;
                consumerReqInfo.enq(False);
                debugLog.record($format("getConsumerLock: get head lock!"));
            end
            else
            begin
                cohMem.testAndSetReq(unpack(`HEAD_LOCK_ADDR), unpack(1));
                debugLog.record($format("getConsumerLock: does not get head lock, retry..."));
            end
        end
        else
        begin
            cohMem.readReq(unpack(`TAIL_ADDR));
            consumerReqInfo.enq(False);
            consumerPhase <= 2;
        end
    endrule

    rule getTailAddr (initDone && consumerPhase == 1 && !consumerReqInfo.first());
        let resp <- cohMem.readRsp(); 
        consumerReqInfo.deq();
        head <= unpack(resize(pack(resp)));
        cohMem.readReq(unpack(`TAIL_ADDR));
        consumerReqInfo.enq(False);
        consumerPhase <= consumerPhase + 1;
    endrule
    
    rule checkEmpty (initDone && consumerPhase == 2 && !consumerReqInfo.first());
        match {.head_looped, .head_val} = head;
        t_DATA tail_resp <- cohMem.readRsp();
        Tuple3#(Bool, t_QUEUE_IDX, Bool) tail_tuple = unpack(resize(tail_resp));
        match {.tail_looped, .tail_val, .tail_done} = tail_tuple;
        consumerReqInfo.deq();
        if ((head_looped == tail_looped) && (pack(head_val) == pack(tail_val))) // empty
        begin
            debugLog.record($format("checkEmpty: Empty! head=0x%x, tail=0x%x", head_val, tail_val));
            consumerPhase <= 0;
            if (tail_done) //producerIsDone
            begin
                cohMem.write(unpack(`HEAD_LOCK_ADDR), unpack(0));
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

    rule popItem (initDone && consumerPhase == 2 && (queueNotEmptyW || queueNotEmpty));    
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

    (* mutually_exclusive = "doInit, checkEmpty, updateHead" *)
    rule updateHead (initDone && consumerPhase == 3);
        match {.head_looped, .head_val} = head;
        cohMem.write(unpack(`HEAD_ADDR), unpack(resize(pack(head))));
        debugLog.record($format("updateHead: head=0x%x", head_val));
        consumerPhase <= consumerPhase + 1;
        queueNotEmpty <= False;
    endrule

    rule releaseLock (initDone && consumerPhase == 4);    
        consumerPhase <= consumerPhase + 1;
        cohMem.write(unpack(`HEAD_LOCK_ADDR), unpack(0));
        hasLock <= False;
    endrule

    rule reAcquireLock (initDone && !testDone && consumerPhase == 5);
        consumerPhase <= 0;
        cohMem.testAndSetReq(unpack(`HEAD_LOCK_ADDR), unpack(1));
        debugLog.record($format("reAcquireLock..."));
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
        noAction;
    endmethod
    
    method Action producerDone();
        noAction;
    endmethod

    method Bool initialized() = initDone;

    method Bool done() = testDone;
endmodule

