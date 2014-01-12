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
`include "awb/provides/mem_perf_common.bsh"
`include "awb/rrr/remote_server_stub_MEMPERFRRR.bsh"
`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"



module [CONNECTED_MODULE] mkMemPerfDriver ()
    provisos (Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ));

    // Output
    STDIO#(Bit#(64))     stdio <- mkStdIO();

    Reg#(Bit#(64))       cycles <- mkReg(0);

    ServerStub_MEMPERFRRR serverStub <- mkServerStub_MEMPERFRRR();

    CONNECTION_CHAIN#(CommandType) cmdOut <- mkConnectionChain("command");
    CONNECTION_ADDR_RING#(Bit#(8), Bit#(1)) finishIn <- mkConnectionAddrRingNode("finish",0);

    Reg#(Bit#(8)) operationsComplete <- mkReg(0);

    let startMsg <- getGlobalStringUID("Test Started %llu\n");
    let endMsg   <-  getGlobalStringUID("Test Ended %llu \n");	    

    rule tickCycles;
        cycles <= cycles + 1;
    endrule

    rule injectOperation;
        let cmd <- serverStub.acceptRequest_RunTest();

        cmdOut.sendToNext(CommandType{workingSet: unpack(cmd.workingSet),
                                      stride: unpack(cmd.stride),
                                      iterations: unpack(cmd.iterations),
                                      command: unpack(cmd.command)});
        stdio.printf(startMsg, list1(cycles));
    endrule

    rule drainOperation;
        let cmd <- cmdOut.recvFromPrev();
    endrule

    rule collectResponses;
        finishIn.deq;
        if(operationsComplete + 1 == finishIn.maxID)
        begin
            serverStub.sendResponse_RunTest(0, 0);
            operationsComplete <= 0;
            stdio.printf(endMsg, list1(cycles));
        end
        else 
        begin
            operationsComplete <= operationsComplete + 1;
        end
    endrule

endmodule
