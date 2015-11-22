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


module [CONNECTED_MODULE] mkTreeLayer#(Integer offset, NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves) (CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA));

    // Generate child offsets. 
    Vector#(TAdd#(n_RADIX, 1), Integer) offsets = zipWith( \+ , replicate(offset), map( fromInteger, zipWith( \* , replicate(valueof(n_LEAVES)/valueof(n_RADIX)), genVector)));  

    let rootIfc = ?;

    // Build the child nodes.
    if (valueof(n_LEAVES) > 1)
    begin

        messageM("Building tree layer: offset " + integerToString(offset) + " radix " + integerToString(valueof(n_RADIX)) + " leaves " + integerToString(valueof(n_LEAVES)));
        NumTypeParam#(TDiv#(n_LEAVES, n_RADIX)) childLeaves = ?;
        List#(CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA)) children <- List::zipWith3M(mkTreeLayer, List::take(valueof(n_RADIX) ,toList(offsets)), List::replicate(valueof(n_RADIX), radix), List::replicate(valueof(n_RADIX), childLeaves));

        // Having constructed the children, we can construct the parent. 
        CONNECTION_ADDR_TREE#(ROUTER_ADDR, ROUTER_DATA) parent <- mkTreeRouter(toVector(children), map(fromInteger, offsets), mkLocalArbiterBandwidth(replicate(3'd4)));
 
        rootIfc = parent;

    end
    else
    begin 

        messageM("Building tree leaf: offset " + integerToString(offset) + " radix " + integerToString(valueof(n_RADIX)) + " leaves " + integerToString(valueof(n_LEAVES)));
        rootIfc <- mkLeafNode(offset); 

    end

    return rootIfc;

endmodule  

module [CONNECTED_MODULE] mkSystem ();

    let msgFinish     <- getGlobalStringUID("Tests Complete, Pass Vector: %x\n");
    let msgStart      <- getGlobalStringUID("Tests Starting");
    STDIO#(Bit#(64)) stdio <- mkStdIO();
   
    Reg#(Bool)     done        <- mkReg(False);
    Reg#(Bit#(32)) counter     <- mkReg(0);
    Reg#(Bool)     initialized <- mkReg(False); 


    NumTypeParam#(`ROUTER_RADIX)  radix  = ?;
    NumTypeParam#(`ROUTER_LEAVES) leaves = ?;

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

        if( counter[6:0] == 0 )
        begin 
            $display("Test Status: %b", pack(testers));
        end

        if(passed)
        begin             
            $display("Test Passed");
            $finish;
        end 

        if(!passed &&& counter > 20000000) 
        begin
            $display("Test Failed: %b", pack(testers));
            $finish;
        end

        if(counter > 20000000)
        begin
            done <= True;
            stdio.printf(msgFinish, list1(zeroExtend(pack(testers))));
        end
        
    endrule
  
endmodule



module [CONNECTED_MODULE] mkTreeTester#(NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves, DEBUG_FILE debugLog) (Bool)
    provisos(Add#(address_extra_bits, TLog#(TAdd#(1, n_LEAVES)), 16));

    let routingTree <- mkTreeLayer(0, radix, leaves);

    Vector#(n_LEAVES, LFSR#(Bit#(16)))                            enqLFSRs     <- replicateM(mkLFSR_16);
    Vector#(n_LEAVES, Wire#(Bool))                                dequeued     <- replicateM(mkDWire(False));
    Vector#(n_LEAVES, FIFO#(ROUTER_DATA))                         resultFIFO   <- replicateM(mkSizedFIFO(1024));
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
        $display("Handling root message: id %d value %h", routingTree.first.dstNode, routingTree.first.data);
        routingTree.enq(routingTree.first);
        routingTree.deq;
    endrule


    for( Integer i = 0; i < valueof(n_LEAVES); i = i + 1) 
    begin

        CONNECTION_RECV#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) incomingResponse <- mkConnectionRecv("TREE_NODE_OUT_" + integerToString(i));

        CONNECTION_SEND#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) outgoingRequest <- mkConnectionSend("TREE_NODE_IN_" + integerToString(i));

        let enqSelect = enqLFSRs[i].value();        
        let enqTag = fromInteger(i);   
        Vector#(8,Bit#(16)) payloadVector = replicate(enqLFSRs[i].value());                 
        ROUTER_DATA payload = truncateNP(pack(payloadVector));

        rule treeEnq (enqSelect == enqTag && initialized && !done);               
            resultFIFO[i].enq(payload);
            outgoingRequest.send(TREE_MSG{dstNode: fromInteger(i), data: payload});                
            enqLFSRs[i].next();
            $display("Tree enq child %d data %h", i, payload); 
        endrule

        rule advanceLFSR (enqSelect != enqTag && initialized && !done);
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

        $display("DeqCount: %d", deqCount);

        if(deqCount > 5000) 
        begin
            done <= True;            
        end

    endrule
 
    return done._read();
endmodule
