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
// mkTreeLayer --
//   Recursively isntatiates a node of the router tree and the subtree associated with the node.
//   For leaf nodes, a channel-based client is instantiated. 
//
module [CONNECTED_MODULE] mkTreeLayer#(Integer offset, NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves) (CONNECTION_ADDR_TREE#(ROUTER_ADDR, Tuple2#(ROUTER_ADDR, ROUTER_DATA), ROUTER_DATA));

    // Generate child offsets. 
    Vector#(TAdd#(n_RADIX, 1), Integer) offsets = zipWith( \+ , replicate(offset), map( fromInteger, zipWith( \* , replicate(valueof(n_LEAVES)/valueof(n_RADIX)), genVector)));  

    let rootIfc = ?;

    // Build the child nodes.
    if (valueof(n_LEAVES) > 1)
    begin

        messageM("Building tree layer: offset " + integerToString(offset) + " radix " + integerToString(valueof(n_RADIX)) + " leaves " + integerToString(valueof(n_LEAVES)));
        NumTypeParam#(TDiv#(n_LEAVES, n_RADIX)) childLeaves = ?;
        List#(CONNECTION_ADDR_TREE#(ROUTER_ADDR, Tuple2#(ROUTER_ADDR, ROUTER_DATA), ROUTER_DATA)) children <- List::zipWith3M(mkTreeLayer, List::take(valueof(n_RADIX) ,toList(offsets)), List::replicate(valueof(n_RADIX), radix), List::replicate(valueof(n_RADIX), childLeaves));

        // Having constructed the children, we can construct the parent. 
        CONNECTION_ADDR_TREE#(ROUTER_ADDR, Tuple2#(ROUTER_ADDR, ROUTER_DATA), ROUTER_DATA) parent <- mkTreeRouter(toVector(children), map(fromInteger, offsets), mkLocalArbiterBandwidth(replicate(3'd4)));
 
        rootIfc = parent;

    end
    else
    begin 

        messageM("Building tree leaf: offset " + integerToString(offset) + " radix " + integerToString(valueof(n_RADIX)) + " leaves " + integerToString(valueof(n_LEAVES)));
        rootIfc <- mkTreeLeafNode("TEST", offset); 

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

    function ActionValue#(Bool) doCurryTester(mFunction, id);
        actionvalue
            NumTypeParam#(`ROUTER_RADIX)  radix  = ?;
            NumTypeParam#(`ROUTER_LEAVES) leaves = ?;
            DEBUG_FILE debugFile <- mkDebugFile("tree_tester_" + integerToString(id) + ".out");
            let m <- mFunction(radix, leaves, debugFile);
            return m;
        endactionvalue
    endfunction

    Vector#(1, Bool) testers <- zipWithM(doCurryTester, replicate(mkTreeTester), genVector());

    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

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
//   sends data into the tree randomly, based on an LFSR.  It terminates when a hard coded number
//   of responses have been received.
// 
module [CONNECTED_MODULE] mkTreeTester#(NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves, DEBUG_FILE debugLog) (Bool)
    provisos(Add#(address_extra_bits, TLog#(TAdd#(1, n_LEAVES)), 16));

    let routingTree <- mkTreeLayer(0, radix, leaves);

    Vector#(n_LEAVES, LFSR#(Bit#(32)))                            enqLFSRs     <- replicateM(mkLFSR_32);
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
        match {.dest, .data} = routingTree.first();
        routingTree.enq(TREE_MSG{dstNode: dest, data: data});
        routingTree.deq;
    endrule


    for( Integer i = 0; i < valueof(n_LEAVES); i = i + 1) 
    begin

        CONNECTION_RECV#(TREE_MSG#(ROUTER_ADDR, ROUTER_DATA)) incomingResponse <- mkConnectionRecv("TEST_TREE_NODE_OUT_" + integerToString(i));

        CONNECTION_SEND#(Tuple2#(ROUTER_ADDR, ROUTER_DATA)) outgoingRequest <- mkConnectionSend("TEST_TREE_NODE_IN_" + integerToString(i));

        //let enqSelect = enqLFSRs[i].value();        
        Bit#(10) enqSelect = truncate(enqLFSRs[i].value());        
        let enqTag = fromInteger(i);   
        Vector#(8,Bit#(64)) payloadVector = replicate(999999 * signExtend(enqLFSRs[i].value()));                 
        ROUTER_DATA payload = truncateNP(pack(payloadVector));

        rule treeEnq (enqSelect == enqTag && initialized && !done);               
            resultFIFO[i].enq(payload);
            outgoingRequest.send(tuple2(fromInteger(i),payload));                
            enqLFSRs[i].next();
            debugLog.record($format("treeEnq: node_id=%0d, data=0x%x", fromInteger(i), payload));
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
            debugLog.record($format("treeDeq: node_id=%0d, data=0x%x (%0d), expected=0x%x", 
                            fromInteger(i), incomingResponse.receive.data, incomingResponse.receive.dstNode, resultFIFO[i].first));
        endrule

    end


    rule countCompletions;

        let total = countElem(True, readVReg(dequeued));
 
        deqCount <= deqCount + zeroExtend(pack(total));
       
        if (pack(total) != 0)
        begin
            debugLog.record($format("deqCount: old=%0d, add=%0d", deqCount, pack(total)));
        end

        if(deqCount > 5000) 
        begin
            done <= True;            
        end

    endrule
 
    return done._read();
endmodule
