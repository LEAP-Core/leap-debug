//
// Copyright (C) 2012 MIT
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

`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh" 
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/mem_services.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/coherent_scratchpad_memory_service.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "awb/provides/mem_perf_tester.bsh"
`include "awb/provides/mem_perf_tester_alt.bsh"

module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));

    //
    // Allocate scratchpads
    //
    COH_SCRATCH_CONFIG conf = defaultValue;
    conf.cacheMode = COH_SCRATCH_CACHED;

    // Coherent scratchpads
    NumTypeParam#(SizeOf#(MEM_ADDRESS)) addr_size = ~0;
    NumTypeParam#(SizeOf#(MEM_DATA)) data_size = ~0;

    mkCoherentScratchpadController(`VDEV_SCRATCH_COH_MEMPERF_DATA, `VDEV_SCRATCH_COH_MEMPERF_BITS, addr_size, data_size, conf);

    let mem_tester <- mkMemTester();
    let mem_tester_alt <- mkMemTesterAlt();
    let mem_perf_driver <- mkMemPerfDriver();
  
endmodule
