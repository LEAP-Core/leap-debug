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

`include "asim/provides/fpga_components.bsh"

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/scratchpad_memory_service.bsh"
`include "asim/provides/scratchpad_memory.bsh"

`define LAST_ADDR 'h2000

typedef enum
{
    STATE_ready,
    STATE_awaitingResponse,
    STATE_finished,
    STATE_calc_start,
    STATE_calc_end,
    STATE_calc_end1
}
STATE
    deriving (Bits, Eq);


module [CONNECTED_MODULE] mkSystem ();

    Connection_Client#(SCRATCHPAD_MEM_REQUEST, SCRATCHPAD_MEM_VALUE) link_memory <- mkConnection_Client("vdev_memory");
    Connection_Receive#(SCRATCHPAD_MEM_ADDRESS) link_memory_inval <- mkConnection_Receive("vdev_memory_invalidate");

    Reg#(Bit#(32)) cooldown <- mkReg(1000);
    Reg#(SCRATCHPAD_MEM_ADDRESS) addr <- mkReg('h1000);
    Reg#(STATE) state <- mkReg(STATE_ready);
    Reg#(Bit#(2)) pos <- mkReg(0);

    Reg#(Bit#(64)) arg0 <- mkReg(0);
    Reg#(Bit#(64)) arg1 <- mkReg(0);

    STDIO#(Bit#(64)) stdio <- mkStdIO();
    let strNum64 <- getGlobalStringUID("0x%08x ");
    let strResult128 <- getGlobalStringUID("0x%016x 0x%016x\n");
    let strDone <- getGlobalStringUID("alu-test: done\n");


    // ====================================================================
    //
    // Calculate function.  Test harness sets two 64 bit arguments (arg0
    // and arg1) and sets the state to STATE_calc_start.  Once done the
    // calculator should set the state to STATE_ready.
    //
    // ====================================================================

    HASIM_COMPACT_MUL#(64) uMul <- mkCompactUnsignedMul();

    rule calc_start(state == STATE_calc_start);
        
        uMul.req(truncate(arg0), truncate(arg1));
        state <= STATE_calc_end;

    endrule

    rule calc_end(state == STATE_calc_end);
        
        let c <- uMul.resp();

        stdio.printf(strNum128, list2(c[127:64], c[63:0]));
        state <= STATE_ready;

    endrule


    // ====================================================================
    //
    // Below this point is just mechanics of reading in numbers,
    // terminating, etc.
    //
    // ====================================================================

    rule send_load_req(state == STATE_ready && addr != `LAST_ADDR);

        link_memory.makeReq(tagged SCRATCHPAD_MEM_READ addr);
        state <= STATE_awaitingResponse;

    endrule

    //
    // recv_load_resp --
    //     Group a set of 4 32 bit responses into a pair of 64 bit values
    //     that will be handed to the calc function.
    //
    rule recv_load_resp(state == STATE_awaitingResponse);

        SCRATCHPAD_MEM_VALUE v = link_memory.getResp();
        link_memory.deq();

        case (pos)
            0:
            begin
                arg0[31:0] <= v;
            end
            
            1:
            begin
                arg0[63:32] <= v;
                stdio.printf(strNum64, list1({v, arg0[31:0]}));
            end
            
            2:
            begin
                arg1[31:0] <= v;
            end
            
            3:
            begin
                arg1[63:32] <= v;
                stdio.printf(strNum64, list1({v, arg1[31:0]}));
            end
        endcase

        if (pos == 3)
            state <= STATE_calc_start;
        else
            state <= STATE_ready;

        pos   <= pos + 1;
        addr  <= addr + 4;

    endrule

    rule terminate (state == STATE_ready && addr == `LAST_ADDR);

        state <= STATE_finished;

    endrule

    rule finishup (state == STATE_finished && cooldown != 0);

        stdio.printf(strDone, List::nil);
        cooldown <= cooldown - 1;

    endrule

    rule accept_invalidates(True);

        SCRATCHPAD_MEM_ADDRESS addr = link_memory_inval.receive();
        link_memory_inval.deq();

    endrule

endmodule
