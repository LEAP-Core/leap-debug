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

typedef Bit#(64) ROUTER_DATA;
typedef Bit#(64) ROUTER_ADDR;


//
//  mkLeafNode --
//    Instantiates a leaf node in the router tree. The external interface is 
//    channel based. 
module [CONNECTED_MODULE] mkLeafNode#(Integer index) (CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA));

    CONNECTION_RECV#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) incomingRequest <-
        mkConnectionRecv("TREE_NODE_IN_" + integerToString(index));

    CONNECTION_SEND#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) outgoingRequest <-
        mkConnectionSend("TREE_NODE_OUT_" + integerToString(index));
    
    // Outgoing portion of the network
    method enq = outgoingRequest.send;
    method notFull = outgoingRequest.notFull;

    // Incoming portion
    method first = incomingRequest.receive;
    method deq = incomingRequest.deq;
    method notEmpty = incomingRequest.notEmpty;

endmodule


// 
// mkTreeLayer --
//   Recursively isntatiates a node of the router tree and the subtree associated with the node.
//   For leaf nodes, a channel-based client is instantiated. 
//
module [CONNECTED_MODULE] mkTreeLayer#(Integer offset, NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves) (CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA))
    provisos(Add#(1, n_RADIX_extra_bits, TMul#(2, TLog#(n_RADIX))),
             Add#(1, n_RADIX_VALUES_extra_bits, TLog#(TAdd#(1, TExp#(TMul#(2, TLog#(n_RADIX)))))));

    // Generate child offsets. 
    Vector#(TAdd#(n_RADIX, 1), Integer) offsets = zipWith( \+ , replicate(offset), map( fromInteger, zipWith( \* , replicate(valueof(n_LEAVES)/valueof(n_RADIX)), genVector)));  

    let rootIfc = ?;

    // Build the child nodes.
    if (valueof(n_LEAVES) > 1)
    begin

        NumTypeParam#(TDiv#(n_LEAVES, n_RADIX)) childLeaves = ?;
        List#(CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA)) children <- List::zipWith3M(mkTreeLayer, List::take(valueof(n_RADIX) ,toList(offsets)), List::replicate(valueof(n_RADIX), radix), List::replicate(valueof(n_RADIX), childLeaves));

        // This function will generate a priority series for the router bandwidth allocation. It proceeds 0/2^n,1/2^n,2/2^n,4/2^n,....
        function UInt#(TMul#(2,TLog#(n_RADIX))) genFrac(Integer index);
            let frac = 0;

            if(index > 0)
            begin
                frac = (1 << (fromInteger(index) - 1));                
            end
            
            return frac;
        endfunction

        // Having constructed the children, we can construct the parent. 
        CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA) parent <- mkTreeRouter(toVector(children), map(fromInteger, offsets), mkLocalArbiterBandwidth(genWith(genFrac)));
         
        rootIfc = parent;

    end
    else
    begin 

        messageM("Building tree leaf: offset " + integerToString(offset) + " radix " + integerToString(valueof(n_RADIX)) + " leaves " + integerToString(valueof(n_LEAVES)));
        rootIfc <- mkLeafNode(offset); 

    end

    return rootIfc;

endmodule  


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

    let routingTree <- mkTreeLayer(0, radix, leaves);

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

    rule handleRoot;
        routingTree.enq(routingTree.first);
        routingTree.deq;
    endrule


    for( Integer i = 0; i < valueof(n_LEAVES); i = i + 1) 
    begin

        CONNECTION_RECV#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) incomingResponse <- mkConnectionRecv("TREE_NODE_OUT_" + integerToString(i));

        CONNECTION_SEND#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) outgoingRequest <- mkConnectionSend("TREE_NODE_IN_" + integerToString(i));

        Vector#(8,Bit#(16)) payloadVector = replicate(enqLFSRs[i].value());                 
        ROUTER_DATA payload = truncateNP(pack(payloadVector));

        rule treeEnq (initialized && !done);               
            resultFIFO[i].enq(payload);
            outgoingRequest.send(TREE_MSG{dstNode: fromInteger(i), data: payload});                
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
