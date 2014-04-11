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
`include "asim/provides/heat_transfer_common_params.bsh"
`include "awb/provides/heat_transfer_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/VDEV_COH_SCRATCH.bsh"
`include "asim/dict/PARAMS_HEAT_TRANSFER_COMMON.bsh"

//
// Implement a heat transfer test
//
module [CONNECTED_MODULE] mkHeatTransferTestRemote ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    // if (valueOf(N_TOTAL_ENGINES)>1 && `HEAT_TRANSFER_TEST_MULTI_CONTROLLER_ENABLE == 1)
    // begin
    //     // Allocate coherent scratchpad controller for heat engines
    //     COH_SCRATCH_CONTROLLER_CONFIG controllerConf = defaultValue;
    //     controllerConf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    //     controllerConf.multiController = True;
    //     controllerConf.baseAddr = fromInteger(valueOf(TMul#(TMul#(N_LOCAL_ENGINES, N_POINTS_PER_ENGINE),2)));
    //     controllerConf.addrRange = fromInteger(valueOf(TMul#(TMul#(N_REMOTE_ENGINES, N_POINTS_PER_ENGINE),2)));
    //     controllerConf.coherenceDomainID = `VDEV_COH_SCRATCH_HEAT;
    //     controllerConf.isMaster = False;
    //     
    //     NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
    //     NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
    //     mkCoherentScratchpadController(`VDEV_SCRATCH_HEAT_DATA2, `VDEV_SCRATCH_HEAT_BITS2, addr_size, data_size, controllerConf);
    // end
    
    if (valueOf(N_REMOTE_ENGINES)>0)
    begin
        //
        // Allocate coherent scratchpads for heat engines
        //
        // COH_SCRATCH_CLIENT_CONFIG clientConf = defaultValue;
        COH_SCRATCH_CONFIG clientConf = defaultValue;
        clientConf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        // clientConf.multiController = (`HEAT_TRANSFER_TEST_MULTI_CONTROLLER_ENABLE == 1);
        
        function String genDebugMemoryFileName(Integer id);
            return "heat_engine_memory_"+integerToString(id + valueOf(N_LOCAL_ENGINES))+".out";
        endfunction
        
        function String genDebugEngineFileName(Integer id);
            return "heat_engine_"+integerToString(id + valueOf(N_LOCAL_ENGINES))+".out";
        endfunction

        function ActionValue#(MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) doCurryCohClient(mFunction, x, y);
            actionvalue
                Integer scratchpadID = (`HEAT_TRANSFER_TEST_MULTI_CONTROLLER_ENABLE == 1)? `VDEV_SCRATCH_HEAT_DATA2 : `VDEV_SCRATCH_HEAT_DATA;
                let m <- mFunction(scratchpadID, x + valueOf(N_LOCAL_ENGINES), clientConf, y);
                return m;
            endactionvalue
        endfunction

        function ActionValue#(HEAT_ENGINE_IFC#(MEM_ADDRESS)) doCurryHeatEngine(mFunction, x, y);
            actionvalue
                let m <- mFunction(x, y, False);
                return m;
            endactionvalue
        endfunction
        
        Vector#(N_REMOTE_ENGINES, String) debugLogMNames = genWith(genDebugMemoryFileName);
        Vector#(N_REMOTE_ENGINES, String) debugLogENames = genWith(genDebugEngineFileName);
        Vector#(N_REMOTE_ENGINES, DEBUG_FILE) debugLogMs <- mapM(mkDebugFile, debugLogMNames); 
        Vector#(N_REMOTE_ENGINES, DEBUG_FILE) debugLogEs <- mapM(mkDebugFile, debugLogENames);

        Vector#(N_REMOTE_ENGINES, Integer) clientIds = genVector();
        let mkCohClientVec = replicate(mkDebugCoherentScratchpadClient);
        Vector#(N_REMOTE_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) memories <- 
            zipWith3M(doCurryCohClient, mkCohClientVec, clientIds, debugLogMs);

        let mkHeatEngineVec = replicate(mkHeatEngine);
        Vector#(N_REMOTE_ENGINES, HEAT_ENGINE_IFC#(MEM_ADDRESS)) engines <-
            zipWith3M(doCurryHeatEngine, mkHeatEngineVec, memories, debugLogEs);
        
        DEBUG_FILE debugLog <- mkDebugFile("heat_transfer_test_remote.out");

        Reg#(Bit#(5))  bidX               <- mkReg(0);
        Reg#(Bit#(5))  bidY               <- mkReg(0);
        Reg#(Bit#(10)) engineID           <- mkReg(0);
        Reg#(Bool)     blockIdInitDone    <- mkReg(False);
  
        rule blockIdInit (!blockIdInitDone);
            if (engineID >= fromInteger(valueOf(N_LOCAL_ENGINES)))
            begin
                MEM_ADDRESS addr_x = unpack(zeroExtend(bidX) * fromInteger(valueOf(N_COLS_PER_ENGINE)));
                MEM_ADDRESS addr_y = unpack(zeroExtend(bidY) * fromInteger(valueOf(N_ROWS_PER_ENGINE)));
                engines[resize(engineID - fromInteger(valueOf(N_LOCAL_ENGINES)))].setAddrX(addr_x);
                engines[resize(engineID - fromInteger(valueOf(N_LOCAL_ENGINES)))].setAddrY(addr_y);
                debugLog.record($format("blockIdInit: engineID: %2d, addrX: 0x%x, addrY: 0x%x", engineID, addr_x, addr_y));
            end
            if (engineID == fromInteger(valueOf(N_TOTAL_ENGINES)-1))
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

    end

endmodule
