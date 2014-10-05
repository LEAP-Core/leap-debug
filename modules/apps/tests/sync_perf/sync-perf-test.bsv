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
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"

`include "asim/dict/VDEV_SYNCGROUP.bsh"
`include "asim/dict/VDEV_SCRATCH.bsh"

typedef Bit#(64) CYCLE_COUNTER;
typedef 8 N_TOTAL_ENGINES;

typedef Bit#(14) MEM_ADDRESS;
typedef Bit#(64) MEM_DATA;

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
// Implement a synchronization performance test
//
module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(MEM_DATA, t_MEM_DATA_SZ));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    // Allocate coherent scratchpad controller for sync test engines
    if (`SYNC_PERF_TEST_MEM_ENABLE == 1)
    begin
        COH_SCRATCH_CONTROLLER_CONFIG controllerConf = defaultValue;
        controllerConf.cacheMode = COH_SCRATCH_CACHED;
        NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
        NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
        mkCoherentScratchpadController(`VDEV_SCRATCH_SYNC_DATA, `VDEV_SCRATCH_SYNC_BITS, addr_size, data_size, controllerConf);
    end
    
    Vector#(N_TOTAL_ENGINES, SYNC_TEST_ENGINE_IFC) syncEngines = newVector(); 
    Vector#(N_TOTAL_ENGINES, DEBUG_FILE) debugLogs = newVector();
    Vector#(N_TOTAL_ENGINES, DEBUG_FILE) debugLogMs = newVector();
    
    Vector#(N_TOTAL_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, MEM_DATA)) memories = newVector();
    COH_SCRATCH_CLIENT_CONFIG clientConf = defaultValue;
    clientConf.cacheMode = COH_SCRATCH_CACHED;

    for(Integer p = 0; p < valueOf(N_TOTAL_ENGINES); p = p + 1)
    begin
        debugLogs[p] <- mkDebugFile("sync_test_engine_"+integerToString(p)+".out");
        if (`SYNC_PERF_TEST_MEM_ENABLE == 1)
        begin
            memories[p] <- mkCoherentScratchpadClient(`VDEV_SCRATCH_SYNC_DATA, clientConf);
            syncEngines[p] <- mkMemSyncTestEngine(memories[p], debugLogs[p], (p == 0)); 
        end
        else
        begin
            syncEngines[p] <- mkSyncTestEngine(debugLogs[p], (p == 0)); 
        end
    end
    
    DEBUG_FILE debugLog <- mkDebugFile("sync_perf_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    Param#(16) iterParam <-mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_SYNC_PERF_TEST_ITER, paramNode);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(STATE) state <- mkReg(STATE_init);

    // Messages
    let msgInit <- getGlobalStringUID("syncPerfTest: start\n");
    let msgInitDone <- getGlobalStringUID("syncPerfTest: initialization done, cycle: %012d\n");
    let msgDone <- getGlobalStringUID("syncPerfTest: done cycle: %012d, iter=%06d, test cycle count: %012d\n");
    
    Reg#(Bit#(2)) initCnt             <- mkReg(0);
    Reg#(CYCLE_COUNTER) cycleCnt      <- mkReg(0);
    Reg#(CYCLE_COUNTER) initCycleCnt  <- mkReg(0);
    Reg#(Bit#(16)) numIter            <- mkReg(0);
  
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

    rule doInit1 (state == STATE_init && initCnt == 1);
        Vector#(N_SYNC_NODES, Bool) barriers = replicate(False);
        for(Integer p = 0; p < valueOf(N_TOTAL_ENGINES); p = p + 1)
        begin 
            barriers[p] = True;
            syncEngines[p].setIter(iterParam);
        end
        numIter <= iterParam;
        syncEngines[0].setBarrier(pack(barriers));
        initCnt <= initCnt + 1;
        debugLog.record($format("doInit: initCnt = 1"));
    endrule

    rule doInit2 (state == STATE_init && initCnt == 2 && syncEngines[0].initialized());
        initCnt <= 0;
        state <= STATE_test;
        initCycleCnt  <= cycleCnt;
        stdio.printf(msgInitDone, list1(zeroExtend(cycleCnt)));
        debugLog.record($format("initialization done, cycle=0x%011d", cycleCnt));
    endrule

    rule waitForAllDone (state == STATE_test && syncEngines[0].done());
        state <= STATE_finished;
        debugLog.record($format("waitForAllDone: all engines complete, cycle=0x%011d", cycleCnt));
    endrule

    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        stdio.printf(msgDone, list3(zeroExtend(cycleCnt), zeroExtend(numIter), zeroExtend(cycleCnt-initCycleCnt)));
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule

