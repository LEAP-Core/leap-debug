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

import Vector::*;
import FIFOF::*;
import GetPut::*;
import LFSR::*;

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/pipetest_common.bsh"
`include "asim/provides/pipeline_test.bsh"

typedef enum
{
    STATE_init,
    STATE_enq,
    STATE_deq,
    STATE_finished,
    STATE_done
}
STATE
    deriving (Bits, Eq);


module [CONNECTED_MODULE] mkSystem ();

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    Reg#(STATE) state <- mkReg(STATE_init);

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();
    let msgDone <- getGlobalStringUID("pipetest: done (0x%016llx)\n");

    // Instantiate the test pipelines
    PIPELINE_TEST#(`PIPE_TEST_STAGES, `PIPE_TEST_NUM_PIPES) pipes <- mkPipeTest();

    // Random number generator
    LFSR#(Bit#(32)) lfsr_0 <- mkLFSR_32();
    LFSR#(Bit#(32)) lfsr_1 <- mkLFSR_32();

    rule doInit (state == STATE_init);
        linkStarterStartRun.deq();
        lfsr_0.seed(1);
        lfsr_1.seed(2);
        state <= STATE_enq;
    endrule

    // ====================================================================
    //
    // Enqueue data to the pipes
    //
    // ====================================================================

    Reg#(PIPELINE_IDX) pipeIdx <- mkReg(0);
    Reg#(Bit#(1)) pipeTrips <- mkReg(0);

    rule doEnq (state == STATE_enq  && pipes.pipes[pipeIdx].notFull());
        // Pass random data so no optimizer can reduce pipeline sizes
        let v0 = lfsr_0.value();
        lfsr_0.next();
        let v1 = lfsr_1.value();
        lfsr_1.next();

        PIPE_TEST_DATA v;
        // Data driven routing.  Low bits of data indicate path.  Add two
        // numbers together so it isn't a constant.
        PIPELINE_IDX tgt = pipeIdx + zeroExtend(pipeTrips);
        v = truncate({v0, v1, tgt});

        pipes.pipes[pipeIdx].enq(v);
        
        // Enqueue to pipelines sequentially
        if (pipeIdx == maxBound)
        begin
            // Make multiple trips through the pipelines
            if (pipeTrips == maxBound)
            begin
                state <= STATE_deq;
            end

            pipeTrips <= pipeTrips + 1;
        end

        pipeIdx <= pipeIdx + 1;
    endrule


    // ====================================================================
    //
    // Dequeue data from the pipes
    //
    // ====================================================================

    Reg#(PIPE_TEST_DATA) outData <- mkReg(0);

    rule doDeq (state == STATE_deq && pipes.pipes[pipeIdx].notEmpty());
        let d = pipes.pipes[pipeIdx].first();
        pipes.pipes[pipeIdx].deq();
        
        // Consume the data so it can't be optimized away
        outData <= outData ^ d;

        // Dequeue from pipelines sequentially
        if (pipeIdx == maxBound)
        begin
            if (pipeTrips == maxBound)
            begin
                state <= STATE_finished;
            end

            pipeTrips <= pipeTrips + 1;
        end

        pipeIdx <= pipeIdx + 1;
    endrule


    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        Bit#(64) d = zeroExtend(outData);

        // Write the data so it can't be optimized away
        stdio.printf(msgDone, list1(d));
        linkStarterFinishRun.send(0);
        state <= STATE_done;
    endrule

    rule done (state == STATE_done);
        noAction;
    endrule

endmodule
