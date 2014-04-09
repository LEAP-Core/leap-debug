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

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "asim/provides/lock_sync_service.bsh"

`include "asim/dict/VDEV_SYNCGROUP.bsh"

`define BARRIER_ENTER_CNT_ADDR 1
`define BARRIER_LEAVE_CNT_ADDR 2
`define BARRIER_ENTER_FLAG_ADDR 3
`define BARRIER_LEAVE_FLAG_ADDR 4
`define BARRIER_LOCK_ADDR 5

interface SYNC_TEST_ENGINE_IFC;
    method Action setIter(Bit#(16) num);
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
    method Bool initialized();
    method Bool done();
endinterface

//
// Heat engine implementation (using synchronization primitive)
//
module [CONNECTED_MODULE] mkSyncTestEngine#(DEBUG_FILE debugLog,
                                            Bool isMaster)
    // interface:
    (SYNC_TEST_ENGINE_IFC)
    provisos ();

    // =======================================================================
    //
    // Synchronization services
    //
    // =======================================================================
    
    SYNC_SERVICE_IFC sync <- mkSyncNode(`VDEV_SYNCGROUP_TEST, isMaster); 

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================
    
    Reg#(Bool) initDone                        <- mkReg(False);
    Reg#(Bool) masterInitDone                  <- mkReg(!isMaster);
    Reg#(Bit#(16)) numIter                     <- mkReg(0);
    Reg#(Bit#(16)) maxIter                     <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt                    <- mkReg(0);
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue  <- mkReg(0);

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && sync.initialized());
        initDone <= True;
        debugLog.record($format("doInit: initialization done, cycle=0x%11d", cycleCnt));
    endrule

    if (isMaster == True)
    begin
        rule doMasterInit (!initDone && !masterInitDone && barrierInitValue != 0);
            masterInitDone <= True;
            sync.setSyncBarrier(barrierInitValue);
            debugLog.record($format("master initialization done, cycle=0x%11d, barrier=0x%x", cycleCnt, barrierInitValue));
        endrule
    end

    // =======================================================================
    //
    // Tests: Synchronization test
    //
    // ====================================================================

    Reg#(Bool)  iterDone   <- mkReg(False);
    Reg#(Bool)  allDone    <- mkReg(False);

    rule sendSyncSignal (initDone && !iterDone && (!isMaster || (numIter != maxIter)));
        sync.signalSyncReached();
        iterDone <= True;
        debugLog.record($format("sendSyncSignal: numIter=%05d, cycle=0x%11d", numIter, cycleCnt));
    endrule    
    
    rule waitForSync (initDone && iterDone && (!isMaster || (numIter != maxIter)));
        sync.waitForSync();
        numIter  <= numIter + 1;
        iterDone  <= False;
        debugLog.record($format("waitForSync: next iteration starts: numIter=%05d", numIter+1));
    endrule
    
    if (isMaster == True)
    begin
        rule waitForOthers (initDone && !allDone && (numIter == maxIter) && sync.othersSyncAllReached());
            allDone <= True;
            debugLog.record($format("waitForOthers: all complete, numIter=%05d, cycle=0x%11d", numIter, cycleCnt));
        endrule
    end

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action setIter(Bit#(16) num);
        maxIter <= num - 1;
        debugLog.record($format("setTestIter: numIter = %08d", num));
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

//
// Heat engine implementation (using coherent memory)
//
module [CONNECTED_MODULE] mkMemSyncTestEngine#(MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) cohMem,
                                               DEBUG_FILE debugLog,
                                               Bool isMaster)
    // interface:
    (SYNC_TEST_ENGINE_IFC)
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================
    
    Reg#(Bool) initDone          <- mkReg(False);
    Reg#(Bool) masterInitDone    <- mkReg(!isMaster);
    Reg#(Bit#(16)) numIter       <- mkReg(0);
    Reg#(Bit#(16)) maxIter       <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt      <- mkReg(0);

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && maxIter != 0);
        initDone <= True;
        debugLog.record($format("doInit: initialization done, cycle=0x%11d", cycleCnt));
    endrule

    if (isMaster == True)
    begin
        Reg#(Bit#(3)) masterInitCnt <- mkReg(0);
        
        rule doMasterInit0 (!initDone && !masterInitDone && masterInitCnt == 0);
            cohMem.write(unpack(`BARRIER_ENTER_CNT_ADDR), unpack(0));
            debugLog.record($format("doMasterInit0: write addr=0x%x, val=0x%x", `BARRIER_ENTER_CNT_ADDR, 0));
            masterInitCnt <= masterInitCnt + 1;
        endrule
          
        rule doMasterInit1 (!initDone && !masterInitDone && masterInitCnt == 1);
            cohMem.write(unpack(`BARRIER_LEAVE_CNT_ADDR), unpack(0));
            debugLog.record($format("doMasterInit1: write addr=0x%x, val=0x%x", `BARRIER_LEAVE_CNT_ADDR, 0));
            masterInitCnt <= masterInitCnt + 1;
        endrule
        
        rule doMasterInit2 (!initDone && !masterInitDone && masterInitCnt == 2);
            cohMem.write(unpack(`BARRIER_LEAVE_FLAG_ADDR), unpack(0));
            debugLog.record($format("doMasterInit2: write addr=0x%x, val=0x%x", `BARRIER_LEAVE_FLAG_ADDR, 0));
            masterInitCnt <= masterInitCnt + 1;
        endrule
        
        rule doMasterInit3 (!initDone && !masterInitDone && masterInitCnt == 3);
            cohMem.write(unpack(`BARRIER_LOCK_ADDR), unpack(0));
            debugLog.record($format("doMasterInit3: write addr=0x%x, val=0x%x", `BARRIER_LOCK_ADDR, 0));
            masterInitCnt <= masterInitCnt + 1;
        endrule
          
        rule doMasterInit4 (!initDone && !masterInitDone && masterInitCnt == 4);
            cohMem.write(unpack(`BARRIER_ENTER_FLAG_ADDR), unpack(1));
            debugLog.record($format("doMasterInit4: write addr=0x%x, val=0x%x", `BARRIER_ENTER_FLAG_ADDR, 1));
            masterInitCnt <= masterInitCnt + 1;
        endrule

        rule doMasterInit5 (!initDone && !masterInitDone && masterInitCnt == 5 && !cohMem.writePending());
            masterInitDone <= True;
            debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
        endrule
    end

    // =======================================================================
    //
    // Tests: Synchronization test
    //
    // ====================================================================

    Reg#(Bool)   iterDone   <- mkReg(False);
    Reg#(Bool)   allDone    <- mkReg(False);
    Reg#(Bit#(4)) testState <- mkReg(0);

    rule checkBarrierReach (initDone && testState == 0);
        cohMem.readReq(unpack(`BARRIER_ENTER_FLAG_ADDR));
        testState <= testState + 1;
        debugLog.record($format("checkBarrierReach: read addr = 0x%x", `BARRIER_ENTER_FLAG_ADDR));
    endrule

    rule recvBarrierReachSignal (initDone && testState == 1);
        let resp <- cohMem.readRsp();
        if (pack(resp) == 0) // cannot enter barrier
        begin
            testState <= 0; // recheck barrier reach signal
            debugLog.record($format("recvBarrierReachSignal: need to recheck"));
        end
        else
        begin
            cohMem.testAndSetReq(unpack(`BARRIER_LOCK_ADDR), unpack(1));
            testState <= 2;
            debugLog.record($format("recvBarrierReachSignal: require barrier lock..."));
        end
    endrule

    rule getBarrierLock (initDone && testState == 2);
        let resp <- cohMem.testAndSetRsp();
        debugLog.record($format("getBarrierLock: testAndSetRsp=0x%x", resp));
        if (pack(resp) == 0) // get lock!
        begin
            cohMem.readReq(unpack(`BARRIER_ENTER_CNT_ADDR));
            debugLog.record($format("getBarrierLock: get lock, read BARRIER_ENTER_CNT_ADDR..."));
            testState <= 3;
        end
        else
        begin
            cohMem.testAndSetReq(unpack(`BARRIER_LOCK_ADDR), unpack(1));
            debugLog.record($format("getBarrierLock: does not get lock, retry..."));
        end
    endrule

    rule incrBarrierEnterCnt (initDone && testState == 3);
        let resp <- cohMem.readRsp();
        t_DATA new_val = unpack(pack(resp) + 1);
        debugLog.record($format("incrBarrierEnterCnt: barrier enter count=0x%x", resp));
        cohMem.write(unpack(`BARRIER_ENTER_CNT_ADDR), new_val);
        testState <= (pack(new_val) == fromInteger(valueOf(N_TOTAL_ENGINES)))? 4 : 6;
    endrule

    rule finishBarrierEnter (initDone && testState == 4);
        cohMem.write(unpack(`BARRIER_ENTER_FLAG_ADDR), unpack(0));
        debugLog.record($format("finishBarrierEnter: write addr = 0x%x, val=0x%x", `BARRIER_ENTER_FLAG_ADDR, 0));
        testState <= 5;
    endrule

    rule startBarrierLeave (initDone && testState == 5);
        cohMem.write(unpack(`BARRIER_LEAVE_FLAG_ADDR), unpack(1));
        debugLog.record($format("startBarrierLeave: write addr = 0x%x, val=0x%x", `BARRIER_LEAVE_FLAG_ADDR, 1));
        testState <= 6;
    endrule

    rule releaseBarrierLock (initDone && testState == 6);
        cohMem.write(unpack(`BARRIER_LOCK_ADDR), unpack(0));
        debugLog.record($format("releaseBarrierLock: release lock"));
        testState <= 7;
    endrule

    rule checkBarrierLeave (initDone && testState == 7);
        cohMem.readReq(unpack(`BARRIER_LEAVE_FLAG_ADDR));
        debugLog.record($format("checkBarrierLeave: read addr = 0x%x", `BARRIER_LEAVE_FLAG_ADDR));
        testState <= 8;
    endrule

    rule recvBarrierLeaveSignal (initDone && testState == 8);
        let resp <- cohMem.readRsp();
        if (pack(resp) == 0) // cannot leave barrier
        begin
            testState <= 7; // recheck barrier reach signal
            debugLog.record($format("recvBarrierLeaveSignal: need to recheck"));
        end
        else
        begin
            cohMem.testAndSetReq(unpack(`BARRIER_LOCK_ADDR), unpack(1));
            testState <= 9;
            debugLog.record($format("recvBarrierLeaveSignal: require barrier lock..."));
        end
    endrule
    
    rule getBarrierLeaveLock (initDone && testState == 9);
        let resp <- cohMem.testAndSetRsp();
        debugLog.record($format("getBarrierLeaveLock: testAndSetRsp=0x%x", resp));
        if (pack(resp) == 0) // get lock!
        begin
            cohMem.readReq(unpack(`BARRIER_LEAVE_CNT_ADDR));
            debugLog.record($format("getBarrierLeaveLock: get lock, read BARRIER_LEAVE_CNT_ADDR..."));
            testState <= 10;
        end
        else
        begin
            cohMem.testAndSetReq(unpack(`BARRIER_LOCK_ADDR), unpack(1));
            debugLog.record($format("getBarrierLeaveLock: does not get lock, retry..."));
        end
    endrule

    rule incrBarrierLeaveCnt (initDone && testState == 10);
        let resp <- cohMem.readRsp();
        t_DATA new_val = unpack(pack(resp) + 1);
        debugLog.record($format("incrBarrierLeaveCnt: barrier enter count=0x%x", resp));
        cohMem.write(unpack(`BARRIER_LEAVE_CNT_ADDR), new_val);
        testState <= (pack(new_val) == fromInteger(valueOf(N_TOTAL_ENGINES)))? 11 : 15;
    endrule

    rule finishBarrierLeave (initDone && testState == 11);
        cohMem.write(unpack(`BARRIER_LEAVE_FLAG_ADDR), unpack(0));
        debugLog.record($format("finishBarrierLeave: write addr = 0x%x, val=0x%x", `BARRIER_LEAVE_FLAG_ADDR, 0));
        testState <= 12;
    endrule

    rule resetEnterCnt (initDone && testState == 12);
        cohMem.write(unpack(`BARRIER_ENTER_CNT_ADDR), unpack(0));
        debugLog.record($format("resetEnterCnt: write addr = 0x%x, val=0x%x", `BARRIER_ENTER_CNT_ADDR, 0));
        testState <= 13;
    endrule
    
    rule resetLeaveCnt (initDone && testState == 13);
        cohMem.write(unpack(`BARRIER_LEAVE_CNT_ADDR), unpack(0));
        debugLog.record($format("resetLeaveCnt: write addr = 0x%x, val=0x%x", `BARRIER_LEAVE_CNT_ADDR, 0));
        testState <= 14;
    endrule

    rule startBarrierEnter (initDone && testState == 14);
        cohMem.write(unpack(`BARRIER_ENTER_FLAG_ADDR), unpack(1));
        debugLog.record($format("startBarrierEnter: write addr = 0x%x, val=0x%x", `BARRIER_ENTER_FLAG_ADDR, 1));
        testState <= 15;
    endrule

    rule releaseBarrierLeaveLock (initDone && !allDone && testState == 15);
        cohMem.write(unpack(`BARRIER_LOCK_ADDR), unpack(0));
        debugLog.record($format("releaseBarrierLeaveLock: release lock, iteration ends: numIter=%05d", numIter));
        if (numIter != maxIter)
        begin
            numIter   <= numIter + 1;
            testState <= 0;
        end
        else
        begin
            allDone <= True;
        end
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action setIter(Bit#(16) num);
        maxIter <= num - 1;
        debugLog.record($format("setTestIter: numIter = %08d", num));
    endmethod
    
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
        noAction;
    endmethod

    method Bool initialized() = initDone;
    method Bool done() = allDone;

endmodule
