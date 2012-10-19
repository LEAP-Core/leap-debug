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

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/rrr/remote_server_stub_MEMPERFRRR.bsh"
`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "awb/provides/mem_perf_tester.bsh"
`include "awb/provides/mem_perf_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"

`define START_ADDR 0

typedef enum
{
    STATE_get_command,
    STATE_test_done,
    STATE_writing,
    STATE_reading,
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

MEM_ADDRESS boundMin      =  1 << fromInteger(valueof(MIN_WORKING_SET));

module [CONNECTED_MODULE] mkMemTesterAlt ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));

    messageM("Compiling mkMemTester");

    //
    // Allocate scratchpads
    //
    let private_caches = (`MEM_TEST_PRIVATE_CACHES != 0 ? SCRATCHPAD_CACHED :
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
    CONNECTION_RECV#(CommandType) cmdIn <- mkConnectionRecv("altCmd");
    CONNECTION_SEND#(Bit#(1)) finishOut <- mkConnectionSend("altFinish");
    CONNECTION_SEND#(CYCLE_COUNTER) operationStartCycleSend <- mkConnectionSend("cycleFIFOAlt");
    CONNECTION_RECV#(CYCLE_COUNTER) operationStartCycleReceive <- mkConnectionRecv("cycleFIFOAlt");
    FIFO#(Bool)          operationIsLast     <- mkSizedFIFO(128);
    Reg#(Bool)           reqsDone <- mkReg(False);
    Reg#(STATE)          state <- mkReg(STATE_get_command);
    // Address Calculation State
    Reg#(MEM_ADDRESS) addr   <- mkReg(0);

    Reg#(Bit#(32)) count <- mkRegU();
    Reg#(Bit#(32)) iterations <- mkRegU();
    Reg#(Bit#(32)) errors <- mkRegU();

    FIFO#(MEM_ADDRESS) expected <- mkSizedBRAMFIFO(128);
    Reg#(MEM_ADDRESS) stride <- mkRegU();
    Reg#(MEM_ADDRESS) bound  <- mkRegU();

    // Simple mixing function to swizzle write values a little bit
    function MEM_ADDRESS addrMix(MEM_ADDRESS a) = a + (a << 3);

    // Messages
    let perfMsg <- getGlobalStringUID("size:%llu:stride:%llu:latency:%llu:time:%llu:Alt:%llu\n");
    let errMsg <-  getGlobalStringUID("expected:%llu:got:%llu:Alt\n");
    
    (* fire_when_enabled *)
    rule cycleCount (True);
        cycle <= cycle + 1;
    endrule

    rule doGetCommand (state == STATE_get_command);
        let cmd = cmdIn.receive;
	cmdIn.deq;    

        addr <= 0;
        bound <= zeroExtend(pack(cmd.workingSet));
        stride <= zeroExtend(pack(cmd.stride));
        iterations <= pack(cmd.iterations);

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
        stdio.printf(perfMsg, list5(zeroExtend(bound), zeroExtend(stride), 0, zeroExtend(endCycle - startCycle), zeroExtend(errors)));
        
        state <= STATE_get_command;
	finishOut.send(?);
    endrule

    rule doWrite(state == STATE_writing);
        memory.write(addr, addrMix(addr));

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

        operationStartCycleSend.send(cycle);
        count <= count + 1;
        Bool is_last = (count + 1 == iterations);
        if(is_last)
        begin
            reqsDone <= True;
        end 
        expected.enq(addrMix(addr));
        operationIsLast.enq(is_last);
    endrule

    rule readResp;
        let resp <- memory.readRsp();

        if (resp != expected.first)
        begin
            stdio.printf(errMsg, list2(zeroExtend(resp), zeroExtend(expected.first)));
            errors <= errors + 1;
        end

        expected.deq();
        operationIsLast.deq;
        operationStartCycleReceive.deq;
        totalLatency <= totalLatency + zeroExtend(cycle - operationStartCycleReceive.receive);

        if(operationIsLast.first)
        begin
            state <= STATE_test_done;
            endCycle <= cycle;
        end
    endrule


    // ====================================================================
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
