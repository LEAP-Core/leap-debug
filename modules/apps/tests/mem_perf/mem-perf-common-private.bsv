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
import Vector::*;
import GetPut::*;
import DefaultValue::*;

`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"


module [CONNECTED_MODULE] mkTestMemory#(Integer scratchpadID, Bool addCaches) (MEMORY_IFC#(t_ADDR, t_DATA))
   provisos (Bits#(t_ADDR, t_ADDR_SZ),
             Bits#(t_DATA, t_DATA_SZ));

    //
    // Allocate scratchpads
    //

    SCRATCHPAD_CONFIG sconf = defaultValue;
    sconf.cacheMode = (addCaches ? SCRATCHPAD_CACHED :
                                   SCRATCHPAD_NO_PVT_CACHE);

    // Large data (multiple containers for single datum)
    MEMORY_IFC#(t_ADDR, t_DATA) memory <- mkScratchpad(scratchpadID, sconf);

    return memory;

endmodule

