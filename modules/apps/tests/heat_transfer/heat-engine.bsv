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
`include "asim/dict/VDEV_SYNCGROUP.bsh"
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"

interface HEAT_ENGINE_IFC#(type t_ADDR);
    method Action setIter(Bit#(16) num);
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
    method Action setAddrX(t_ADDR x);
    method Action setAddrY(t_ADDR y);
    method Bool initialized();
    method Bool done();
    method Bool iterationDone();
endinterface

//
// Heat engine implementation
//
module [CONNECTED_MODULE] mkHeatEngine#(Integer engineID, 
                                        MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) cohMem,
                                        DEBUG_FILE debugLog,
                                        Bool isMaster)
    // interface:
    (HEAT_ENGINE_IFC#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(TLog#(N_X_POINTS), t_ADDR_X_SZ),
              NumAlias#(TLog#(N_Y_POINTS), t_ADDR_Y_SZ),
              Add#(TAdd#(TAdd#(t_ADDR_Y_SZ, t_ADDR_Y_SZ),1), extraBits, t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_X_SZ), t_ADDR_X),
              Alias#(Bit#(t_ADDR_Y_SZ), t_ADDR_Y));

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
    
    // addr function
    function t_ADDR calAddr(t_ADDR_X rx, t_ADDR_Y ry, Bit#(1) b);
        Tuple3#(t_ADDR_Y, t_ADDR_X, Bit#(1)) addr = tuple3(ry, rx, b);
        return unpack(zeroExtend(pack(addr)));
    endfunction

    // Random number generator
    Reg#(Bool) initDone                        <- mkReg(False);
    Reg#(Bool) masterInitDone                  <- mkReg(!isMaster);
    Reg#(Bit#(16)) numIter                     <- mkReg(0);
    Reg#(Bit#(16)) maxIter                     <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt                    <- mkReg(0);
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue  <- mkReg(0);
    Reg#(t_ADDR_X) startAddrX                  <- mkReg(0);
    Reg#(t_ADDR_Y) startAddrY                  <- mkReg(0);
    Reg#(t_ADDR_X) endAddrX                    <- mkReg(0);
    Reg#(t_ADDR_Y) endAddrY                    <- mkReg(0);
    Reg#(t_ADDR_X) testAddrX                   <- mkReg(0);
    Reg#(t_ADDR_Y) testAddrY                   <- mkReg(0);
    PulseWire      iterDoneW                   <- mkPulseWire();

    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule doInit (!initDone && masterInitDone && maxIter != 0 && endAddrX != 0 && endAddrY != 0 && sync.initialized());
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

        rule doMasterInit0 (!masterInitDone && masterInitCnt == 0);
            lfsr.seed(1);
            masterInitCnt <= masterInitCnt + 1;
        endrule
          
        rule doMasterInit1 (!masterInitDone && masterInitCnt == 1 && frameInitDone);
            masterInitCnt <= masterInitCnt + 1;
        endrule

        rule doMasterInit2 (!masterInitDone && masterInitCnt == 2 && !cohMem.writePending());
             masterInitCnt <= masterInitCnt + 1;
             debugLog.record($format("frame initialization done, cycle=0x%11d", cycleCnt));
        endrule

        rule doMasterInit3 (!masterInitDone && masterInitCnt == 3);
             masterIdleCnt <= masterIdleCnt + 1;
             if (masterIdleCnt == maxBound)
             begin
                 masterInitDone <= True;
                 sync.setSyncBarrier(barrierInitValue);
                 debugLog.record($format("master initialization done, cycle=0x%11d", cycleCnt));
             end
        endrule

        rule masterFrameInitIter0 (!masterInitDone && masterInitCnt == 1 && !frameInitDone && initIter0);
            let addr = calAddr(testAddrX, testAddrY,0);
            t_DATA init_value = ?;
            if ((testAddrX == 0) || (testAddrX == fromInteger(valueOf(N_X_POINTS)-1)) || (testAddrY == 0) || (testAddrY == fromInteger(valueOf(N_Y_POINTS)-1))) //boundaries
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
            if (testAddrX == fromInteger(valueOf(N_X_POINTS)-1)) 
            begin
                testAddrX <= 0;
                testAddrY <= testAddrY + 1;
                if (testAddrY == fromInteger(valueOf(N_Y_POINTS)-1))
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
    end

    // =======================================================================
    //
    // Tests: Heat transfer
    //
    // ====================================================================

    Reg#(Bool)                startIter  <- mkReg(True);
    Reg#(Bit#(3))             testPhase  <- mkReg(0);
    Vector#(5, Reg#(t_DATA))  testValues <- replicateM(mkReg(unpack(0)));
    FIFOF#(Bit#(3))           testReqQ   <- mkSizedFIFOF(32);
    Reg#(Bool)                iterDone   <- mkReg(False);
    Reg#(Bool)                 allDone   <- mkReg(False);

    rule initIter (initDone && startIter && (testPhase == 0));
        startIter <= False;
        testAddrX <= (startAddrX == 0)? 1 : startAddrX;
        testAddrY <= (startAddrY == 0)? 1 : startAddrY;
        if (endAddrX == fromInteger(valueOf(N_X_POINTS)-1))
        begin
            endAddrX <= endAddrX - 1;
        end
        if (testAddrY == fromInteger(valueOf(N_Y_POINTS)-1))
        begin
            endAddrY <= endAddrY - 1;
        end
        testPhase <= testPhase + 1;
        debugLog.record($format("initIter: iteration starts: numIter=%05d", numIter));
    endrule

    rule testPhase1 (initDone && (testPhase == 1));
        let addr = calAddr(testAddrX-1, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule

    rule testPhase2 (initDone && (testPhase == 2));
        let addr = calAddr(testAddrX, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule
    
    rule testPhase3 (initDone && (testPhase == 3));
        let addr = calAddr(testAddrX, testAddrY-1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule
    
    rule testPhase4 (initDone && (testPhase == 4));
        let addr = calAddr(testAddrX, testAddrY+1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule
    
    rule testPhase5 (initDone && (testPhase == 5));
        let addr = calAddr(testAddrX+1, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testPhase <= testPhase + 1;
        testReqQ.enq(testPhase);
    endrule
    
    rule testRecv (initDone && testReqQ.notEmpty() && !iterDone);
        let idx = testReqQ.first();
        testReqQ.deq();
        let data <- cohMem.readRsp();
        if (idx != 5) // not the last response
        begin
            testValues[pack(idx)-1] <= data;
        end
        else // get the last value
        begin
            // write value
            t_DATA new_value = unpack(pack(testValues[0]) + pack(testValues[2]) + pack(testValues[3]) + pack(data) - (3 * pack(testValues[1])));
            Bool read_bit = unpack(truncate(numIter));
            let addr = calAddr(testAddrX, testAddrY, pack(!(read_bit)));
            cohMem.write(addr, new_value);
            debugLog.record($format("write: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                            testAddrX, testAddrY, addr, new_value));
            // move to next pixcel
            if (testAddrX == endAddrX)
            begin
                if (testAddrY == endAddrY) //end of interation 
                begin
                    iterDone <= True;
                    sync.signalSyncReached();
                end
                else // next row
                begin
                    testPhase <= 1;
                    testAddrX <= (startAddrX == 0)? 1 : startAddrX;
                    testAddrY <= testAddrY + 1;
                end
            end
            else // next pixel
            begin
                testPhase <= 3;
                testAddrX <= testAddrX + 1;
                testValues[0] <= testValues[1];
                testValues[1] <= data;
            end
        end
    endrule    
    
    rule waitForSync (initDone && (testPhase == 6) && iterDone);
        sync.waitForSync();
        numIter  <= numIter + 1;
        iterDone <= False;
        if (numIter == maxIter) 
        begin
            allDone <= True;
            debugLog.record($format("waitForSync: all complete,  numIter=%05d", numIter));
        end
        else
        begin
            testAddrX <= (startAddrX == 0)? 1 : startAddrX;
            testAddrY <= (startAddrY == 0)? 1 : startAddrY;
            testPhase <= 1;
            iterDoneW.send();
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
        debugLog.record($format("setTestIter: numItern = %08d", num));
    endmethod
    
    method Action setAddrX(t_ADDR x);
        startAddrX <= truncateNP(pack(x));
        endAddrX <= truncateNP(pack(x)) + fromInteger(valueOf(N_COLS_PER_ENGINE)-1);
        debugLog.record($format("setAddrX: start address x = 0x%x", x));
    endmethod
    
    method Action setAddrY(t_ADDR y);
        startAddrY <= truncateNP(pack(y));
        endAddrY <= truncateNP(pack(y)) + fromInteger(valueOf(N_ROWS_PER_ENGINE)-1);
        debugLog.record($format("setAddrY: start address y = 0x%x", y));
    endmethod

    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
        if (isMaster)
        begin
            barrierInitValue <= barrier;
        end
    endmethod

    method Bool initialized() = initDone;
    method Bool done() = allDone;
    method Bool iterationDone() = iterDoneW;
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
              NumAlias#(TLog#(N_X_POINTS), t_ADDR_X_SZ),
              NumAlias#(TLog#(N_Y_POINTS), t_ADDR_Y_SZ),
              Add#(TAdd#(TAdd#(t_ADDR_Y_SZ, t_ADDR_Y_SZ),1), extraBits, t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_X_SZ), t_ADDR_X),
              Alias#(Bit#(t_ADDR_Y_SZ), t_ADDR_Y));

    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================
    
    // addr function
    function t_ADDR calAddr(t_ADDR_X rx, t_ADDR_Y ry, Bit#(1) b);
        Tuple3#(t_ADDR_Y, t_ADDR_X, Bit#(1)) addr = tuple3(ry, rx, b);
        return unpack(zeroExtend(pack(addr)));
    endfunction

    // Random number generator
    Reg#(Bool) initDone                        <- mkReg(False);
    Reg#(Bool) masterInitDone                  <- mkReg(False);
    Reg#(Bit#(16)) numIter                     <- mkReg(0);
    Reg#(Bit#(16)) maxIter                     <- mkReg(0);
    Reg#(Bit#(32)) cycleCnt                    <- mkReg(0);
    Reg#(Bit#(N_SYNC_NODES)) barrierInitValue  <- mkReg(0);
    Reg#(t_ADDR_X) startAddrX                  <- mkReg(0);
    Reg#(t_ADDR_Y) startAddrY                  <- mkReg(0);
    Reg#(t_ADDR_X) endAddrX                    <- mkReg(0);
    Reg#(t_ADDR_Y) endAddrY                    <- mkReg(0);
    Reg#(t_ADDR_X) testAddrX                   <- mkReg(0);
    Reg#(t_ADDR_Y) testAddrY                   <- mkReg(0);
    PulseWire      iterDoneW                   <- mkPulseWire();

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

        rule doMasterInit0 (!masterInitDone && masterInitCnt == 0);
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
            if ((testAddrX == 0) || (testAddrX == fromInteger(valueOf(N_X_POINTS)-1)) || (testAddrY == 0) || (testAddrY == fromInteger(valueOf(N_Y_POINTS)-1))) //boundaries
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
            if (testAddrX == fromInteger(valueOf(N_X_POINTS)-1)) 
            begin
                testAddrX <= 0;
                testAddrY <= testAddrY + 1;
                if (testAddrY == fromInteger(valueOf(N_Y_POINTS)-1))
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

    Reg#(Bool)                startIter  <- mkReg(True);
    Reg#(Bit#(3))             testPhase  <- mkReg(0);
    Vector#(5, Reg#(t_DATA))  testValues <- replicateM(mkReg(unpack(0)));
    FIFOF#(Bit#(3))           testReqQ   <- mkSizedFIFOF(32);
    Reg#(Bool)                iterDone   <- mkReg(False);
    Reg#(Bool)                 allDone   <- mkReg(False);

    rule initIter (initDone && startIter && (testPhase == 0));
        startIter <= False;
        testAddrX <= (startAddrX == 0)? 1 : startAddrX;
        testAddrY <= (startAddrY == 0)? 1 : startAddrY;
        if (endAddrX == fromInteger(valueOf(N_X_POINTS)-1))
        begin
            endAddrX <= endAddrX - 1;
        end
        if (testAddrY == fromInteger(valueOf(N_Y_POINTS)-1))
        begin
            endAddrY <= endAddrY - 1;
        end
        testPhase <= testPhase + 1;
        debugLog.record($format("initIter: iteration starts: numIter=%05d", numIter));
    endrule

    rule testPhase1 (initDone && (testPhase == 1));
        let addr = calAddr(testAddrX-1, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule

    rule testPhase2 (initDone && (testPhase == 2));
        let addr = calAddr(testAddrX, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule
    
    rule testPhase3 (initDone && (testPhase == 3));
        let addr = calAddr(testAddrX, testAddrY-1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule
    
    rule testPhase4 (initDone && (testPhase == 4));
        let addr = calAddr(testAddrX, testAddrY+1, truncate(numIter));
        cohMem.readReq(addr);
        testReqQ.enq(testPhase);
        testPhase <= testPhase + 1;
    endrule
    
    rule testPhase5 (initDone && (testPhase == 5));
        let addr = calAddr(testAddrX+1, testAddrY, truncate(numIter));
        cohMem.readReq(addr);
        testPhase <= testPhase + 1;
        testReqQ.enq(testPhase);
    endrule
    
    rule testRecv (initDone && testReqQ.notEmpty() && !iterDone);
        let idx = testReqQ.first();
        testReqQ.deq();
        let data <- cohMem.readRsp();
        if (idx != 5) // not the last response
        begin
            testValues[pack(idx)-1] <= data;
        end
        else // get the last value
        begin
            // write value
            t_DATA new_value = unpack(pack(testValues[0]) + pack(testValues[2]) + pack(testValues[3]) + pack(data) - (3 * pack(testValues[1])));
            Bool read_bit = unpack(truncate(numIter));
            let addr = calAddr(testAddrX, testAddrY, pack(!(read_bit)));
            cohMem.write(addr, new_value);
            debugLog.record($format("write: addr_x=0x%x, addr_y=0x%x, addr=0x%x, value=0x%x", 
                            testAddrX, testAddrY, addr, new_value));
            // move to next pixcel
            if (testAddrX == endAddrX)
            begin
                if (testAddrY == endAddrY) //end of interation 
                begin
                    iterDone <= True;
                end
                else // next row
                begin
                    testPhase <= 1;
                    testAddrX <= (startAddrX == 0)? 1 : startAddrX;
                    testAddrY <= testAddrY + 1;
                end
            end
            else // next pixel
            begin
                testPhase <= 3;
                testAddrX <= testAddrX + 1;
                testValues[0] <= testValues[1];
                testValues[1] <= data;
            end
        end
    endrule    
    
    rule waitForSync (initDone && (testPhase == 6) && iterDone);
        numIter  <= numIter + 1;
        iterDone <= False;
        if (numIter == maxIter) 
        begin
            allDone <= True;
            debugLog.record($format("waitForSync: all complete,  numIter=%05d", numIter));
        end
        else
        begin
            testAddrX <= (startAddrX == 0)? 1 : startAddrX;
            testAddrY <= (startAddrY == 0)? 1 : startAddrY;
            testPhase <= 1;
            iterDoneW.send();
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
        debugLog.record($format("setTestIter: numItern = %08d", num));
    endmethod
    
    method Action setAddrX(t_ADDR x);
        startAddrX <= truncateNP(pack(x));
        endAddrX <= truncateNP(pack(x)) + fromInteger(valueOf(N_COLS_PER_ENGINE)-1);
        debugLog.record($format("setAddrX: start address x = 0x%x", x));
    endmethod
    
    method Action setAddrY(t_ADDR y);
        startAddrY <= truncateNP(pack(y));
        endAddrY <= truncateNP(pack(y)) + fromInteger(valueOf(N_ROWS_PER_ENGINE)-1);
        debugLog.record($format("setAddrY: start address y = 0x%x", y));
    endmethod

    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
        noAction;
    endmethod

    method Bool initialized() = initDone;
    method Bool done() = allDone;
    method Bool iterationDone() = iterDoneW;
endmodule
