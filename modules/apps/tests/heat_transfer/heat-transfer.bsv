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

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_HARDWARE_SYSTEM.bsh"


typedef Bit#(64) CYCLE_COUNTER;

typedef 256 N_X_POINTS;
typedef 256 N_Y_POINTS;
typedef   2 N_X_ENGINES;
typedef   2 N_Y_ENGINES;
typedef TMul#(N_X_ENGINES, N_Y_ENGINES) N_TOTAL_ENGINES;
typedef TMul#(N_X_POINTS, N_Y_POINTS)  N_TOTAL_POINTS;
typedef TDiv#(N_Y_POINTS, N_Y_ENGINES) N_ROWS_PER_ENGINE;
typedef TDiv#(N_X_POINTS, N_X_ENGINES) N_COLS_PER_ENGINE;
typedef Bit#(TAdd#(TAdd#(TLog#(N_X_POINTS),TLog#(N_Y_POINTS)),2)) MEM_ADDRESS;
typedef Bit#(30) TEST_DATA;

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
module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    //
    // Allocate coherent scratchpads for heat engines
    //
    COH_SCRATCH_CONFIG conf = defaultValue;
    conf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;

    Vector#(N_TOTAL_ENGINES, DEBUG_FILE) debugLogMs = newVector();
    Vector#(N_TOTAL_ENGINES, DEBUG_FILE) debugLogEs = newVector();
    Vector#(N_TOTAL_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) memories = newVector();
    Vector#(N_TOTAL_ENGINES, HEAT_ENGINE_IFC#(MEM_ADDRESS)) engines = newVector();

    if (valueOf(N_TOTAL_ENGINES)>1)
    begin
        mkCoherentScratchpadController(`VDEV_SCRATCH_HEAT_DATA, `VDEV_SCRATCH_HEAT_BITS, addr_size, data_size, conf);
        for(Integer p = 0; p < valueOf(N_TOTAL_ENGINES); p = p + 1)
        begin
            debugLogMs[p] <- mkDebugFile("heat_engine_memory_"+integerToString(p)+".out");
            debugLogEs[p] <- mkDebugFile("heat_engine_"+integerToString(p)+".out");
            memories[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_HEAT_DATA, p, conf, debugLogMs[p]);
            engines[p] <- mkHeatEngine(p, memories[p], debugLogEs[p], p == 0);
        end
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

    DEBUG_FILE debugLog <- mkDebugFile("heat_transfer_test.out");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    // Verbose mode
    //  0 -- quiet
    //  1 -- verbose
    Param#(1) verboseMode <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_HEAT_TRANSFER_TEST_VERBOSE, paramNode);
    let verbose = verboseMode == 1;
    Param#(16) iterParam <-mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_HEAT_TRANSFER_TEST_ITER, paramNode);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    Reg#(STATE) state <- mkReg(STATE_init);

    // Messages
    let msgInit <- getGlobalStringUID("heatTransferTest: start\n");
    let msgInitDone <- getGlobalStringUID("heatTransferTest: initialization done, cycle: %012d\n");
    let msgTest <- getGlobalStringUID("heatTransferTest: frame size: %05d x %05d, # engines: %03d, # iter: %06d\n");
    let msgIterDone <- getGlobalStringUID("heatTransferTest: %06d iteration done, cycle: %012d, test cycle count: %012d\n");
    let msgDone <- getGlobalStringUID("heatTransferTest: done cycle: %012d, test cycle count: %012d\n");
    
    Reg#(Bit#(2)) initCnt             <- mkReg(0);
    Reg#(CYCLE_COUNTER) cycleCnt      <- mkReg(0);
    Reg#(CYCLE_COUNTER) initCycleCnt  <- mkReg(0);
    Reg#(CYCLE_COUNTER) startCycleCnt <- mkReg(0);
    Reg#(Bit#(16)) numIter            <- mkReg(0);
    Reg#(Bit#(16)) maxIter            <- mkReg(0);
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

    rule doInit1 (state == STATE_init && initCnt == 1);
        Vector#(N_SYNC_NODES, Bool) barriers = replicate(False);
        for(Integer p = 0; p < valueOf(N_TOTAL_ENGINES); p = p + 1)
        begin 
            engines[p].setIter(iterParam);
            barriers[p] = True;
        end
        initCnt <= initCnt + 1;
        maxIter <= iterParam;
        engines[0].setBarrier(pack(barriers));
        debugLog.record($format("doInit: initCnt = 1"));
        stdio.printf(msgTest, list4(fromInteger(valueOf(N_X_POINTS)), 
                                    fromInteger(valueOf(N_Y_POINTS)), 
                                    fromInteger(valueOf(N_X_ENGINES)*valueOf(N_Y_ENGINES)), 
                                    zeroExtend(iterParam)));
    endrule

    rule doInit2 (state == STATE_init && initCnt == 2 && blockIdInitDone);
        initCnt <= initCnt + 1;
    endrule

    rule doInit3 (state == STATE_init && initCnt == 3);
        Vector#(N_TOTAL_ENGINES, Bool) dones = newVector();
        for(Integer p = 0; p < valueOf(N_TOTAL_ENGINES); p = p + 1)
        begin 
            dones[p] = engines[p].initialized(); 
        end
        if (fold(\&& , dones)) // all initialized
        begin
            initCnt <= 0;
            state <= STATE_test;
            initCycleCnt <= cycleCnt;
            startCycleCnt <= cycleCnt;
            stdio.printf(msgInitDone, list1(zeroExtend(cycleCnt)));
            debugLog.record($format("initialization done, cycle=0x%11d", cycleCnt));
        end
    endrule

    rule blockIdInit (state == STATE_init && initCnt == 2 && !blockIdInitDone);
        MEM_ADDRESS addr_x = unpack(zeroExtend(bidX) * fromInteger(valueOf(N_COLS_PER_ENGINE)));
        MEM_ADDRESS addr_y = unpack(zeroExtend(bidY) * fromInteger(valueOf(N_ROWS_PER_ENGINE)));
        engines[resize(engineID)].setAddrX(addr_x);
        engines[resize(engineID)].setAddrY(addr_y);
        if (bidX == fromInteger(valueOf(N_X_ENGINES)-1))
        begin
            bidX <= 0;
            bidY <= bidY + 1;
            if (bidY == fromInteger(valueOf(N_Y_ENGINES)-1))
            begin
                blockIdInitDone <= True;
            end
        end
        else
        begin
            bidX <= bidX + 1;
            bidY <= bidY;
        end
        engineID <= engineID + 1;
    endrule

    rule printIterDone (state == STATE_test && engines[0].iterationDone());
        stdio.printf(msgIterDone, list3(zeroExtend(numIter), resize(cycleCnt), resize(cycleCnt-startCycleCnt)));
        numIter <= numIter + 1;
        startCycleCnt <= cycleCnt;
        debugLog.record($format("%06d iteration done, cycle=0x%11d", numIter, cycleCnt));
    endrule

    rule waitForAllDone (state == STATE_test && engines[0].done());
        state <= STATE_finished;
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
