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

module [CONNECTED_MODULE] mkMemTesterAlt ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));



    //
    // Allocate scratchpads
    //

    let private_caches = (`MEM_TEST_PRIVATE_CACHES_ALT != 0 ? SCRATCHPAD_CACHED :
                                                          SCRATCHPAD_NO_PVT_CACHE);

    // Large data (multiple containers for single datum)
    MEMORY_IFC#(MEM_ADDRESS, MEM_ADDRESS) memory <- mkScratchpad(`VDEV_SCRATCH_MEMTESTALT, private_caches);

    // Output
    STDIO#(Bit#(64))     stdio <- mkStdIO();

    // Statistics Collection State
    Reg#(CYCLE_COUNTER)  cycle <- mkReg(0);
    Reg#(CYCLE_COUNTER)  startCycle <- mkReg(0);
    Reg#(CYCLE_COUNTER)  endCycle <- mkReg(0);
    Reg#(Bit#(64))       totalLatency <- mkReg(0);
    FIFO#(CYCLE_COUNTER) operationStartCycle <- mkSizedBRAMFIFO(128);
    FIFO#(Bool)          operationIsLast     <- mkSizedBRAMFIFO(128);
    Reg#(STATE)          state <- mkReg(STATE_init);

    // Address Calculation State
    Reg#(MEM_ADDRESS) addr   <- mkReg(0);
    MEM_ADDRESS       stride[valueof(STRIDE_INDEXES)] = {1,2,3,4,5,6,7,8,16,32,64,128};
    Reg#(Bit#(18))    count <- mkReg(0);  
    Reg#(MEM_ADDRESS) strideIdx <- mkReg(1);
    Reg#(MEM_ADDRESS) bound  <- mkReg(boundMin);
    Reg#(MEM_ADDRESS) boundMask  <- mkReg(boundMaskBase);


    // Messages
    let perfMsg <- getGlobalStringUID("size:%llu:stride:%llu:latency:%llu:time:%llu\n");
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doInit (False);
        
        state <= STATE_writing;
        startCycle <= cycle;
        totalLatency <= 0;
        strideIdx <= 0;
        bound <= boundMin;
        boundMask <= boundMaskBase;
        count <= 0;
    endrule


    rule doWrite(state == STATE_writing);
        memory.write(addr,addr);
        addr <= (addr + stride[strideIdx]) & boundMask;
        count <= count + 1;
        if(count + 1 == 0)
        begin
            state <= STATE_write_reset;
            endCycle <= cycle;
        end
    endrule

    rule doWriteReset(state == STATE_write_reset);
        addr <= 0;
        startCycle <= cycle;
        stdio.printf(perfMsg, list4(zeroExtend(bound), zeroExtend(stride[strideIdx]), 0, zeroExtend(endCycle - startCycle)));
        if(bound << 1 == boundMax)
        begin
            bound <= boundMin;
            strideIdx <= 0;
            boundMask <= boundMaskBase;
            state <= STATE_reading;
        end
        else
        begin
            state <= STATE_writing;
            if(strideIdx == strideMax)
            begin
                strideIdx <= 0;         
                bound <= bound << 1;
                boundMask <= truncate({boundMask,1'b1});
            end
            else
            begin
                strideIdx <= strideIdx + 1;
            end
        end
    endrule

    Reg#(Bool) reqsDone <- mkReg(False);

    rule readReq (state == STATE_reading && !reqsDone);
        memory.readReq(addr);
        addr <= (addr + stride[strideIdx]) & boundMask;
        operationStartCycle.enq(cycle);
        count <= count + 1;
        if(count + 1 == 0)
        begin
            reqsDone <= True;
        end 

        operationIsLast.enq(count + 1 == 0);
    endrule

    rule readResp;
        let resp <- memory.readRsp();
        operationIsLast.deq;
        operationStartCycle.deq;
        totalLatency <= totalLatency + zeroExtend(cycle - operationStartCycle.first);
        if(operationIsLast.first)
        begin
            state <= STATE_read_reset;
            endCycle <= cycle;
        end
    endrule

    rule doReadReset(state == STATE_read_reset);
        addr <= 0;
        reqsDone <= False;
        startCycle <= cycle;
        totalLatency <= 0;
        stdio.printf(perfMsg, list4(zeroExtend(bound), zeroExtend(stride[strideIdx]), zeroExtend(totalLatency), zeroExtend(endCycle - startCycle)));
        if(bound << 1 == boundMax)
        begin
            bound <= 1;
            strideIdx <= 0;
            state <= STATE_finished;
        end
        else
        begin
            state <= STATE_reading;
            if(strideIdx == strideMax)
            begin
                strideIdx <= 0;         
                bound <= bound << 1;
                boundMask <= truncate({boundMask,1'b1});
            end
            else
            begin
                strideIdx <= strideIdx + 1;
            end
        end
    endrule

    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        state <= STATE_sync;
    endrule

    rule sync (state == STATE_sync);
        stdio.sync_req();
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        let r <- stdio.sync_rsp();
    endrule

endmodule
