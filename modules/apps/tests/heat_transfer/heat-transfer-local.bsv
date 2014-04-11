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
import Vector::*;
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "asim/provides/lock_sync_service.bsh"
`include "asim/provides/heat_transfer_common_params.bsh"
`include "awb/provides/heat_transfer_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/VDEV_COH_SCRATCH.bsh"
`include "asim/dict/PARAMS_HEAT_TRANSFER_COMMON.bsh"

typedef enum
{
    STATE_init,
    STATE_test,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);

//
// Implement a heat transfer test
//
module [CONNECTED_MODULE] mkHeatTransferTestLocal ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate coherent scratchpads for heat engines
    //
    // COH_SCRATCH_CLIENT_CONFIG clientConf = defaultValue;
    COH_SCRATCH_CONFIG clientConf = defaultValue;
    clientConf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    // clientConf.multiController = (`HEAT_TRANSFER_TEST_MULTI_CONTROLLER_ENABLE == 1);

    Vector#(N_LOCAL_ENGINES, DEBUG_FILE) debugLogMs = newVector();
    Vector#(N_LOCAL_ENGINES, DEBUG_FILE) debugLogEs = newVector();
    Vector#(N_LOCAL_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) memories = newVector();
    Vector#(N_LOCAL_ENGINES, HEAT_ENGINE_IFC#(MEM_ADDRESS)) engines = newVector();

    if (valueOf(N_LOCAL_ENGINES) == 0 || (valueOf(N_LOCAL_ENGINES) > valueOf(N_TOTAL_ENGINES)))
    begin
        // N_LOCAL_ENGINES should be at least 1 and should not be larger than N_TOTAL_ENGINES
        error("Invalid number of local heat engines");
    end
    
    function String genDebugMemoryFileName(Integer id);
        return "heat_engine_memory_"+integerToString(id)+".out";
    endfunction
    
    function String genDebugEngineFileName(Integer id);
        return "heat_engine_"+integerToString(id)+".out";
    endfunction

    function ActionValue#(MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) doCurryCohClient(mFunction, x, y);
        actionvalue
            let m <- mFunction(`VDEV_SCRATCH_HEAT_DATA, x, clientConf, y);
            return m;
        endactionvalue
    endfunction

    function doCurryHeatEngineConstructor(mFunction, x, y);
        return mFunction(x,y);
    endfunction

    function ActionValue#(HEAT_ENGINE_IFC#(MEM_ADDRESS)) doCurryHeatEngine(mFunction, id);
        actionvalue
            let m <- mFunction(id == 0);
            return m;
        endactionvalue
    endfunction

    if (valueOf(N_TOTAL_ENGINES)>1)
    begin
        Vector#(N_LOCAL_ENGINES, String) debugLogMNames = genWith(genDebugMemoryFileName);
        Vector#(N_LOCAL_ENGINES, String) debugLogENames = genWith(genDebugEngineFileName);

        debugLogMs <- mapM(mkDebugFile, debugLogMNames);
        debugLogEs <- mapM(mkDebugFile, debugLogENames);
       
        Vector#(N_LOCAL_ENGINES, Integer) clientIds = genVector();
        let mkCohClientVec = replicate(mkDebugCoherentScratchpadClient);
        memories <- zipWith3M(doCurryCohClient, mkCohClientVec, clientIds, debugLogMs);

        let mkHeatEngineVec = replicate(mkHeatEngine);
        let engineConstructors = zipWith3(doCurryHeatEngineConstructor, mkHeatEngineVec, memories, debugLogEs);
        engines <- zipWithM(doCurryHeatEngine, engineConstructors, genVector());
    end
    else
    begin
        SCRATCHPAD_CONFIG sconf = defaultValue;
        sconf.cacheMode = SCRATCHPAD_CACHED;
        debugLogMs[0] <- mkDebugFile("heat_engine_memory_0.out");
        debugLogEs[0] <- mkDebugFile("heat_engine_0.out");
        MEMORY_IFC#(MEM_ADDRESS, TEST_DATA) memory <- mkScratchpad(`VDEV_SCRATCH_HEAT_DATA, sconf);
        engines[0]    <- mkHeatEnginePrivate(memory, debugLogEs[0]);
    end

    DEBUG_FILE debugLog <- mkDebugFile("heat_transfer_test_local.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    Param#(16) iterParam <-mkDynamicParameter(`PARAMS_HEAT_TRANSFER_COMMON_HEAT_TRANSFER_TEST_ITER, paramNode);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(STATE) state <- mkReg(STATE_init);

    // Messages
    let msgInit <- getGlobalStringUID("heatTransferTest: start\n");
    let msgInitDone <- getGlobalStringUID("heatTransferTest: initialization done, cycle: %012d\n");
    let msgTest <- getGlobalStringUID("heatTransferTest: frame size: %05d x %05d, # engines: %03d, # iter: %06d\n");
    let msgDone <- getGlobalStringUID("heatTransferTest: done cycle: %012d, test cycle count: %012d\n");
    
    Reg#(Bit#(2)) initCnt             <- mkReg(0);
    Reg#(CYCLE_COUNTER) cycleCnt      <- mkReg(0);
    Reg#(CYCLE_COUNTER) initCycleCnt  <- mkReg(0);
    Reg#(Bit#(5))  bidX               <- mkReg(0);
    Reg#(Bit#(5))  bidY               <- mkReg(0);
    Reg#(Bit#(10)) engineID           <- mkReg(0);
    Reg#(Bool)     blockIdInitDone    <- mkReg(False);
  
    (* fire_when_enabled *)
    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule

    rule doInit0 (state == STATE_init && initCnt == 0);
        linkStarterStartRun.deq();
        initCnt <= initCnt + 1;
        stdio.printf(msgInit, List::nil);
        debugLog.record($format("doInit: initCnt = 0"));
    endrule

    function Bool genBarrierInitVal(Integer id);
        return (id < valueOf(N_TOTAL_ENGINES))? True : False;
    endfunction

    rule doInit1 (state == STATE_init && initCnt == 1);
        Vector#(N_SYNC_NODES, Bool) barriers = genWith(genBarrierInitVal);
        engines[0].setIter(iterParam);
        engines[0].setBarrier(pack(barriers));
        initCnt <= initCnt + 1;
        debugLog.record($format("doInit: initCnt = 1, barrier = 0x%x", pack(barriers)));
        stdio.printf(msgTest, list4(fromInteger(valueOf(N_X_POINTS)), 
                                    fromInteger(valueOf(N_Y_POINTS)), 
                                    fromInteger(valueOf(N_X_ENGINES)*valueOf(N_Y_ENGINES)), 
                                    zeroExtend(iterParam)));
    endrule

    rule doInit2 (state == STATE_init && initCnt == 2 && blockIdInitDone);
        initCnt <= initCnt + 1;
    endrule

    rule doInit3 (state == STATE_init && initCnt == 3 && engines[0].initialized());
        initCnt <= 0;
        state <= STATE_test;
        initCycleCnt  <= cycleCnt;
        stdio.printf(msgInitDone, list1(zeroExtend(cycleCnt)));
        debugLog.record($format("initialization done, cycle=0x%011d", cycleCnt));
    endrule

    rule blockIdInit (state == STATE_init && initCnt == 2 && !blockIdInitDone);
        MEM_ADDRESS addr_x = unpack(zeroExtend(bidX) * fromInteger(valueOf(N_COLS_PER_ENGINE)));
        MEM_ADDRESS addr_y = unpack(zeroExtend(bidY) * fromInteger(valueOf(N_ROWS_PER_ENGINE)));
        engines[resize(engineID)].setAddrX(addr_x);
        engines[resize(engineID)].setAddrY(addr_y);
        debugLog.record($format("blockIdInit: engineID: %2d, addrX: 0x%x, addrY: 0x%x", engineID, addr_x, addr_y));
        if (engineID == fromInteger(valueOf(N_LOCAL_ENGINES)-1))
        begin
            blockIdInitDone <= True;
        end
        else if (bidX == fromInteger(valueOf(N_X_ENGINES)-1))
        begin
            bidX <= 0;
            bidY <= bidY + 1;
        end
        else
        begin
            bidX <= bidX + 1;
        end
        engineID <= engineID + 1;
    endrule

    rule waitForAllDone (state == STATE_test && engines[0].done());
        state <= STATE_finished;
        debugLog.record($format("waitForAllDone: all engines complete, cycle=0x%011d", cycleCnt));
    endrule

    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        stdio.printf(msgDone, list2(zeroExtend(cycleCnt), zeroExtend(cycleCnt-initCycleCnt)));
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule
