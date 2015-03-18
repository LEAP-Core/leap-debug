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
// Test individual request and pipeline throughput of various BRAM sizes.
// Use "null" benchmark.  No input data required.
//


// Library imports.

import FIFO::*;
import Vector::*;

//
// The Bluespec library providing BRAM.  HAsim already provides a BRAM
// interface and mkBRAM module, so the Bluespec library must be accessed
// with BRAM::
//
import BRAM::*;
import ClientServer::*;
import GetPut::*;
import List::*;

`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/fpga_components.bsh"

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/common_services.bsh"

// HAsim or Bluespec BRAM?
`define LEAP_BRAM 1


// ========================================================================
//
//  Test module.  Builds a BRAM of requested size and provides a test
//  interface.
//
// ========================================================================

interface BRAM_TEST#(type t_INDEX, type t_DATA);
    method Action writeStart();
    method Action writeEnd();

    method Action readStart();
    method Action readEnd();

    method Action readDelayedStart();
    method Action readDelayedEnd();

    method Action readWriteStart();
    method Action readWriteEnd();
endinterface: BRAM_TEST


module [CONNECTED_MODULE] mkBRAMTest
    // interface:
    (BRAM_TEST#(Bit#(indexBits), Bit#(dataBits)))
    provisos (Add#(a__, dataBits, 256),
              Add#(64, dataBits, TAdd#(dataBits, 64)),

              // These are for Bluespec BRAM
              Add#(x, 1, indexBits),
              Add#(y, 1, dataBits),

              Alias#(BRAMRequest#(Bit#(indexBits), Bit#(dataBits)), t_BRAM_REQ));
    
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    let msgWRITE_PIPE     <- getGlobalStringUID("Write %d bits: 16 take %d cycles\n");
    let msgWRITE_1        <- getGlobalStringUID("Write %d bits: 1 takes %d cycles\n");
    let msgREAD_PIPE      <- getGlobalStringUID("Read %d bits: 16 take %d cycles\n");
    let msgREAD_1         <- getGlobalStringUID("Read %d bits: 1 takes %d cycles\n");
    let msgREADDELAY_PIPE <- getGlobalStringUID("Read %d bits with delays: 16 take %d cycles\n");
    let msgREADWRITE_PIPE <- getGlobalStringUID("Read & write %d bits: 16 take %d cycles\n");
    let msgREADWRITE_1    <- getGlobalStringUID("Read & write %d bits: 1 takes %d cycles\n");
    let msgERR_VAL        <- getGlobalStringUID("BRAM-test: ERROR: unexpected read val (0x%08llx)\n");                                                     
`ifdef LEAP_BRAM
    BRAM#(Bit#(indexBits), Bit#(dataBits)) ram;

    if(`BRAM_CONSTRUCTOR == 0)
    begin
        ram <- mkBRAM();
    end

    if(`BRAM_CONSTRUCTOR == 1)
    begin
        ram <- mkBRAMClockDivider();
    end

`else
    BRAM::BRAM#(Bit#(indexBits), Bit#(dataBits)) ram <- BRAM::mkBRAM();
`endif
    Reg#(Bit#(64)) fpgaCycle <- mkReg(0);
    Reg#(Bit#(64)) lastCycle <- mkRegU();

    let writeDataStart = 'h12345678abcdef634828a88f321491aefda329658429f9929e9341758bc13463;

    Reg#(Bit#(indexBits)) writeIdx <- mkReg(0);
    Reg#(Bit#(256)) writeData <- mkRegU();

    Reg#(Bool) readDone <- mkRegU();
    Reg#(Bit#(indexBits)) readIdx <- mkReg(0);
    Reg#(Bit#(256)) expectReadData <- mkRegU();
    Reg#(Bit#(indexBits)) readWriteIdx <- mkReg(0);
    FIFO#(Tuple2#(Bool, Bit#(dataBits))) readQ <- mkSizedFIFO(16);
    Reg#(Bool) doingRW <- mkReg(False);

    Reg#(Bit#(indexBits)) readDelayedIdx <- mkReg(0);
    FIFO#(Tuple2#(Bool, Bit#(dataBits))) readDelayedQ <- mkSizedFIFO(16);

    Reg#(Bit#(64)) startCycle <- mkRegU();


    //
    // Functions for building Bluespec BRAM requests
    //
    function t_BRAM_REQ writeReq(Bit#(indexBits) idx, Bit#(dataBits) data);
        t_BRAM_REQ req;
        req.write = True;
        req.address = idx;
        req.datain = data;
        return req;
    endfunction

    function t_BRAM_REQ readReq(Bit#(indexBits) idx);
        t_BRAM_REQ req;
        req.write = False;
        req.address = idx;
        req.datain = ?;
        return req;
    endfunction


    //
    // doWrites --
    //     Write only test.
    //
    rule doWrites (writeIdx != 0);
`ifdef LEAP_BRAM
        ram.write(writeIdx, truncate(writeData));
`else
        ram.portA.request.put(writeReq(writeIdx, truncate(writeData)));
`endif
        
        // Update write data for next stage
        let new_data = (writeData << 1);
        new_data[0] = writeData[255];
        writeData <= new_data;

        // Compute single write latency one time
        if (writeIdx == 1)
        begin
            Bit#(64) write_cycles = truncate(fpgaCycle - lastCycle);
            stdio.printf(msgWRITE_1, list2(fromInteger(valueOf(dataBits)), write_cycles));
        end

        lastCycle <= fpgaCycle;
        writeIdx <= writeIdx - 1;
    endrule


    //
    // startReads --
    //     Read only test.
    //
    rule startReads (readIdx != 0);
`ifdef LEAP_BRAM
        ram.readReq(readIdx);
`else
        ram.portB.request.put(readReq(readIdx));
`endif
        readQ.enq(tuple2(readIdx == 1, truncate(expectReadData)));
        lastCycle <= fpgaCycle;

        // Compute expected value of next read (assumes doWrites ran first)
        let new_read_data = (expectReadData << 1);
        new_read_data[0] = expectReadData[255];
        expectReadData <= new_read_data;

        readIdx <= readIdx - 1;
    endrule


    //
    // startReadWrites --
    //     Read & write dual test using separate ports.
    //
    rule startReadWrites (readWriteIdx != 0);
`ifdef LEAP_BRAM
        ram.write(readWriteIdx + 1, truncate(writeData));
`else
        ram.portA.request.put(writeReq(readWriteIdx + 1, truncate(writeData)));
`endif

        // Compute write value for next iternation
        let new_data = (writeData << 1);
        new_data[0] = writeData[255];
        writeData <= new_data;

`ifdef LEAP_BRAM
        ram.readReq(readWriteIdx);
`else
        ram.portB.request.put(readReq(readWriteIdx));
`endif
        readQ.enq(tuple2(readWriteIdx == 1, truncate(expectReadData)));

        // Compute expected value of next read (assumes doWrites ran first)
        let new_read_data = (expectReadData << 1);
        new_read_data[0] = expectReadData[255];
        expectReadData <= new_read_data;

        lastCycle <= fpgaCycle;
        readWriteIdx <= readWriteIdx - 1;
    endrule
    

    //
    // getReads --
    //     Read consumer for both startReads and startReadWrites.
    //
    rule getReads (True);
`ifdef LEAP_BRAM
        let v <- ram.readRsp();
`else
        let v <- ram.portB.response.get();
`endif

        // Internal status queue
        match { .is_last, .expected_val } = readQ.first();
        readQ.deq();
        
        // Is read data correct?
        Bool err = False;
        if (expected_val != v)
        begin
            Bit#(64) p_v = truncate({ 64'b0, expected_val });
            stdio.printf(msgERR_VAL, list1(p_v));
            err = True;
        end

        // Display latency of a single read
        if (is_last)
        begin
            readDone <= True;

            if (! err)
            begin
                Bit#(64) read_cycles = truncate(fpgaCycle - lastCycle);
                stdio.printf(doingRW ? msgREADWRITE_1 : msgREAD_1, list2(fromInteger(valueOf(dataBits)), read_cycles ));
            end
        end
    endrule


    //
    // startDelayedReads --
    //     Read only test with consumer that doesn't run every cycle.
    //
    rule startDelayedReads (readDelayedIdx != 0);
`ifdef LEAP_BRAM
        ram.readReq(readDelayedIdx);
`else
        ram.portB.request.put(readReq(readDelayedIdx));
`endif
        readDelayedQ.enq(tuple2(readDelayedIdx == 1, truncate(expectReadData)));
        lastCycle <= fpgaCycle;

        // Compute expected value of next read (assumes doWrites ran first)
        let new_read_data = (expectReadData << 1);
        new_read_data[0] = expectReadData[255];
        expectReadData <= new_read_data;

        readDelayedIdx <= readDelayedIdx - 1;
    endrule
    

    //
    // getReadsDelayed --
    //     Read consumer for startDelayedReads.  Doesn't consume a read every
    //     cycle as a test of protection logic in BRAM to avoid missing reads
    //     or returning bad values.
    //
    rule getReadsDelayed (fpgaCycle[2] == 0);
`ifdef LEAP_BRAM
        let v <- ram.readRsp();
`else
        let v <- ram.portB.response.get();
`endif

        // Internal status queue
        match { .is_last, .expected_val } = readDelayedQ.first();
        readDelayedQ.deq();
        
        // Is read data correct?
        if (expected_val != v)
        begin
            Bit#(64) p_v = truncate({ 64'b0, expected_val });
            stdio.printf(msgERR_VAL, list1(p_v));
        end

        readDone <= is_last;
    endrule


    rule cycleCounter (True);
        fpgaCycle <= fpgaCycle + 1;
    endrule
    

    //
    // writeStart --
    //     Start write only test.  This must be run before the other two tests
    //     in order to initialize the BRAM for reads.
    //
    method Action writeStart();
        startCycle <= fpgaCycle;
        writeData <= writeDataStart;
        writeIdx <= 16;
    endmethod


    //
    // writeEnd --
    //     Wait for write-only test to complete and print summary.
    //
    method Action writeEnd() if (writeIdx == 0);
        Bit#(64) total_cycles = truncate(fpgaCycle - startCycle - 1);
        stdio.printf(msgWRITE_PIPE, list2(fromInteger(valueOf(dataBits)), total_cycles));
    endmethod


    //
    // readStart --
    //     Start read-only test.  writeStart must be called before this test
    //     to initialize the BRAM.
    //
    method Action readStart();
        startCycle <= fpgaCycle;
        expectReadData <= writeDataStart;
        readDone <= False;
        readIdx <= 16;
    endmethod


    //
    // readEnd --
    //     Wait for read-only test to complete and print summary.
    //
    method Action readEnd() if (readDone);
        Bit#(64) total_cycles = truncate(fpgaCycle - startCycle - 2);
        stdio.printf(msgREAD_PIPE, list2(fromInteger(valueOf(dataBits)), total_cycles ));
    endmethod


    //
    // readDelayedStart --
    //     Start read-only test with reader delays.  writeStart must be called
    //     before this test to initialize the BRAM.
    //
    method Action readDelayedStart();
        startCycle <= fpgaCycle;
        expectReadData <= writeDataStart;
        readDone <= False;
        readDelayedIdx <= 16;
    endmethod


    //
    // readDelayedEnd --
    //     Wait for read-only test with delays to complete and print summary.
    //
    method Action readDelayedEnd() if (readDone);
        Bit#(64) total_cycles = truncate(fpgaCycle - startCycle - 2);
        stdio.printf(msgREADDELAY_PIPE, list2(fromInteger(valueOf(dataBits)), total_cycles ));
    endmethod


    //
    // readWriteStart --
    //     Read & write combined test.  readStart() may not be run immediately
    //     after this test as the values written are not what it expects.
    //
    method Action readWriteStart();
        startCycle <= fpgaCycle;
        readDone <= False;
        expectReadData <= writeDataStart;
        writeData <= writeDataStart;
        doingRW <= True;
        readWriteIdx <= 16;
    endmethod


    //
    // readWriteEnd --
    //     Wait for read & write test to complete and print summary.
    //
    method Action readWriteEnd() if (readDone);
        Bit#(64) total_cycles = truncate(fpgaCycle - startCycle - 2);
        stdio.printf(msgREADWRITE_PIPE, list2(fromInteger(valueOf(dataBits)), total_cycles ));
        doingRW <= False;
    endmethod

endmodule


interface BRAM_TEST_DRIVER#(type t_INDEX, type t_DATA);
    method Action start();
    method Action finish();
endinterface: BRAM_TEST_DRIVER

module [CONNECTED_MODULE] mkBRAMTestDriver
    // interface:
    (BRAM_TEST_DRIVER#(Bit#(indexBits), Bit#(dataBits)))
    provisos (Add#(a__, dataBits, 256),
              Add#(64, dataBits, TAdd#(dataBits, 64)),

              // These are for Bluespec BRAM
              Add#(x, 1, indexBits),
              Add#(y, 1, dataBits));

    
    BRAM_TEST#(Bit#(indexBits), Bit#(dataBits)) bram <- mkBRAMTest();
    Reg#(Bit#(5)) state <- mkReg(0);

    rule driverWriteStart (state == 1);
        bram.writeStart();
        state <= state + 1;
    endrule

    rule driverWriteEnd (state == 2);
        bram.writeEnd();
        state <= state + 1;
    endrule

    rule driverReadStart (state == 3);
        bram.readStart();
        state <= state + 1;
    endrule

    rule driverReadEnd (state == 4);
        bram.readEnd();
        state <= state + 1;
    endrule

    rule driverReadDelayedStart (state == 5);
        bram.readDelayedStart();
        state <= state + 1;
    endrule

    rule driverReadDelayedEnd (state == 6);
        bram.readDelayedEnd();
        state <= state + 1;
    endrule

    rule driverReadWriteStart (state == 7);
        bram.readWriteStart();
        state <= state + 1;
    endrule

    rule driverReadWriteEnd (state == 8);
        bram.readWriteEnd();
        state <= 0;
    endrule

    method Action start() if (state == 0);
        state <= 1;
    endmethod
    
    method Action finish() if (state == 0);
        noAction;
    endmethod

endmodule


// ========================================================================
//
//  Test driver
//
// ========================================================================

module [CONNECTED_MODULE] mkSystem ();

    Reg#(Bit#(5)) state <- mkReg(0);

    STDIO#(Bit#(64)) stdio <- mkStdIO();

    let msgStart <- getGlobalStringUID("BRAM-test: Start\n");
    let msgDone  <- getGlobalStringUID("BRAM-test: Done\n"); 
    let msgErr   <- getGlobalStringUID("BRAM-test: terminated with error\n");


    rule start (state == 0);
        stdio.printf(msgStart, List::nil);
        state <= state + 1;
    endrule


    BRAM_TEST_DRIVER#(Bit#(10), Bit#(8)) bram8Test <- mkBRAMTestDriver();

    rule bram8_Start (state == 1);
        bram8Test.start();
        state <= state + 1;
    endrule

    rule bram8_Finish (state == 2);
        bram8Test.finish();
        state <= state + 1;
    endrule


    BRAM_TEST_DRIVER#(Bit#(10), Bit#(64)) bram64Test <- mkBRAMTestDriver();

    rule bram64_Start (state == 3);
        bram64Test.start();
        state <= state + 1;
    endrule

    rule bram64_Finish (state == 4);
        bram64Test.finish();
        state <= state + 1;
    endrule


    BRAM_TEST_DRIVER#(Bit#(5), Bit#(210)) bram210Test <- mkBRAMTestDriver();

    rule bram210_Start (state == 5);
        bram210Test.start();
        state <= state + 1;
    endrule

    rule bram210_Finish (state == 6);
        bram210Test.finish();
        state <= state + 1;
    endrule


    rule doneMessage (state == 7);
        stdio.printf(msgDone, List::nil);
        state <= state + 1;
    endrule

    rule exit (state == 8);
        $finish;
    endrule

endmodule