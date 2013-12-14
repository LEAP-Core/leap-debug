//
// Copyright (C) 2013 Intel Corporation
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
import FIFOF::*;
import Vector::*;
import GetPut::*;
import LFSR::*;
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "awb/provides/coherent_scratchpad_performance_common.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_COHERENT_SCRATCHPAD_PERFORMANCE_COMMON.bsh"

module [CONNECTED_MODULE] mkCoherentScratchpadRemote ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Alias#(Bit#(TSub#(t_SCRATCHPAD_MEM_VALUE_SZ, 1)), t_MEM_DATA),
              //Alias#(MEM_DATA_SM, t_MEM_DATA),
              Bits#(t_MEM_DATA, t_MEM_DATA_SZ),
              NumAlias#(TLog#(`N_SCRATCH), t_SCRATCH_IDX_SZ),
              Alias#(Bit#(t_SCRATCH_IDX_SZ), t_SCRATCH_IDX),
              NumAlias#(TAdd#(t_SCRATCH_IDX_SZ, t_MEM_ADDR_SZ), t_COH_SCRATCH_ADDR_SZ),
              Alias#(Bit#(t_COH_SCRATCH_ADDR_SZ), t_COH_SCRATCH_ADDR));

    // Coherent scratchpads
    COH_SCRATCH_CONFIG conf = defaultValue;
    conf.cacheMode = (`COH_SCRATCH_MEM_PERF_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
    
    NumTypeParam#(t_COH_SCRATCH_ADDR_SZ) addr_size = ?;
    NumTypeParam#(t_MEM_DATA_SZ) data_size = ?;

    DEBUG_FILE debugLogsCohScratch <- mkDebugFile("coherent_scratchpad_"+integerToString(`N_SCRATCH) +".out");
    MEMORY_WITH_FENCE_IFC#(t_COH_SCRATCH_ADDR, t_MEM_DATA) memoriesCohScratch <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_COH_MEMPERF_DATA, `N_SCRATCH, conf, debugLogsCohScratch);


    Reg#(t_COH_SCRATCH_ADDR) addr <- mkReg(0);
    Reg#(Bit#(10)) count <- mkReg(0);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();
    let msgCohRReq      <- getGlobalStringUID("cohMemRemote Read Req %x! \n");
    let msgCohRResp     <- getGlobalStringUID("cohMemRemote Read Resp %x! \n");
    let msgCohW         <- getGlobalStringUID("cohMemRemote Write %x %x! \n");
   

    rule doOp(count < 10);
       if(count[0] == 1)
       begin
           memoriesCohScratch.readReq(zeroExtend(count>>1));
           stdio.printf(msgCohRReq,list1(zeroExtend(count>>1)));
       end
       else
       begin
           memoriesCohScratch.write(zeroExtend(count>>1),zeroExtend(count>>1));	
           stdio.printf(msgCohW,list2(zeroExtend(count>>1),zeroExtend(count>>1)));
       end
       count <= count + 1;

    endrule

    rule drain;
       let data <- memoriesCohScratch.readRsp();
       stdio.printf(msgCohRResp,list1(zeroExtend(data)));
    endrule

endmodule
