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
// Implement a heat transfer controller
//
module [CONNECTED_MODULE] mkHeatTransferTestController ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    if (valueOf(N_TOTAL_ENGINES)>1)
    begin
        // Allocate coherent scratchpad controller for heat engines
        COH_SCRATCH_CONTROLLER_CONFIG controllerConf = defaultValue;
        controllerConf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
        NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
        
        if (`HEAT_TRANSFER_TEST_MULTI_CONTROLLER_ENABLE == 1)
        begin
            Reg#(Bit#(TAdd#(TLog#(N_X_MAX_POINTS), 1))) numXPoints <- mkWriteValidatedReg();
            Reg#(Bit#(TAdd#(TLog#(N_Y_MAX_POINTS), 1))) numYPoints <- mkWriteValidatedReg();
            Bit#(TAdd#(TLog#(N_X_MAX_POINTS), 1)) numColsPerEngine = numXPoints >> valueOf(TLog#(N_X_ENGINES));
            Bit#(TAdd#(TLog#(N_Y_MAX_POINTS), 1)) numRowsPerEngine = numYPoints >> valueOf(TLog#(N_Y_ENGINES));
            MEM_ADDRESS numPointsPerEngine = unpack(zeroExtend(numColsPerEngine)*zeroExtend(numRowsPerEngine));

            COH_SCRATCH_MEM_ADDRESS baseAddr  = 0;
            COH_SCRATCH_MEM_ADDRESS addrRange = zeroExtendNP(pack(numPointsPerEngine)) << valueOf(TAdd#(TLog#(N_LOCAL_ENGINES), 1));

            controllerConf.multiController = True;
            controllerConf.coherenceDomainID = `VDEV_COH_SCRATCH_HEAT;
            controllerConf.isMaster = True;
            controllerConf.partition = mkCohScratchControllerAddrPartition(baseAddr, addrRange, data_size); 
        
            // Dynamic parameters.
            PARAMETER_NODE paramNode <- mkDynamicParameterNode();
            Param#(16) numXParam <- mkDynamicParameter(`PARAMS_HEAT_TRANSFER_COMMON_HEAT_TRANSFER_TEST_X_POINTS, paramNode);
            Param#(16) numYParam <- mkDynamicParameter(`PARAMS_HEAT_TRANSFER_COMMON_HEAT_TRANSFER_TEST_Y_POINTS, paramNode);
       
            Reg#(Bool) initialized <- mkReg(False);

            rule doInit (!initialized);
                numXPoints  <= resize(numXParam);
                numYPoints  <= resize(numYParam);
                initialized <= True;
            endrule
        end
        
        mkCoherentScratchpadController(`VDEV_SCRATCH_HEAT_DATA, `VDEV_SCRATCH_HEAT_BITS, addr_size, data_size, controllerConf);
    
    end
    
endmodule

