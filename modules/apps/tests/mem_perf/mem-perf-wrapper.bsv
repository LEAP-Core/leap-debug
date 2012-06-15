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


import FIFO::*;
import Vector::*;
import GetPut::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/mem_perf_tester.bsh"


`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"

`define START_ADDR 0

typedef enum
{
    STATE_init,
    STATE_writing,
    STATE_write_reset,
    STATE_reading,
    STATE_read_reset,
    STATE_finished,
    STATE_sync,
    STATE_exit
}
STATE
    deriving (Bits, Eq);


typedef Bit#(32) CYCLE_COUNTER;

typedef Bit#(32) MEM_ADDRESS;
typedef 26 MAX_WORKING_SET;
typedef 9 MIN_WORKING_SET;
typedef 12 STRIDE_INDEXES;

MEM_ADDRESS boundMaskBase = (1 << fromInteger(valueof(MIN_WORKING_SET))) - 1;
MEM_ADDRESS boundMin      =  1 << fromInteger(valueof(MIN_WORKING_SET));
MEM_ADDRESS boundMax      =  1 << fromInteger(valueof(MAX_WORKING_SET));
MEM_ADDRESS strideMax     = fromInteger(valueof(STRIDE_INDEXES));

module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));

    let mem_tester <- mkMemTester();

endmodule
