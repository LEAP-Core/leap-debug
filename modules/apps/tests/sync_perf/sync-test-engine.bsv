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

`include "asim/dict/VDEV_SYNCGROUP.bsh"

interface SYNC_TEST_ENGINE_IFC;
    method Action setIter(Bit#(16) num);
    method Action setBarrier(Bit#(N_SYNC_NODES) barrier);
    method Bool initialized();
    method Bool done();
endinterface

//
// Heat engine implementation
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
        debugLog.record($format("setTestIter: numItern = %08d", num));
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


