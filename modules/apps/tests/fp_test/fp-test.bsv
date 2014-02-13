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

import FIFOF::*;
import Vector::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/stdio_service.bsh"


// Number of tests
typedef 17 N_TESTS;

// Names of all FP pipelines
typedef enum
{
    FP_PIPE_ADD,
    FP_PIPE_MUL,
    FP_PIPE_DIV,
    FP_PIPE_SQRT,
    FP_PIPE_CMP,
    FP_PIPE_CVT_SD,
    FP_PIPE_CVT_ID,
    FP_PIPE_CVT_DS,
    FP_PIPE_CVT_IS,
    FP_PIPE_CVT_DI
}
FP_PIPELINE
    deriving (Eq, Bits);

// Test descriptor (inputs and expected output)
typedef struct
{
    FP_PIPELINE pipe;
    Bit#(6) op;
    Bit#(64) inA;
    Bit#(64) inB;
    Bit#(64) expectedOut;
}
TEST
    deriving (Eq, Bits);

//
// Internal state machine.
//
typedef enum
{
    STATE_START,
    STATE_RUNNING,
    STATE_END
}
STATE
    deriving (Eq, Bits);


module [CONNECTED_MODULE] mkSystem ()
    provisos (Alias#(t_TEST_IDX, Bit#(TLog#(TAdd#(N_TESTS, 1)))));

    Vector#(N_TESTS, TEST) tests = newVector();
    tests[0] =  TEST { pipe: FP_PIPE_ADD, op: 6'h0, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 64'h414529b221abe271 };
    tests[1] =  TEST { pipe: FP_PIPE_MUL, op: 6'h0, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 64'h4244058cc04b843b };
    tests[2] =  TEST { pipe: FP_PIPE_DIV, op: 6'h0, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 64'h40455b7f38c50664 };
    tests[3] =  TEST { pipe: FP_PIPE_SQRT, op: 6'h0, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 64'h4099b9533de0fa5e };

    // EQ
    tests[4] =  TEST { pipe: FP_PIPE_CMP, op: 6'b010100, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 0 };
    tests[5] =  TEST { pipe: FP_PIPE_CMP, op: 6'b010100, inA: 64'h4144adc35c0389f8, inB: 64'h4144adc35c0389f8, expectedOut: 1 };
    // LT
    tests[6] =  TEST { pipe: FP_PIPE_CMP, op: 6'b001100, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 0 };
    tests[7] =  TEST { pipe: FP_PIPE_CMP, op: 6'b001100, inA: 64'h40eefbb16a161e4f, inB: 64'h4144adc35c0389f8, expectedOut: 1 };
    tests[8] =  TEST { pipe: FP_PIPE_CMP, op: 6'b001100, inA: 64'h4144adc35c0389f8, inB: 64'h4144adc35c0389f8, expectedOut: 0 };
    // LE
    tests[9] =  TEST { pipe: FP_PIPE_CMP, op: 6'b011100, inA: 64'h4144adc35c0389f8, inB: 64'h40eefbb16a161e4f, expectedOut: 0 };
    tests[10] = TEST { pipe: FP_PIPE_CMP, op: 6'b011100, inA: 64'h40eefbb16a161e4f, inB: 64'h4144adc35c0389f8, expectedOut: 1 };
    tests[11] = TEST { pipe: FP_PIPE_CMP, op: 6'b011100, inA: 64'h4144adc35c0389f8, inB: 64'h4144adc35c0389f8, expectedOut: 1 };

    tests[12] = TEST { pipe: FP_PIPE_CVT_SD, op: 6'h0, inA: 64'h000000004a256e1b, inB: 64'h0000000000000000, expectedOut: 64'h4144adc360000000 };
    tests[13] = TEST { pipe: FP_PIPE_CVT_ID, op: 6'h0, inA: 64'h0000000020dfe309, inB: 64'h0000000000000000, expectedOut: 64'h41c06ff184800000 };
    tests[14] = TEST { pipe: FP_PIPE_CVT_DS, op: 6'h0, inA: 64'h4144adc35c0389f8, inB: 64'h0000000000000000, expectedOut: 64'h000000004a256e1b };
    tests[15] = TEST { pipe: FP_PIPE_CVT_IS, op: 6'h0, inA: 64'h0000000020dfe309, inB: 64'h0000000000000000, expectedOut: 64'h000000004e037f8c };
    tests[16] = TEST { pipe: FP_PIPE_CVT_DI, op: 6'h0, inA: 64'h41c06ff184800000, inB: 64'h0000000000000000, expectedOut: 64'h0000000020dfe309 };

    STDIO#(Bit#(64)) stdio <- mkStdIO();
    let msgOk   <- getGlobalStringUID("Correct: idx %ld, op %ld   0x%016llx 0x%016llx -> 0x%016llx\n");
    let msgFail <- getGlobalStringUID("ERROR:   idx %ld, op %ld   0x%016llx 0x%016llx -> 0x%016llx\n");

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    Vector#(10, FP_ACCEL) accel = newVector();
    accel[pack(FP_PIPE_ADD)] <- mkFPAcceleratorAdd();
    accel[pack(FP_PIPE_MUL)] <- mkFPAcceleratorMul();
    accel[pack(FP_PIPE_DIV)] <- mkFPAcceleratorDiv();
    accel[pack(FP_PIPE_SQRT)] <- mkFPAcceleratorSqrt();
    accel[pack(FP_PIPE_CMP)] <- mkFPAcceleratorCmp();
    accel[pack(FP_PIPE_CVT_SD)] <- mkFPAcceleratorCvtStoD();
    accel[pack(FP_PIPE_CVT_ID)] <- mkFPAcceleratorCvtItoD();
    accel[pack(FP_PIPE_CVT_DS)] <- mkFPAcceleratorCvtDtoS();
    accel[pack(FP_PIPE_CVT_IS)] <- mkFPAcceleratorCvtItoS();
    accel[pack(FP_PIPE_CVT_DI)] <- mkFPAcceleratorCvtDtoI();
    
    Reg#(t_TEST_IDX) testIdx <- mkReg(0);
    FIFOF#(Tuple2#(t_TEST_IDX, TEST)) testQ <- mkFIFOF();

    Reg#(STATE) state <- mkReg(STATE_START);

    rule start (state == STATE_START);
        linkStarterStartRun.deq();
        state <= STATE_RUNNING;
    endrule

    //
    // Initiate tests
    //
    rule dpReq ((state == STATE_RUNNING) && (testIdx != fromInteger(valueOf(N_TESTS))));
        FP_INPUT inp;
        inp.operation = tests[testIdx].op;
        inp.operandA = tests[testIdx].inA;
        inp.operandB = tests[testIdx].inB;

        let pipe = pack(tests[testIdx].pipe);
        accel[pipe].makeReq(inp);
        testQ.enq(tuple2(testIdx, tests[testIdx]));

        testIdx <= testIdx + 1;
    endrule

    rule dpRsp (state == STATE_RUNNING);
        match {.idx, .test} = testQ.first();
        testQ.deq();

        let outp <- accel[pack(test.pipe)].getRsp();
        Bit#(64) res = outp.result;

        let msg = ((res == test.expectedOut) ? msgOk : msgFail);
        stdio.printf(msg, list(zeroExtend(idx),
                               zeroExtend(pack(test.pipe)),
                               test.inA, test.inB, res));
    endrule

    //
    // Sync output when all tests are done.
    //
    rule done ((state == STATE_RUNNING) &&
               (testIdx == fromInteger(valueOf(N_TESTS))) &&
               ! testQ.notEmpty);

        linkStarterFinishRun.send(0);
        state <= STATE_END;
    endrule

    //
    // Wait for STDIO flush response and signal completion.
    //
    rule exit (state == STATE_END);
        noAction;
    endrule

endmodule
