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
import FIFOLevel::*;
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
`include "awb/dict/PARAMS_MEM_PERF_COMMON.bsh"
`include "awb/dict/VDEV_SCRATCH.bsh"

`define START_ADDR 0

typedef enum
{
    STATE_get_command,
    STATE_test_done0,
    STATE_test_done1,
    STATE_test_done2,
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

    FIFOCountIfc#(CYCLE_COUNTER,256) operationStartCycle <- mkFIFOCount();
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

    // Dynamic Parameter
    // Dynamic parameters
    PARAMETER_NODE paramNode         <- mkDynamicParameterNode();
    Param#(9) maxOutstanding         <- mkDynamicParameter(`PARAMS_MEM_PERF_COMMON_MEM_TEST_OUTSTANDING_REQUESTS, paramNode);

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

    rule doTestDone0 (state == STATE_test_done0);
        stdio.printf(perfMsg, list6(fromInteger(scratchpadID),
                                    zeroExtend(pack(bound)), 
                                    zeroExtend(pack(stride)), 
                                    totalLatency, 
                                    zeroExtend(pack(endCycle - startCycle)), 
                                    zeroExtend(pack(errors))));
        state <= STATE_test_done1;
    endrule

    rule doTestDone1 (state == STATE_test_done1);
        stdio.sync_req(False);
        state <= STATE_test_done2;
    endrule

    rule doTestDone2 (state == STATE_test_done2);
        stdio.sync_rsp();
        finishChain.enq(0, ?);
        state <= STATE_get_command;
    endrule

    rule doWrite(state == STATE_writing);
        memory.write(addr, zeroExtend(addrMix(addr)));
            
        debugLog.record($format("doWrite (%d): addr = 0x%x, val = 0x%X", cycle, addr, addrMix(addr)));

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
            state <= STATE_test_done0;
            endCycle <= cycle;
        end
    endrule

    rule readReq (state == STATE_reading && !reqsDone && (operationStartCycle.count() < unpack(maxOutstanding)));
        memory.readReq(addr);
        
        debugLog.record($format("readReq (%d): addr = 0x%x", cycle, addr));
        
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
                                       resize(pack(resp)), 
                                       resize(pack(expected.first))));
            errors <= errors + 1;
        end
            
        debugLog.record($format("readResp(%d, latency %d): %s val = 0x%x, expected = 0x%x", cycle, 
                         cycle - operationStartCycle.first, (resp != expected.first())? "ERROR!" : "", resp, expected.first()));

        expected.deq();
        operationIsLast.deq;
        operationStartCycle.deq;
        totalLatency <= totalLatency + zeroExtend(cycle - operationStartCycle.first);

        if(operationIsLast.first)
        begin
            state <= STATE_test_done0;
            endCycle <= cycle;
        end
    endrule


endmodule
