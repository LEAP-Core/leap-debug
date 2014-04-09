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


//
// Implement a heat transfer controller
//
module [CONNECTED_MODULE] mkHeatTransferTestController ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    if (valueOf(N_TOTAL_ENGINES)>1)
    begin
        // Allocate coherent scratchpad controller for heat engines
        COH_SCRATCH_CONFIG controllerConf = defaultValue;
        // COH_SCRATCH_CONTROLLER_CONFIG controllerConf = defaultValue;
        controllerConf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        
        // if (`HEAT_TRANSFER_TEST_MULTI_CONTROLLER_ENABLE == 1)
        // begin
        //     controllerConf.multiController = True;
        //     controllerConf.baseAddr = unpack(0);
        //     controllerConf.addrRange = fromInteger(valueOf(TMul#(TMul#(N_LOCAL_ENGINES, N_POINTS_PER_ENGINE),2)));
        //     controllerConf.coherenceDomainID = `VDEV_COH_SCRATCH_HEAT;
        //     controllerConf.isMaster = True;
        // end
        
        NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
        NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
        mkCoherentScratchpadController(`VDEV_SCRATCH_HEAT_DATA, `VDEV_SCRATCH_HEAT_BITS, addr_size, data_size, controllerConf);
    end
    
endmodule

