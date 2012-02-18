//
// Copyright (C) 2009 Intel Corporation
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
    STATE_sync,
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
        state <= STATE_sync;
    endrule

    rule sync (state == STATE_sync);
        stdio.sync_req();
        state <= STATE_done;
    endrule

    rule done (state == STATE_done);
        let r <- stdio.sync_rsp();
        linkStarterFinishRun.send(0);
    endrule

endmodule

