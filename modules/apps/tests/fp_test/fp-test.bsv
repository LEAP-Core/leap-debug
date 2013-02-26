//
// Copyright (C) 2008 Intel Corporation
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

//
// This module isn't meant to be especially pretty.  It is a simple test harness
// for testing arithmetic operations.  The test reads in a series of 64 bit
// number pairs and passes them to a calculate rule.
//
//                            * * * * * * * * * * *
// There are benchmarks under hasim/demos/test that provide data inputs for
// this test harness.
//                            * * * * * * * * * * *
//

import Vector::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/stdio_service.bsh"

`include "awb/dict/PARAMS_HARDWARE_SYSTEM.bsh"

typedef enum
{
    STATE_START,
    STATE_RUNNING,
    STATE_END_SYNC_REQ,
    STATE_END_SYNC_RSP
}
STATE
    deriving (Eq, Bits);


module [CONNECTED_MODULE] mkSystem ();

    STDIO#(Bit#(64)) stdio <- mkStdIO();
    let msg <- getGlobalStringUID("0x%016llx  0x%016llx\n");

    // Dynamic parameters to feed to datapath.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();
    Param#(64) paramOp1 <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_OP1, paramNode);
    Param#(64) paramOp2 <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_OP2, paramNode);

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    // Datapath instantiation based on AWB parameter.
    FP_ACCEL dp <- `DATAPATH();
    
    // Only send the answer once.
    Reg#(Bool) done <- mkReg(False);

    Reg#(STATE) state <- mkReg(STATE_START);

    rule start (state == STATE_START);
        linkStarterStartRun.deq();
        state <= STATE_RUNNING;
    endrule

    // Rule to read the dynamic parameters and send them to the datapath.
    rule dpReq ((state == STATE_RUNNING) && !done);
        FP_INPUT inp;
        inp.operandA = paramOp1;
        inp.operandB = paramOp2;

        dp.makeReq(inp);
        done <= True;
    endrule

    // Rule to read the results and report them via streams.
    rule dpRsp (state == STATE_RUNNING);
        let outp <- dp.getRsp();
        Bit#(64) res = outp.result;

        stdio.printf(msg, list(res, fpSingleInDouble(truncate(res))));
        state <= STATE_END_SYNC_REQ;
    endrule

    rule sync (state == STATE_END_SYNC_REQ);
        stdio.sync_req();
        state <= STATE_END_SYNC_RSP;
    endrule

    rule exit (state == STATE_END_SYNC_RSP);
        stdio.sync_rsp();
        linkStarterFinishRun.send(0);
    endrule

endmodule
