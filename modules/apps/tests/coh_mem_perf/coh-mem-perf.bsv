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
import FIFOF::*;
import Vector::*;
import GetPut::*;
import LFSR::*;
import DefaultValue::*;

`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh" 
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/mem_services.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/coherent_scratchpad_performance_common.bsh"
`include "awb/provides/coherent_scratchpad_performance_test.bsh"
`include "awb/provides/coherent_scratchpad_performance_remote.bsh"
`include "awb/provides/coherent_scratchpad_memory_service.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_COHERENT_SCRATCHPAD_PERFORMANCE_COMMON.bsh"

// It is normally NOT necessary to include scratchpad_memory.bsh to use
// scratchpads.  mem-test includes it only to get the value of
// SCRATCHPAD_MEM_VALUE in order to pick data sizes that will force
// the three possible container scenarios:  multiple containers per
// datum, one container per datum, multiple data per container.
`include "awb/provides/scratchpad_memory.bsh"

`define TEST_NUM   512

typedef Bit#(32) MEM_DATA_SM;
typedef Bit#(14) MEM_ADDRESS;
typedef Bit#(14) WORKING_SET;
typedef Bit#(32) CYCLE_COUNTER;


module [CONNECTED_MODULE] mkSystem ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Alias#(Bit#(TSub#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA),
              //Alias#(MEM_DATA_SM, t_MEM_DATA),
              Bits#(t_MEM_DATA, t_MEM_DATA_SZ),
              NumAlias#(TLog#(`N_SCRATCH), t_SCRATCH_IDX_SZ),
              Alias#(Bit#(t_SCRATCH_IDX_SZ), t_SCRATCH_IDX),
              NumAlias#(TAdd#(t_SCRATCH_IDX_SZ, t_MEM_ADDR_SZ), t_COH_SCRATCH_ADDR_SZ),
              Alias#(Bit#(t_COH_SCRATCH_ADDR_SZ), t_COH_SCRATCH_ADDR));

    //
    // Allocate scratchpads
    //
    COH_SCRATCH_CONFIG conf = defaultValue;
    conf.cacheMode = (`COH_SCRATCH_MEM_PERF_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;

    // Coherent scratchpads
    NumTypeParam#(t_COH_SCRATCH_ADDR_SZ) addr_size = ~0;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ~0;

    mkCoherentScratchpadController(`VDEV_SCRATCH_COH_MEMPERF_DATA, `VDEV_SCRATCH_COH_MEMPERF_BITS, addr_size, data_size, conf);

    mkCoherentScratchpadTest();
    mkCoherentScratchpadRemote();

endmodule
