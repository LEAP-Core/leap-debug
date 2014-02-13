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


typedef Bit#(32) CYCLE_COUNTER;
typedef Bit#(`MEM_ADDR) MEM_ADDRESS;
typedef Bit#(`MEM_WIDTH) MEM_DATA;
typedef 26 MAX_WORKING_SET;
typedef 9 MIN_WORKING_SET;
typedef 12 STRIDE_INDEXES;

MEM_ADDRESS boundMin      =  1 << fromInteger(valueof(MIN_WORKING_SET));

typedef struct {
    Bit#(32) workingSet;
    Bit#(32) stride;
    Bit#(32) iterations;
    Bit#(8)  command;
} CommandType deriving (Bits,Eq);


module [CONNECTED_MODULE] mkMemTesterRing#(Integer scratchpadID, Bool addCaches) (Empty)
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));


    //
    // Allocate scratchpads
    //

    MEMORY_IFC#(MEM_ADDRESS, MEM_DATA) memory <- mkTestMemory(scratchpadID, addCaches);

    // Output
    STDIO#(Bit#(64))     stdio <- mkStdIO();

    // Statistics Collection State
    Reg#(CYCLE_COUNTER)  cycle <- mkReg(0);
    Reg#(CYCLE_COUNTER)  startCycle <- mkReg(0);
    Reg#(CYCLE_COUNTER)  endCycle <- mkReg(0);
    Reg#(Bit#(64))       totalLatency <- mkReg(0);

    // Used to skew access addresses.  Useful for create the illusion of private
    // address spaces in coherent memory tests. 
    MEM_ADDRESS privSpace = fromInteger(scratchpadID) << `MEM_TEST_SHIFT;

    CONNECTION_CHAIN#(CommandType) commandChain <- mkConnectionChain("command");
    CONNECTION_ADDR_RING#(Bit#(8), Bit#(1))     finishChain  <- mkConnectionAddrRingDynNode("finish");


    FIFO#(CYCLE_COUNTER) operationStartCycle <- mkSizedFIFO(256);
    FIFO#(Bool)          operationIsLast     <- mkSizedFIFO(256);
    Reg#(Bool)           reqsDone <- mkReg(False);
    Reg#(STATE)          state <- mkReg(STATE_get_command);
    // Address Calculation State
    Reg#(MEM_ADDRESS) addr   <- mkReg(0);

    Reg#(Bit#(32)) count <- mkRegU();
    Reg#(Bit#(32)) iterations <- mkRegU();
    Reg#(Bit#(32)) errors <- mkRegU();

    FIFO#(MEM_DATA) expected <- mkSizedBRAMFIFO(256);
    Reg#(MEM_ADDRESS) stride <- mkRegU();
    Reg#(MEM_ADDRESS) bound  <- mkRegU();

    // Debugging
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "state", state);
    dbg_list <- addDebugScanField(dbg_list, "count", count);
    dbg_list <- addDebugScanField(dbg_list, "iterations", iterations);
    dbg_list <- addDebugScanField(dbg_list, "errors", errors);
    dbg_list <- addDebugScanField(dbg_list, "addr", addr);
    dbg_list <- addDebugScanField(dbg_list, "stride", stride);
    dbg_list <- addDebugScanField(dbg_list, "bound", bound);

    let dbgNode <- mkDebugScanNode("Memory performance (mem-perf-common.bsv)", dbg_list);


    // Simple mixing function to swizzle write values a little bit
    function MEM_DATA addrMix(MEM_ADDRESS a) = zeroExtend(a + (a << 3));

    // Messages
    let perfMsg <- getGlobalStringUID("Tester%d:size:%llu:stride:%llu:latency:%llu:time:%llu:errors:%llu\n");
    let errMsg <-  getGlobalStringUID("Tester%d:expected:%llu:got:%llu:Alt\n");	    
    
    DEBUG_FILE debugLog <- mkDebugFile("mem_tester_"+integerToString(scratchpadID)+".out");

    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doGetCommand (state == STATE_get_command);
        let cmd <- commandChain.recvFromPrev();
        commandChain.sendToNext(cmd);
	
        addr <= privSpace;
        bound <= truncate(cmd.workingSet);
        stride <= truncate(cmd.stride);
        iterations <= cmd.iterations;

        case (pack(cmd.command)[1:0])
            0: state <= STATE_writing;
            1: state <= STATE_reading;
            2: state <= STATE_finished;
        endcase
            
        debugLog.record($format("goGetCommand: command: %s", 
                        (pack(cmd.command)[1:0] == 0)? "write": ((pack(cmd.command)[1:0] == 1)? "read" : "finish") ));

        if (pack(cmd.command)[1:0] != 2)
        begin
            debugLog.record($format("goGetCommand: workingSet = 0x%x, stride = 0x%x, iterations = 0x%x",
                            cmd.workingSet, cmd.stride, cmd.iterations)); 
        end

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
            
        debugLog.record($format("doWrite: addr = 0x%x, val = 0x%X", addr, addrMix(addr)));

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
        
        debugLog.record($format("readReq: addr = 0x%x", addr));
        
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

        if (resp != expected.first && `MEM_TEST_VERBOSE != 0)
        begin
            stdio.printf(errMsg, list3(fromInteger(scratchpadID),
                                       zeroExtend(pack(resp)), 
                                       zeroExtend(pack(expected.first))));
            errors <= errors + 1;
        end
            
        debugLog.record($format("readResp: %s val = 0x%x, expected = 0x%x", 
                        (resp != expected.first())? "ERROR!" : "", resp, expected.first()));

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
