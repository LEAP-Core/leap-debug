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
// @file chan-test.bsv
// @brief Channel integrity test
//
// @author Michael Adler
//

import FIFO::*;
import LFSR::*;

`include "asim/provides/librl_bsv.bsh"
`include "asim/provides/fpga_components.bsh"
`include "asim/provides/virtual_platform.bsh"
`include "asim/provides/low_level_platform_interface.bsh"

`include "asim/rrr/service_ids.bsh"
`include "asim/rrr/server_stub_CHANTEST.bsh"
`include "asim/rrr/client_stub_CHANTEST.bsh"

// types

typedef enum 
{
    STATE_IDLE,
    STATE_F2H16
} 
STATE deriving(Bits,Eq);

typedef Bit#(64) PAYLOAD;

// mkApplication

module mkApplication#(VIRTUAL_PLATFORM vp)();

    LowLevelPlatformInterface llpi = vp.llpint;
    
    // Instantiate stubs
    ServerStub_CHANTEST serverStub <- mkServerStub_CHANTEST(llpi.rrrServer);
    ClientStub_CHANTEST clientStub <- mkClientStub_CHANTEST(llpi.rrrClient);
    
    // Counters
    Reg#(Bit#(64)) cycle <- mkReg(0);
    Reg#(Bit#(64)) f2hIter <- mkReg(0);
    Reg#(Bit#(64)) h2fPackets <- mkReg(0);
    Reg#(Bit#(64)) h2fErrors <- mkReg(0);
    Reg#(Bit#(64)) h2fBitsFlipped <- mkReg(0);
    
    Reg#(STATE) state <- mkReg(STATE_IDLE);
    
    // Count FPGA cycles
    rule tick (True);
        cycle <= cycle + 1;
    endrule
    
    //
    // FPGA -> Host one-way test
    //
    rule startF2HOneWayTest (state == STATE_IDLE);
        // accept request from host
        let count <- serverStub.acceptRequest_F2HStartOneWayTest();
        f2hIter <= count;

        state <= STATE_F2H16;
    endrule
    

    //
    // sendF2HMessage --
    //     Send the requested number of messages to the host.  Each message
    //     has 4 random 64 bit values and their complements.
    //

    LFSR#(Bit#(32)) random[16];
    for (Integer n = 0; n < 16; n = n + 1)
    begin
        random[n] <- mkFeedLFSR(lfsr32FeedPolynomials(n));
    end

    rule sendF2HMessage (state == STATE_F2H16);
        UINT64 p0 = { random[0].value(), random[1].value() };
        UINT64 p1 = { random[2].value(), random[3].value() };
        UINT64 p2 = { random[4].value(), random[5].value() };
        UINT64 p3 = { random[6].value(), random[7].value() };
        UINT64 p4 = { random[8].value(), random[9].value() };
        UINT64 p5 = { random[10].value(), random[11].value() };
        UINT64 p6 = { random[12].value(), random[13].value() };
        UINT64 p7 = { random[14].value(), random[15].value() };
        for (Integer n = 0; n < 16; n = n + 1)
        begin
            random[n].next();
        end

        clientStub.makeRequest_F2HOneWayMsg16(p0, p1, p2, p3, p4, p5, p6, p7,
                                              ~p0, ~p1, ~p2, ~p3, ~p4, ~p5, ~p6, ~p7);
        
        // Update test iteration counter
        let i = f2hIter - 1;
        f2hIter <= i;

        if (i == 0)
        begin
            // Done
            state <= STATE_IDLE;
        end
    endrule


    //
    // Host -> FPGA test
    //
    FIFO#(Tuple3#(UInt#(16), Bit#(16), IN_TYPE_H2FOneWayMsg16)) h2fErrorQ <- mkFIFO();

    Reg#(Bit#(64)) lastMsgCycle <- mkReg(0);
    Reg#(Bit#(16)) chunkIdx <- mkReg(0);

    (* conservative_implicit_conditions *)
    rule checkH2FMessage (True);
        let msg <- serverStub.acceptRequest_H2FOneWayMsg16();

        //
        // This code is more relevant to the ACP than many other channels.
        // On ACP, messages are grouped into chunks.  This code tries to
        // figure out the index of this message in the chunk by looking
        // for a time gap between chunks.
        //
        Bit#(16) chunk_idx;
        if (cycle > (lastMsgCycle + 20))
        begin
            // New chunk
            chunk_idx = 0;
        end
        else
        begin
            chunk_idx = chunkIdx + 1;
        end

        lastMsgCycle <= cycle;
        chunkIdx <= chunk_idx;

        //
        // 8-15 are complements of 0-7.
        //
        let mask0 = ~(msg.payload0 ^ msg.payload8);
        let mask1 = ~(msg.payload1 ^ msg.payload9);
        let mask2 = ~(msg.payload2 ^ msg.payload10);
        let mask3 = ~(msg.payload3 ^ msg.payload11);
        let mask4 = ~(msg.payload4 ^ msg.payload12);
        let mask5 = ~(msg.payload5 ^ msg.payload13);
        let mask6 = ~(msg.payload6 ^ msg.payload14);
        let mask7 = ~(msg.payload7 ^ msg.payload15);

        if ((mask0 != 0) ||
            (mask1 != 0) ||
            (mask2 != 0) ||
            (mask3 != 0) ||
            (mask4 != 0) ||
            (mask5 != 0) ||
            (mask6 != 0) ||
            (mask7 != 0))
        begin
            h2fErrors <= h2fErrors + 1;

            // Count the number of flipped bits
            UInt#(16) bit_errors =
                zeroExtend(countOnes(mask0)) +
                zeroExtend(countOnes(mask1)) +
                zeroExtend(countOnes(mask2)) +
                zeroExtend(countOnes(mask3)) +
                zeroExtend(countOnes(mask4)) +
                zeroExtend(countOnes(mask5)) +
                zeroExtend(countOnes(mask6)) +
                zeroExtend(countOnes(mask7));

            h2fErrorQ.enq(tuple3(bit_errors, chunk_idx, msg));
        end

        h2fPackets <= h2fPackets + 1;
    endrule


    (* descending_urgency = "h2fError, sendF2HMessage" *)
    rule h2fError (True);
        match {.bits, .chunk_idx, .msg} = h2fErrorQ.first();
        h2fErrorQ.deq();
        
        h2fBitsFlipped <= h2fBitsFlipped + zeroExtend(pack(bits));
        clientStub.makeRequest_H2FNoteError(pack(bits),
                                            chunk_idx,
                                            msg.payload0,
                                            msg.payload1,
                                            msg.payload2,
                                            msg.payload3,
                                            msg.payload4,
                                            msg.payload5,
                                            msg.payload6,
                                            msg.payload7,
                                            msg.payload8,
                                            msg.payload9,
                                            msg.payload10,
                                            msg.payload11,
                                            msg.payload12,
                                            msg.payload13,
                                            msg.payload14,
                                            msg.payload15);
    endrule

    rule getH2FErrorCount (state == STATE_IDLE);
        let dummy <- serverStub.acceptRequest_H2FGetStats();
        serverStub.sendResponse_H2FGetStats(h2fPackets, h2fErrors, h2fBitsFlipped);
    endrule

endmodule
