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

// ========================================================================
//
// Shared queue test common definitions. 
//
// ========================================================================

`define TEST_NUM 1024
`define HEAD_ADDR   0
`define TAIL_ADDR   4

`define PRODUCER_DONE_ADDR   8
`define CONSUMER_DONE_ADDR  12
`define HEAD_LOCK_ADDR 16
`define TAIL_LOCK_ADDR 20
`define PRODUCER_DONE_LOCK_ADDR 24
`define CONSUMER_DONE_LOCK_ADDR 28
`define INIT_DONE_ADDR 32
`define INIT_CLIENT_DONE_ADDR 36

`define START_ADDR  40

typedef Bit#(32) CYCLE_COUNTER;
typedef Bit#(16) MEM_ADDRESS;
typedef Bit#(9) WORKING_SET;

typedef Bit#(4) PRODUCER_IDX;
typedef Bit#(4) CONSUMER_IDX;
typedef  4 N_PRODUCERS;
typedef  4 N_CONSUMERS;
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
    Bit#(25)     data;
}
TEST_DATA
    deriving (Bits, Eq);


