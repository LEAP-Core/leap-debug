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
import Vector::*;
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "asim/provides/coh_mem_test_common_params.bsh"
`include "awb/provides/coh_mem_test_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/VDEV_COH_SCRATCH.bsh"
`include "asim/dict/PARAMS_COH_MEM_TEST_COMMON.bsh"

//
// Coherent scratchpad memory test remote module
// This module is used for multi-controller test
//
module [CONNECTED_MODULE] mkCohMemTestRemote ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));
    
    Reg#(COH_SCRATCH_MEM_ADDRESS) memoryMax <- mkWriteValidatedReg();
    
    if (`COH_MEM_TEST_MULTI_CONTROLLER_ENABLE == 1)
    begin
        //
        // Allocate another coherent scratchpad controller
        //
        NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
        NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
        COH_SCRATCH_MEM_ADDRESS baseAddr  = (memoryMax._read())>>1;
        COH_SCRATCH_MEM_ADDRESS addrRange = (memoryMax._read());
        
        COH_SCRATCH_CONTROLLER_CONFIG controllerConf = defaultValue;
        controllerConf.cacheMode = (`COH_MEM_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        controllerConf.multiController = True;
        controllerConf.coherenceDomainID = `VDEV_COH_SCRATCH_MEMTEST;
        controllerConf.isMaster = False;
        controllerConf.partition = mkCohScratchControllerAddrPartition(baseAddr, addrRange, data_size); 
        
        let originalID <- getSynthesisBoundaryPlatformID();
        let platformID = (`FPGA_NUM_PLATFORMS != 1)? 1 : 0;
        putSynthesisBoundaryPlatformID(platformID);
        mkCoherentScratchpadController(`VDEV_SCRATCH_COH_MEMTEST_DATA2, `VDEV_SCRATCH_COH_MEMTEST_BITS2, addr_size, data_size, controllerConf);
        putSynthesisBoundaryPlatformID(originalID);
    end

    
    if (valueOf(N_REMOTE_ENGINES)>0)
    begin
        
        COH_SCRATCH_CLIENT_CONFIG clientConf = defaultValue;
        clientConf.cacheMode = (`COH_MEM_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        clientConf.multiController = (`COH_MEM_TEST_MULTI_CONTROLLER_ENABLE == 1);
   
        Vector#(N_REMOTE_ENGINES, DEBUG_FILE) debugLogMs = newVector();
        Vector#(N_REMOTE_ENGINES, DEBUG_FILE) debugLogEs = newVector();
        Vector#(N_REMOTE_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) memories = newVector();
        Vector#(N_REMOTE_ENGINES, COH_MEM_TEST_ENGINE_IFC#(MEM_ADDRESS)) engines = newVector();
        
        function String genDebugMemoryFileName(Integer id);
            return "coh_memory_"+integerToString(id + valueOf(N_LOCAL_ENGINES))+".out";
        endfunction
        
        function String genDebugEngineFileName(Integer id);
            return "coh_test_engine_"+integerToString(id + valueOf(N_LOCAL_ENGINES))+".out";
        endfunction

        function ActionValue#(MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) doCurryCohClient(mFunction, x, y);
            actionvalue
                Integer scratchpadId = (`COH_MEM_TEST_MULTI_CONTROLLER_ENABLE == 1)? `VDEV_SCRATCH_COH_MEMTEST_DATA2 : `VDEV_SCRATCH_COH_MEMTEST_DATA;
                let m <- mFunction(scratchpadId, x + valueOf(N_LOCAL_ENGINES), clientConf, y);
                return m;
            endactionvalue
        endfunction

        function doCurryTestEngineConstructor(mFunction, x, y);
            return mFunction(x,y + valueOf(N_LOCAL_ENGINES));
        endfunction

        function ActionValue#(COH_MEM_TEST_ENGINE_IFC#(MEM_ADDRESS)) doCurryTestEngine(mFunction, x);
            actionvalue
                let m <- mFunction(x);
                return m;
            endactionvalue
        endfunction

        Vector#(N_REMOTE_ENGINES, String) debugLogMNames = genWith(genDebugMemoryFileName);
        Vector#(N_REMOTE_ENGINES, String) debugLogENames = genWith(genDebugEngineFileName);
        debugLogMs <- mapM(mkDebugFile, debugLogMNames);
        debugLogEs <- mapM(mkDebugFile, debugLogENames);
        
        Vector#(N_REMOTE_ENGINES, Integer) clientIds = genVector();
        let mkCohClientVec = replicate(mkDebugCoherentScratchpadClient);
        memories <- zipWith3M(doCurryCohClient, mkCohClientVec, clientIds, debugLogMs);

        let mkTestEngineVec = replicate(mkCohMemTestEngine);
        let engineConstructors = zipWith3(doCurryTestEngineConstructor, mkTestEngineVec, memories, genVector());
        engines <- zipWithM(doCurryTestEngine, engineConstructors, debugLogEs);
        
        
        // Dynamic parameters.
        PARAMETER_NODE paramNode <- mkDynamicParameterNode();

        Param#(24) iterParam   <- mkDynamicParameter(`PARAMS_COH_MEM_TEST_COMMON_COH_MEM_TEST_NUM, paramNode);
        Param#(5) wsetBitParam <- mkDynamicParameter(`PARAMS_COH_MEM_TEST_COMMON_COH_MEM_TEST_WORKING_SET_BIT, paramNode);

        Reg#(Bool) initialized       <- mkReg(False);
        Reg#(Bool) engineInitialized <- mkReg(False);
        Reg#(Bit#(24)) maxIter       <- mkReg(0);
        Reg#(MEM_ADDRESS) wset       <- mkReg(unpack(0));

        rule doInit (!initialized);
            MEM_ADDRESS w_set = 1 << wsetBitParam;
            wset        <= w_set;
            maxIter     <= iterParam;
            memoryMax   <= zeroExtendNP(w_set);
            initialized <= True;
        endrule

        Reg#(ENGINE_PORT_NUM) engineId <- mkReg(0);

        rule engineInit (initialized && !engineInitialized);
            engines[resize(engineId)].setIter(maxIter);
            engines[resize(engineId)].setWorkingSet(wset);
            engineId <= engineId + 1;
            if (engineId == fromInteger(valueOf(N_REMOTE_ENGINES)-1))
            begin
                engineInitialized <= True;
            end
        endrule
    
    end

endmodule

