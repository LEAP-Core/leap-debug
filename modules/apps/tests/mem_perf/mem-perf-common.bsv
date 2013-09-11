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
`include "awb/rrr/remote_server_stub_MEMPERFRRR.bsh"
`include "awb/provides/mem_services.bsh"
`include "awb/provides/mem_perf_common.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/dict/VDEV_SCRATCH.bsh"

`define START_ADDR 0

typedef enum
{
    STATE_get_command,
    STATE_test_done,
    STATE_writing,
    STATE_reading,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);


typedef UInt#(32) CYCLE_COUNTER;

typedef UInt#(28) MEM_ADDRESS;
typedef UInt#(64) MEM_DATA;
typedef 26 MAX_WORKING_SET;
typedef 9 MIN_WORKING_SET;
typedef 12 STRIDE_INDEXES;

MEM_ADDRESS boundMin      =  1 << fromInteger(valueof(MIN_WORKING_SET));

typedef struct {
    UInt#(32) workingSet;
    UInt#(32) stride;
    UInt#(32) iterations;
    UInt#(8)  command;
} CommandType deriving (Bits,Eq);


module [CONNECTED_MODULE] mkMemTesterRing#(Integer scratchpadID, Bool addCaches) (Empty)
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));


    //
    // Allocate scratchpads
    //

    SCRATCHPAD_CONFIG sconf = defaultValue;
    sconf.cacheMode = (addCaches ? SCRATCHPAD_CACHED :
                                   SCRATCHPAD_NO_PVT_CACHE);

    // Large data (multiple containers for single datum)
    MEMORY_IFC#(MEM_ADDRESS, MEM_DATA) memory <- mkScratchpad(scratchpadID, sconf);

    // Output
    STDIO#(Bit#(64))     stdio <- mkStdIO();

    // Statistics Collection State
    Reg#(CYCLE_COUNTER)  cycle <- mkReg(0);
    Reg#(CYCLE_COUNTER)  startCycle <- mkReg(0);
    Reg#(CYCLE_COUNTER)  endCycle <- mkReg(0);
    Reg#(UInt#(64))       totalLatency <- mkReg(0);

    CONNECTION_CHAIN#(CommandType) commandChain <- mkConnectionChain("command");
    CONNECTION_ADDR_RING#(Bit#(8), Bit#(1))     finishChain  <- mkConnectionAddrRingDynNode("finish");


    FIFO#(CYCLE_COUNTER) operationStartCycle <- mkSizedFIFO(256);
    FIFO#(Bool)          operationIsLast     <- mkSizedFIFO(256);
    Reg#(Bool)           reqsDone <- mkReg(False);
    Reg#(STATE)          state <- mkReg(STATE_get_command);
    // Address Calculation State
    Reg#(MEM_ADDRESS) addr   <- mkReg(0);

    Reg#(UInt#(32)) count <- mkRegU();
    Reg#(UInt#(32)) iterations <- mkRegU();
    Reg#(UInt#(32)) errors <- mkRegU();

    FIFO#(MEM_DATA) expected <- mkSizedBRAMFIFO(256);
    Reg#(MEM_ADDRESS) stride <- mkRegU();
    Reg#(MEM_ADDRESS) bound  <- mkRegU();

    // Simple mixing function to swizzle write values a little bit
    function MEM_DATA addrMix(MEM_ADDRESS a) = zeroExtend(a + (a << 3));

    // Messages
    let perfMsg <- getGlobalStringUID("Tester%d:size:%llu:stride:%llu:latency:%llu:time:%llu:errors:%llu\n");
    let errMsg <-  getGlobalStringUID("Tester%d:expected:%llu:got:%llu:Alt\n");	    

    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doGetCommand (state == STATE_get_command);
        let cmd <- commandChain.recvFromPrev();
        commandChain.sendToNext(cmd);

        addr <= 0;
        bound <= truncate(cmd.workingSet);
        stride <= truncate(cmd.stride);
        iterations <= cmd.iterations;

        case (pack(cmd.command)[1:0])
            0: state <= STATE_writing;
            1: state <= STATE_reading;
            2: state <= STATE_finished;
        endcase

        errors <= 0;
        count <= 0;
        totalLatency <= 0;
        startCycle <= cycle;
        reqsDone <= False;
    endrule

    rule doTestDone (state == STATE_test_done);
        stdio.printf(perfMsg, list6(fromInteger(scratchpadID),
                                    zeroExtend(pack(bound)), 
                                    zeroExtend(pack(stride)), 
                                    0, 
                                    zeroExtend(pack(endCycle - startCycle)), 
                                    zeroExtend(pack(errors))));
        finishChain.enq(0,?);
        state <= STATE_get_command;
    endrule

    rule doWrite(state == STATE_writing);
        memory.write(addr, zeroExtend(addrMix(addr)));

        if(addr + stride < bound * stride)
        begin
            addr <= (addr + stride);
        end
        else 
        begin
            addr <= 0; 
        end 

        count <= count + 1;
        if(count + 1 == iterations)
        begin
            state <= STATE_test_done;
            endCycle <= cycle;
        end
    endrule

    rule readReq (state == STATE_reading && !reqsDone);
        memory.readReq(addr);
        if(addr + stride < bound * stride)
        begin
            addr <= (addr + stride);
        end
        else 
        begin
            addr <= 0; 
        end 

        operationStartCycle.enq(cycle);
        count <= count + 1;
        Bool is_last = (count + 1 == iterations);
        if(is_last)
        begin
            reqsDone <= True;
        end 
        expected.enq(zeroExtend(addrMix(addr)));
        operationIsLast.enq(is_last);
    endrule

    rule readResp (state == STATE_reading);
        let resp <- memory.readRsp();

        if (resp != expected.first)
        begin
            stdio.printf(errMsg, list3(fromInteger(scratchpadID),
                                       zeroExtend(pack(resp)), 
                                       zeroExtend(pack(expected.first))));
            errors <= errors + 1;
        end

        expected.deq();
        operationIsLast.deq;
        operationStartCycle.deq;
        totalLatency <= totalLatency + zeroExtend(cycle - operationStartCycle.first);

        if(operationIsLast.first)
        begin
            state <= STATE_test_done;
            endCycle <= cycle;
        end
    endrule


endmodule
