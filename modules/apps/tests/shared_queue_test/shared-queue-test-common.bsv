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

// ========================================================================
//
// Shared queue test common definitions. 
//
// ========================================================================

`define TEST_NUM 1024
`define HEAD_ADDR   0
`define TAIL_ADDR   4
`define START_ADDR  8

typedef Bit#(32) CYCLE_COUNTER;
typedef Bit#(16) MEM_ADDRESS;
typedef Bit#(9) WORKING_SET;

typedef Bit#(4) PRODUCER_IDX;
typedef Bit#(4) CONSUMER_IDX;
typedef  2 N_PRODUCERS;
typedef  2 N_CONSUMERS;
typedef 15 SHARED_QUEUE_SIZE_LOG;

typedef enum
{
    STATE_init,
    STATE_test,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);

typedef struct
{
    PRODUCER_IDX idx;
    Bit#(40)     data;
}
TEST_DATA
    deriving (Bits, Eq);


