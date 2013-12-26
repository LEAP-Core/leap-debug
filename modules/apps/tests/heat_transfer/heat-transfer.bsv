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
`include "awb/provides/heat_transfer_local.bsh"
`include "awb/provides/heat_transfer_remote.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_HEAT_TRANSFER_COMMON.bsh"

//
// Implement a heat transfer test
//
module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));


    if (valueOf(N_TOTAL_ENGINES)>1)
    begin
        // Allocate coherent scratchpad controller for heat engines
        COH_SCRATCH_CONFIG conf = defaultValue;
        conf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        
        NumTypeParam#(t_MEM_ADDR_SZ) addr_size = ?;
        NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;
        mkCoherentScratchpadController(`VDEV_SCRATCH_HEAT_DATA, `VDEV_SCRATCH_HEAT_BITS, addr_size, data_size, conf);
    end

    mkHeatTransferTestLocal();
    mkHeatTransferTestRemote();

endmodule

