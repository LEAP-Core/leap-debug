//
// Copyright (c) 2015, Intel Corporation
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

// Library imports.

import FIFO::*;
import Vector::*;
import List::*;
import LFSR::*;


`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/librl_bsv_cache.bsh"
`include "asim/provides/fpga_components.bsh"

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/common_services.bsh"

typedef Bit#(`ROUTER_WIDTH) ROUTER_DATA;
typedef Bit#(`ROUTER_WIDTH) ROUTER_ADDR;



//
// mkSystem --
//   Instantiates a set of testbenches and manages them. 
//
module [CONNECTED_MODULE] mkSystem ();

    let msgFinish     <- getGlobalStringUID("Tests Complete, Pass Vector: %x\n");
    let msgStart      <- getGlobalStringUID("Tests Starting");
    STDIO#(Bit#(64)) stdio <- mkStdIO();
   
    Reg#(Bool)     done        <- mkReg(False);
    Reg#(Bit#(32)) counter     <- mkReg(0);
    Reg#(Bool)     initialized <- mkReg(False); 

    NumTypeParam#(`ROUTER_RADIX)  radix  = ?;
    NumTypeParam#(`ROUTER_LEAVES) leaves = ?;

    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    Vector#(1, Bool) testers <- replicateM(mkTreeTester(radix, leaves, ?));

    rule init(!initialized);
        stdio.printf(msgStart,List::nil);
        initialized <= True;
    endrule

    rule incrCounter;
         counter <= counter + 1;
    endrule

    rule checkTesters(!done);
        Bool passed = all(id, testers);

        if(passed)
        begin                        
            $display("Test Passed");
            linkStarterFinishRun.send(0);
        end 

        if(!passed &&& counter > 20000000) 
        begin
            $display("Test Failed: %b", pack(testers));
            $finish;
        end

        if(counter > 20000000 || passed && !done)
        begin
            done <= True;
            stdio.printf(msgFinish, list1(zeroExtend(pack(testers))));

        end
        
    endrule
  
endmodule


//
// mkTreeTester -- 
//   Constructs a router tree of the given size, and straps a test bench to it.  The test bench 
//   sends data into the tree as quickly as possible.  It terminates when a hard coded number
//   of responses have been received.
// 

module [CONNECTED_MODULE] mkTreeTester#(NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves, DEBUG_FILE debugLog) (Bool)
    provisos(Add#(address_extra_bits, TLog#(TAdd#(1, n_LEAVES)), 16),
             Add#(1, n_RADIX_extra_bits, TMul#(2, TLog#(n_RADIX))),
             Add#(1, n_RADIX_VALUES_extra_bits, TLog#(TAdd#(1, TExp#(TMul#(2, TLog#(n_RADIX)))))));

    Vector#(n_LEAVES, LFSR#(Bit#(16)))                            enqLFSRs     <- replicateM(mkLFSR_16);
    Vector#(n_LEAVES, Wire#(Bool))                                dequeued     <- replicateM(mkDWire(False));
    Vector#(n_LEAVES, FIFO#(ROUTER_DATA))                         resultFIFO   <- replicateM(mkSizedFIFO(1024));
    Vector#(n_LEAVES, Reg#(Bit#(32)))                             deqCounts    <- replicateM(mkReg(0));
    Reg#(Bool)                                                    initialized  <- mkReg(False);   
    Reg#(Bit#(32))                                                counter      <- mkReg(0);   
    Reg#(Bit#(16))                                                deqCount     <- mkReg(1);   
    Reg#(Bool)                                                    done         <- mkReg(False);

    let msgError     <- getGlobalStringUID("Cycle: %d Data mismatch: queue index: %h tag: %h, expected: %d, got: %d\n");
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    rule doInit(!initialized);
        initialized <= True;

        for( Integer i = 0; i < valueof(n_LEAVES); i = i + 1) 
        begin
            enqLFSRs[i].seed(fromInteger(i)+245); 
        end        

    endrule

    rule incrCounter;
        counter <= counter + 1;
    endrule


    for( Integer i = 0; i < valueof(n_LEAVES); i = i + 1) 
    begin

        CONNECTION_RECV#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) incomingResponse <- mkConnectionRecv("TEST_TREE_NODE_OUT_" + integerToString(i));

        CONNECTION_SEND#(Tuple2#(ROUTER_ADDR, ROUTER_DATA)) outgoingRequest <- mkConnectionSend("TEST_TREE_NODE_IN_" + integerToString(i));

        Vector#(8,Bit#(16)) payloadVector = replicate(enqLFSRs[i].value());                 
        ROUTER_DATA payload = truncateNP(pack(payloadVector));

        rule treeEnq (initialized && !done);               
            resultFIFO[i].enq(payload);
            outgoingRequest.send(tuple2(fromInteger(i),payload));                
            enqLFSRs[i].next();
        endrule

        rule treeDeq; 
            resultFIFO[i].deq();
            incomingResponse.deq();
            if(incomingResponse.receive.data != resultFIFO[i].first)
            begin
                $display("Failed to get correct result %d got %h (%h), expected %h", i, incomingResponse.receive.data, incomingResponse.receive.dstNode, resultFIFO[i].first);
                $finish;
            end
            dequeued[i] <= True;
        endrule

    end


    rule countCompletions;

        let total = countElem(True, readVReg(dequeued));
 
        deqCount <= deqCount + zeroExtend(pack(total));

        for( Integer i = 0; i < valueof(n_LEAVES); i = i + 1) 
        begin
            if(dequeued[i])
            begin            
                deqCounts[i] <= deqCounts[i] + 1;
            end
        end 
   
        if(deqCount > 5000) 
        begin

            done <= True;            
        end

    endrule
 
    return done._read();
endmodule
