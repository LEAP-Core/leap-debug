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
`include "awb/provides/heat_transfer_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/VDEV_SYNCGROUP.bsh"
`include "asim/dict/PARAMS_HEAT_TRANSFER_COMMON.bsh"

interface HEAT_ENGINE_IFC#(type t_ADDR);
    method Action setIter(Bit#(16) num);
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
    method Action setFrameSize(t_ADDR x, t_ADDR y);
    method Action setAddrX(t_ADDR startX, t_ADDR endX);
    method Action setAddrY(t_ADDR startY, t_ADDR endY);
    method Bool initialized();
    method Bool done();
endinterface

//
// Heat engine implementation
//
module [CONNECTED_MODULE] mkHeatEngine#(MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) cohMem,
                                        DEBUG_FILE debugLog,
                                        Integer engineId,
                                        Bool isMaster)
    // interface:
    (HEAT_ENGINE_IFC#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(TLog#(N_X_MAX_POINTS), t_ADDR_MAX_X_SZ),
              NumAlias#(TLog#(N_Y_MAX_POINTS), t_ADDR_MAX_Y_SZ),
              Add#(TAdd#(TAdd#(t_ADDR_MAX_X_SZ, t_ADDR_MAX_Y_SZ), 2), extraBits, t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_MAX_X_SZ), t_ADDR_MAX_X),
              Alias#(Bit#(t_ADDR_MAX_Y_SZ), t_ADDR_MAX_Y));

    // =======================================================================
    //
    // Synchronization services
    //
    // =======================================================================
    
    SYNC_SERVICE_IFC sync <- mkSyncNode(`VDEV_SYNCGROUP_HEAT_TRANSFER, isMaster); 

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool) initDone                              <- mkReg(False);
    Reg#(Bool) masterInitDone                        <- mkReg(!isMaster);
    Reg#(Bit#(16)) numIter                           <- mkReg(0);
    Reg#(Bit#(16)) maxIter                           <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt                          <- mkReg(0);
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue        <- mkReg(0);
    Reg#(t_ADDR_MAX_X) startAddrX                    <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) startAddrY                    <- mkReg(0);
    Reg#(t_ADDR_MAX_X) endAddrX                      <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) endAddrY                      <- mkReg(0);
    Reg#(t_ADDR_MAX_X) testAddrX                     <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) testAddrY                     <- mkReg(0);
    
    Reg#(t_ADDR_MAX_X) frameSizeX                    <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) frameSizeY                    <- mkReg(0);
    Reg#(Bit#(TAdd#(t_ADDR_MAX_X_SZ, 1))) rowLength  <- mkReg(0);

    // addr function
    function t_ADDR calAddr(t_ADDR_MAX_X rx, t_ADDR_MAX_Y ry, Bit#(1) b);
        Bit#(TAdd#(TAdd#(t_ADDR_MAX_X_SZ, 1), t_ADDR_MAX_Y_SZ)) pixel_addr = (zeroExtend(ry) * zeroExtend(rowLength)) + zeroExtend(rx); 
        let addr = tuple2(pixel_addr, b);
        return unpack(zeroExtend(pack(addr)));
    endfunction

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && endAddrX != 0 && endAddrY != 0 && sync.initialized());
        initDone <= True;
        debugLog.record($format("doInit: initialization done, cycle=0x%11d", cycleCnt));
    endrule

    if (isMaster == True)
    begin
        LFSR#(Bit#(16)) lfsr            <- mkLFSR_16();
        Reg#(Bit#(2)) masterInitCnt     <- mkReg(0);
        Reg#(Bool) frameInitDone        <- mkReg(False);
        Reg#(Bit#(10)) masterIdleCnt    <- mkReg(0);
        Reg#(Bool) initIter0            <- mkReg(True);

        rule doMasterInit0 (!initDone && !masterInitDone && masterInitCnt == 0 && frameSizeX != 0 && frameSizeY != 0);
            lfsr.seed(1);
            masterInitCnt <= masterInitCnt + 1;
        endrule
          
        rule doMasterInit1 (!initDone && !masterInitDone && masterInitCnt == 1 && frameInitDone);
            masterInitCnt <= masterInitCnt + 1;
        endrule

        rule doMasterInit2 (!initDone && !masterInitDone && masterInitCnt == 2 && !cohMem.writePending());
             masterInitCnt <= masterInitCnt + 1;
             debugLog.record($format("frame initialization done, cycle=0x%11d", cycleCnt));
        endrule

        rule doMasterInit3 (!initDone && !masterInitDone && masterInitCnt == 3);
             masterIdleCnt <= masterIdleCnt + 1;
             if (masterIdleCnt == maxBound)
             begin
                 masterInitDone <= True;
                 sync.setSyncBarrier(barrierInitValue);
                 debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
             end
        endrule

        rule masterFrameInitIter0 (!initDone && !masterInitDone && masterInitCnt == 1 && !frameInitDone && initIter0);
            let addr = calAddr(testAddrX, testAddrY,0);
            t_DATA init_value = ?;
            if ((testAddrX == 0) || (testAddrX == frameSizeX) || (testAddrY == 0) || (testAddrY == frameSizeY)) //boundaries
            begin
                init_value = unpack(0);
            end
            else
            begin
                init_value = unpack(resize(lfsr.value()));
            end
            cohMem.write(addr, init_value);
            lfsr.next(); 
            initIter0 <= False;
            debugLog.record($format("masterFrameInitIter0: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                            testAddrX, testAddrY, addr, init_value));
        endrule

        rule masterFrameInitIter1 (!initDone && !masterInitDone && masterInitCnt == 1 && !frameInitDone && !initIter0);
            let addr = calAddr(testAddrX, testAddrY,1);
            cohMem.write(addr, unpack(0));
            if (testAddrX == frameSizeX) 
            begin
                testAddrX <= 0;
                testAddrY <= testAddrY + 1;
                if (testAddrY == frameSizeY)
                begin
                    frameInitDone <= True;
                end
            end
            else
            begin
                testAddrX <= testAddrX + 1;
            end
            initIter0 <= True;
            debugLog.record($format("masterFrameInitIter1: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                            testAddrX, testAddrY, addr, 0));
        endrule
    end

    // =======================================================================
    //
    // Tests: Heat transfer
    //
    // ====================================================================

    Reg#(Bool)                   startIter  <- mkReg(True);
    Reg#(Bit#(3))                testPhase  <- mkReg(0);
    Vector#(32, Reg#(t_DATA))    testValues <- replicateM(mkReg(unpack(0)));
    FIFOF#(Bit#(3))              testReqQ   <- mkSizedFIFOF(32);
    Reg#(Bool)                   iterDone   <- mkReg(False);
    Reg#(Bool)                  issueDone   <- mkReg(False);
    Reg#(Bool)                    allDone   <- mkReg(False);
    Reg#(Bool)                readFlipRow   <- mkReg(False);
    Reg#(Bool)               writeFlipRow   <- mkReg(False);
    Reg#(Tuple2#(Bool, Bit#(3))) headAddr   <- mkReg(unpack(0));
    Reg#(Tuple2#(Bool, Bit#(3))) tailAddr   <- mkReg(unpack(0));
    Reg#(t_ADDR_MAX_X)         writeAddrX   <- mkReg(0);
    Reg#(t_ADDR_MAX_Y)         writeAddrY   <- mkReg(0);
    PulseWire                    reqFullW   <- mkPulseWire();

    // increase set addr (head/tail)
    function Tuple2#(Bool, Bit#(3)) incrSetAddr(Tuple2#(Bool, Bit#(3)) addr);
        match {.looped, .val} = addr;
        if (val == 7)
        begin
            return tuple2(!looped, 0);
        end
        else
        begin
            return tuple2(looped, val+1);
        end
    endfunction

    function Bit#(5) testValueIdx (Bit#(3) setAddr, Bit#(3) idx);
        return (zeroExtend(setAddr)<<2) + zeroExtend(idx);
    endfunction

    (* fire_when_enabled *)
    rule checkReqFull (True);
        match {.head_looped, .head_val} = headAddr;
        match {.tail_looped, .tail_val} = tailAddr;
        if ((head_looped != tail_looped) && (head_val == tail_val)) // full
        begin
            reqFullW.send();
        end
    endrule

    rule initIter (initDone && startIter && (testPhase == 0));
        startIter <= False;
        // skip boundary pixels
        testAddrX  <= (startAddrX == 0)? 1 : startAddrX;
        testAddrY  <= (startAddrY == 0)? 1 : startAddrY;
        startAddrX <= (startAddrX == 0)? 1 : startAddrX;
        startAddrY <= (startAddrY == 0)? 1 : startAddrY;
        writeAddrX <= (startAddrX == 0)? 1 : startAddrX;
        writeAddrY <= (startAddrY == 0)? 1 : startAddrY;
        if (endAddrX == frameSizeX)
        begin
            endAddrX <= endAddrX - 1;
        end
        if (endAddrY == frameSizeY)
        begin
            endAddrY <= endAddrY - 1;
        end
        testPhase <= testPhase + 1;
        debugLog.record($format("initIter: iteration starts: numIter=%05d", numIter));
    endrule

    rule testPhase1 (initDone && !issueDone && (testPhase == 1));
        let addr = calAddr(testAddrX-1, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX-1, testAddrY, addr));
    endrule

    rule testPhase2 (initDone && !issueDone && (testPhase == 2));
        let addr = calAddr(testAddrX, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX, testAddrY, addr));
    endrule
    
    rule testPhase3 (initDone && !issueDone && (testPhase == 3) && !reqFullW);
        let addr = calAddr(testAddrX, testAddrY-1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX, testAddrY-1, addr));
    endrule
    
    rule testPhase4 (initDone && !issueDone && (testPhase == 4));
        let addr = calAddr(testAddrX, testAddrY+1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX, testAddrY+1, addr));
    endrule
    
    rule testPhase5 (initDone && !issueDone && (testPhase == 5));
        let new_x = (readFlipRow)? (testAddrX - 1) : (testAddrX + 1);
        let addr = calAddr(new_x, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", new_x, testAddrY, addr));
        if (((testAddrX == endAddrX) && !readFlipRow) || ((testAddrX == startAddrX) && readFlipRow)) //end of the row
        begin
            if (testAddrY == endAddrY) //end of interation 
            begin
                issueDone <= True;
            end
            else // next row
            begin
                readFlipRow <= !readFlipRow;
                testPhase   <= 7;
                testAddrY   <= testAddrY + 1;
                tailAddr    <= incrSetAddr(tailAddr); 
            end
        end
        else // next pixel
        begin
            testPhase <= 3;
            testAddrX <= (readFlipRow)? (testAddrX - 1) : (testAddrX + 1);
            tailAddr  <= incrSetAddr(tailAddr); 
        end
    endrule
    
    rule foldPointPhase (initDone && !issueDone && (testPhase == 7) && !reqFullW);
        let new_x = (readFlipRow)? (testAddrX + 1) : (testAddrX - 1);
        let addr = calAddr(new_x, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testPhase <= 4;
        testReqQ.enq(0);
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", new_x, testAddrY, addr));
    endrule

    rule testRecv (initDone && !startIter && !iterDone);
        let idx = testReqQ.first();
        testReqQ.deq();
        let data <- cohMem.readRsp();
        let h = tpl_2(headAddr);
        debugLog.record($format("recv: testValues[%02d] = value=0x%x", testValueIdx(h, idx), data));
        if (idx != 4) // not the last response
        begin
            testValues[testValueIdx(h, idx)] <= data;
        end
        else // get the last value
        begin
            // write value
            t_DATA new_value = unpack(pack(testValues[testValueIdx(h,0)]) + pack(testValues[testValueIdx(h,2)]) + 
                               pack(testValues[testValueIdx(h,3)]) + pack(data) - (3 * pack(testValues[testValueIdx(h,1)])));
            Bool read_bit = unpack(truncate(numIter));
            let addr = calAddr(writeAddrX, writeAddrY, pack(!(read_bit)));
            cohMem.write(addr, new_value);
            debugLog.record($format("write: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                            writeAddrX, writeAddrY, addr, new_value));
            let new_head_addr = incrSetAddr(headAddr);
            let new_h = tpl_2(new_head_addr);
            // move to next pixcel
            if (((writeAddrX == endAddrX) && !writeFlipRow) || ((writeAddrX == startAddrX) && writeFlipRow)) //end of the row
            begin
                if (writeAddrY == endAddrY) //end of interation 
                begin
                    iterDone <= True;
                    if (!isMaster || (numIter != maxIter))
                    begin
                        sync.signalSyncReached();
                    end
                end
                else // next row
                begin
                    writeFlipRow  <= !writeFlipRow;
                    writeAddrY    <= writeAddrY + 1;
                    headAddr      <= new_head_addr;
                    testValues[testValueIdx(new_h,1)] <= testValues[testValueIdx(h,3)];
                    testValues[testValueIdx(new_h,2)] <= testValues[testValueIdx(h,1)];
                end
            end
            else // next pixel
            begin
                writeAddrX  <= (writeFlipRow)? (writeAddrX - 1) : (writeAddrX + 1);
                headAddr    <= new_head_addr;
                testValues[testValueIdx(new_h,0)] <= testValues[testValueIdx(h,1)];
                testValues[testValueIdx(new_h,1)] <= data;
            end
        end
    endrule    
    
    rule waitForSync (initDone && !startIter && issueDone && iterDone && (!isMaster || (numIter != maxIter)));
        sync.waitForSync();
        numIter      <= numIter + 1;
        iterDone     <= False;
        testAddrX    <= startAddrX;
        testAddrY    <= startAddrY;
        writeAddrX   <= startAddrX;
        writeAddrY   <= startAddrY;
        testPhase    <= 1;
        readFlipRow  <= False;
        writeFlipRow <= False;
        issueDone    <= False;
        headAddr     <= unpack(0);
        tailAddr     <= unpack(0);
        debugLog.record($format("waitForSync: next iteration starts: numIter=%05d", numIter+1));
    endrule
    
    if (isMaster == True)
    begin
        rule waitForOthers (initDone && !startIter && issueDone && iterDone && !allDone && (numIter == maxIter) && sync.othersSyncAllReached());
            allDone <= True;
            debugLog.record($format("waitForOthers: all complete, numIter=%05d", numIter));
        endrule
    end
    
    // ====================================================================
    //
    // Heat engine debug scan for deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "Completed Iterations", numIter);
    dbg_list <- addDebugScanField(dbg_list, "testAddrX", testAddrX);
    dbg_list <- addDebugScanField(dbg_list, "testAddrY", testAddrY);
    dbg_list <- addDebugScanField(dbg_list, "writeAddrX", writeAddrX);
    dbg_list <- addDebugScanField(dbg_list, "writeAddrY", writeAddrY);
    dbg_list <- addDebugScanField(dbg_list, "writeAddr", calAddr(writeAddrX, writeAddrY, ~(truncate(numIter))));
    dbg_list <- addDebugScanField(dbg_list, "testPhase", testPhase);
    dbg_list <- addDebugScanField(dbg_list, "issueDone", issueDone);
    dbg_list <- addDebugScanField(dbg_list, "iterDone", iterDone);
    dbg_list <- addDebugScanField(dbg_list, "request full", reqFullW);
    dbg_list <- addDebugScanField(dbg_list, "testReqQ notEmpty", testReqQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "testReqQ notFull", testReqQ.notFull);
    
    let dbgNode <- mkDebugScanNode("Heat Engine "+ integerToString(engineId) + "(heat-engine.bsv)", dbg_list);

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action setIter(Bit#(16) num);
        maxIter <= num - 1;
        debugLog.record($format("setTestIter: numItern = %08d", num));
    endmethod
    
    method Action setFrameSize(t_ADDR x, t_ADDR y);
        frameSizeX <= truncateNP(pack(x)-1);
        frameSizeY <= truncateNP(pack(y)-1);
        rowLength  <= truncateNP(pack(x));
    endmethod
   
    method Action setAddrX(t_ADDR startX, t_ADDR endX);
        startAddrX <= truncateNP(pack(startX));
        endAddrX   <= truncateNP(pack(endX));
        debugLog.record($format("setAddrX: start address x = 0x%x, end address x = 0x%x", startX, endX));
    endmethod
    
    method Action setAddrY(t_ADDR startY, t_ADDR endY);
        startAddrY <= truncateNP(pack(startY));
        endAddrY   <= truncateNP(pack(endY));
        debugLog.record($format("setAddrY: start address y = 0x%x, end address y = 0x%x", startY, endY));
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
// Heat engine implementation using private scratchpad
//
module [CONNECTED_MODULE] mkHeatEnginePrivate#(MEMORY_IFC#(t_ADDR, t_DATA) cohMem,
                                               DEBUG_FILE debugLog)
    // interface:
    (HEAT_ENGINE_IFC#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(TLog#(N_X_MAX_POINTS), t_ADDR_MAX_X_SZ),
              NumAlias#(TLog#(N_Y_MAX_POINTS), t_ADDR_MAX_Y_SZ),
              Add#(TAdd#(TAdd#(t_ADDR_MAX_X_SZ, t_ADDR_MAX_Y_SZ), 2), extraBits, t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_MAX_X_SZ), t_ADDR_MAX_X),
              Alias#(Bit#(t_ADDR_MAX_Y_SZ), t_ADDR_MAX_Y));

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================
    
    Reg#(Bool) initDone                              <- mkReg(False);
    Reg#(Bool) masterInitDone                        <- mkReg(False);
    Reg#(Bit#(16)) numIter                           <- mkReg(0);
    Reg#(Bit#(16)) maxIter                           <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt                          <- mkReg(0);
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue        <- mkReg(0);
    Reg#(t_ADDR_MAX_X) startAddrX                    <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) startAddrY                    <- mkReg(0);
    Reg#(t_ADDR_MAX_X) endAddrX                      <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) endAddrY                      <- mkReg(0);
    Reg#(t_ADDR_MAX_X) testAddrX                     <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) testAddrY                     <- mkReg(0);
    
    Reg#(t_ADDR_MAX_X) frameSizeX                    <- mkReg(0);
    Reg#(t_ADDR_MAX_Y) frameSizeY                    <- mkReg(0);
    Reg#(Bit#(TAdd#(t_ADDR_MAX_X_SZ, 1))) rowLength  <- mkReg(0);

    // addr function
    function t_ADDR calAddr(t_ADDR_MAX_X rx, t_ADDR_MAX_Y ry, Bit#(1) b);
        Bit#(TAdd#(TAdd#(t_ADDR_MAX_X_SZ, 1), t_ADDR_MAX_Y_SZ)) pixel_addr = (zeroExtend(ry) * zeroExtend(rowLength)) + zeroExtend(rx); 
        let addr = tuple2(pixel_addr, b);
        return unpack(zeroExtend(pack(addr)));
    endfunction

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && maxIter != 0 && endAddrX != 0 && endAddrY != 0);
        initDone <= True;
        debugLog.record($format("doInit: initialization done, cycle=0x%11d", cycleCnt));
    endrule

    LFSR#(Bit#(16)) lfsr            <- mkLFSR_16();
    Reg#(Bit#(2)) masterInitCnt     <- mkReg(0);
    Reg#(Bool) frameInitDone        <- mkReg(False);
    Reg#(Bit#(10)) masterIdleCnt    <- mkReg(0);
    Reg#(Bool) initIter0            <- mkReg(True);

    rule doMasterInit0 (!masterInitDone && masterInitCnt == 0 && frameSizeX != 0 && frameSizeY != 0);
        lfsr.seed(1);
        masterInitCnt <= masterInitCnt + 1;
    endrule
      
    rule doMasterInit1 (!masterInitDone && masterInitCnt == 1 && frameInitDone);
        masterInitCnt <= masterInitCnt + 1;
    endrule

    rule doMasterInit2 (!masterInitDone && masterInitCnt == 2);
         masterInitCnt <= masterInitCnt + 1;
         debugLog.record($format("frame initialization done, cycle=0x%11d", cycleCnt));
    endrule

    rule doMasterInit3 (!masterInitDone && masterInitCnt == 3);
         masterIdleCnt <= masterIdleCnt + 1;
         if (masterIdleCnt == maxBound)
         begin
             masterInitDone <= True;
             debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
         end
    endrule

    rule masterFrameInitIter0 (!masterInitDone && masterInitCnt == 1 && !frameInitDone && initIter0);
        let addr = calAddr(testAddrX, testAddrY,0);
        t_DATA init_value = ?;
        if ((testAddrX == 0) || (testAddrX == frameSizeX) || (testAddrY == 0) || (testAddrY == frameSizeY)) //boundaries
        begin
            init_value = unpack(0);
        end
        else
        begin
            init_value = unpack(resize(lfsr.value()));
        end
        cohMem.write(addr, init_value);
        lfsr.next(); 
        initIter0 <= False;
        debugLog.record($format("masterFrameInitIter0: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                        testAddrX, testAddrY, addr, init_value));
    endrule

    rule masterFrameInitIter1 (!masterInitDone && masterInitCnt == 1 && !frameInitDone && !initIter0);
        let addr = calAddr(testAddrX, testAddrY,1);
        cohMem.write(addr, unpack(0));
        if (testAddrX == frameSizeX) 
        begin
            testAddrX <= 0;
            testAddrY <= testAddrY + 1;
            if (testAddrY == frameSizeY)
            begin
                frameInitDone <= True;
            end
        end
        else
        begin
            testAddrX <= testAddrX + 1;
            testAddrY <= testAddrY;
        end
        initIter0 <= True;
        debugLog.record($format("masterFrameInitIter1: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                        testAddrX, testAddrY, addr, 0));
    endrule

    // =======================================================================
    //
    // Tests: Heat transfer
    //
    // ====================================================================

    Reg#(Bool)                   startIter  <- mkReg(True);
    Reg#(Bit#(3))                testPhase  <- mkReg(0);
    Vector#(32, Reg#(t_DATA))    testValues <- replicateM(mkReg(unpack(0)));
    FIFOF#(Bit#(3))              testReqQ   <- mkSizedFIFOF(32);
    Reg#(Bool)                   iterDone   <- mkReg(False);
    Reg#(Bool)                  issueDone   <- mkReg(False);
    Reg#(Bool)                    allDone   <- mkReg(False);
    Reg#(Bool)                readFlipRow   <- mkReg(False);
    Reg#(Bool)               writeFlipRow   <- mkReg(False);
    Reg#(Tuple2#(Bool, Bit#(3))) headAddr   <- mkReg(unpack(0));
    Reg#(Tuple2#(Bool, Bit#(3))) tailAddr   <- mkReg(unpack(0));
    Reg#(t_ADDR_MAX_X)           writeAddrX <- mkReg(0);
    Reg#(t_ADDR_MAX_Y)           writeAddrY <- mkReg(0);
    PulseWire                    reqFullW   <- mkPulseWire();

    // increase set addr (head/tail)
    function Tuple2#(Bool, Bit#(3)) incrSetAddr(Tuple2#(Bool, Bit#(3)) addr);
        match {.looped, .val} = addr;
        if (val == 7)
        begin
            return tuple2(!looped, 0);
        end
        else
        begin
            return tuple2(looped, val+1);
        end
    endfunction

    function Bit#(5) testValueIdx (Bit#(3) setAddr, Bit#(3) idx);
        return (zeroExtend(setAddr)<<2) + zeroExtend(idx);
    endfunction

    (* fire_when_enabled *)
    rule checkReqFull (True);
        match {.head_looped, .head_val} = headAddr;
        match {.tail_looped, .tail_val} = tailAddr;
        if ((head_looped != tail_looped) && (head_val == tail_val)) // full
        begin
            reqFullW.send();
        end
    endrule

    rule initIter (initDone && startIter && (testPhase == 0));
        startIter  <= False;
        // skip boundary pixels
        testAddrX  <= (startAddrX == 0)? 1 : startAddrX;
        testAddrY  <= (startAddrY == 0)? 1 : startAddrY;
        startAddrX <= (startAddrX == 0)? 1 : startAddrX;
        startAddrY <= (startAddrY == 0)? 1 : startAddrY;
        writeAddrX <= (startAddrX == 0)? 1 : startAddrX;
        writeAddrY <= (startAddrY == 0)? 1 : startAddrY;
        if (endAddrX == frameSizeX)
        begin
            endAddrX <= endAddrX - 1;
        end
        if (endAddrY == frameSizeY)
        begin
            endAddrY <= endAddrY - 1;
        end
        testPhase <= testPhase + 1;
        debugLog.record($format("initIter: iteration starts: numIter=%05d", numIter));
    endrule

    rule testPhase1 (initDone && !issueDone && (testPhase == 1));
        let addr = calAddr(testAddrX-1, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX-1, testAddrY, addr));
    endrule

    rule testPhase2 (initDone && !issueDone && (testPhase == 2));
        let addr = calAddr(testAddrX, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX, testAddrY, addr));
    endrule
    
    rule testPhase3 (initDone && !issueDone && (testPhase == 3) && !reqFullW);
        let addr = calAddr(testAddrX, testAddrY-1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX, testAddrY-1, addr));
    endrule
    
    rule testPhase4 (initDone && !issueDone && (testPhase == 4));
        let addr = calAddr(testAddrX, testAddrY+1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        testPhase <= testPhase + 1;
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", testAddrX, testAddrY+1, addr));
    endrule
    
    rule testPhase5 (initDone && !issueDone && (testPhase == 5));
        let new_x = (readFlipRow)? (testAddrX - 1) : (testAddrX + 1);
        let addr = calAddr(new_x, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase-1);
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", new_x, testAddrY, addr));
        if (((testAddrX == endAddrX) && !readFlipRow) || ((testAddrX == startAddrX) && readFlipRow)) //end of the row
        begin
            if (testAddrY == endAddrY) //end of interation 
            begin
                issueDone <= True;
            end
            else // next row
            begin
                readFlipRow <= !readFlipRow;
                testPhase   <= 7;
                testAddrY   <= testAddrY + 1;
                tailAddr    <= incrSetAddr(tailAddr); 
            end
        end
        else // next pixel
        begin
            testPhase <= 3;
            testAddrX <= (readFlipRow)? (testAddrX - 1) : (testAddrX + 1);
            tailAddr  <= incrSetAddr(tailAddr); 
        end
    endrule

    rule foldPointPhase (initDone && !issueDone && (testPhase == 7) && !reqFullW);
        let new_x = (readFlipRow)? (testAddrX + 1) : (testAddrX - 1);
        let addr = calAddr(new_x, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testPhase <= 4;
        testReqQ.enq(0);
        debugLog.record($format("read: addr_x=0x%x, addr_y=0x%x, addr=0x%x", new_x, testAddrY, addr));
    endrule

    rule testRecv (initDone && !startIter && !iterDone);
        let idx = testReqQ.first();
        testReqQ.deq();
        let data <- cohMem.readRsp();
        let h = tpl_2(headAddr);
        debugLog.record($format("recv: testValues[%02d] = value=0x%x", testValueIdx(h, idx), data));
        if (idx != 4) // not the last response
        begin
            testValues[testValueIdx(h, idx)] <= data;
        end
        else // get the last value
        begin
            // write value
            t_DATA new_value = unpack(pack(testValues[testValueIdx(h,0)]) + pack(testValues[testValueIdx(h,2)]) + 
                               pack(testValues[testValueIdx(h,3)]) + pack(data) - (3 * pack(testValues[testValueIdx(h,1)])));
            Bool read_bit = unpack(truncate(numIter));
            let addr = calAddr(writeAddrX, writeAddrY, pack(!(read_bit)));
            cohMem.write(addr, new_value);
            debugLog.record($format("write: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                            writeAddrX, writeAddrY, addr, new_value));
            let new_head_addr = incrSetAddr(headAddr);
            let new_h = tpl_2(new_head_addr);
            // move to next pixcel
            if (((writeAddrX == endAddrX) && !writeFlipRow) || ((writeAddrX == startAddrX) && writeFlipRow)) //end of the row
            begin
                if (writeAddrY == endAddrY) //end of interation 
                begin
                    iterDone <= True;
                end
                else // next row
                begin
                    writeFlipRow  <= !writeFlipRow;
                    writeAddrY    <= writeAddrY + 1;
                    headAddr      <= new_head_addr;
                    testValues[testValueIdx(new_h,1)] <= testValues[testValueIdx(h,3)];
                    testValues[testValueIdx(new_h,2)] <= testValues[testValueIdx(h,1)];
                end
            end
            else // next pixel
            begin
                writeAddrX  <= (writeFlipRow)? (writeAddrX - 1) : (writeAddrX + 1);
                headAddr    <= new_head_addr;
                testValues[testValueIdx(new_h,0)] <= testValues[testValueIdx(h,1)];
                testValues[testValueIdx(new_h,1)] <= data;
            end
        end
    endrule    
    
    rule waitForSync (initDone && !startIter && issueDone && iterDone);
        numIter  <= numIter + 1;
        iterDone <= False;
        if (numIter == maxIter) 
        begin
            allDone <= True;
            debugLog.record($format("waitForSync: all complete,  numIter=%05d", numIter));
        end
        else
        begin
            testAddrX    <= startAddrX;
            testAddrY    <= startAddrY;
            writeAddrX   <= startAddrX;
            writeAddrY   <= startAddrY;
            testPhase    <= 1;
            readFlipRow  <= False;
            writeFlipRow <= False;
            issueDone    <= False;
            headAddr     <= unpack(0);
            tailAddr     <= unpack(0);
            debugLog.record($format("waitForSync: next iteration starts: numIter=%05d", numIter+1));
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
    
    method Action setFrameSize(t_ADDR x, t_ADDR y);
        frameSizeX <= truncateNP(pack(x)-1);
        frameSizeY <= truncateNP(pack(y)-1);
        rowLength  <= truncateNP(pack(x));
        debugLog.record($format("setFrameSize: frame size x = 0x%x, frame size y = 0x%x", x, y));
    endmethod
   
    method Action setAddrX(t_ADDR startX, t_ADDR endX);
        startAddrX <= truncateNP(pack(startX));
        endAddrX   <= truncateNP(pack(endX));
        debugLog.record($format("setAddrX: start address x = 0x%x, end address x = 0x%x", startX, endX));
    endmethod
    
    method Action setAddrY(t_ADDR startY, t_ADDR endY);
        startAddrY <= truncateNP(pack(startY));
        endAddrY   <= truncateNP(pack(endY));
        debugLog.record($format("setAddrY: start address y = 0x%x, end address y = 0x%x", startY, endY));
    endmethod
    
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
        noAction;
    endmethod

    method Bool initialized() = initDone;
    method Bool done() = allDone;
endmodule
