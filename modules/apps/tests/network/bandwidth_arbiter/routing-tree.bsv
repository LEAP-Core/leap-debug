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
`include "asim/provides/hardware_system.bsh"

typedef Bit#(`ROUTER_WIDTH) ROUTER_DATA;
typedef Bit#(`ROUTER_WIDTH) ROUTER_ADDR;


module [CONNECTED_MODULE] mkRouter ();
    NumTypeParam#(`ROUTER_RADIX)  radix  = ?;
    NumTypeParam#(`ROUTER_LEAVES) leaves = ?;
    let routingTree <- mkTreeLayer(0, radix, leaves);

    rule handleRoot;
        match {.dest, .data} = routingTree.first();
        routingTree.enq(TREE_MSG{dstNode: dest, data: data});
        routingTree.deq;
    endrule

endmodule





// 
// mkTreeLayer --
//   Recursively isntatiates a node of the router tree and the subtree associated with the node.
//   For leaf nodes, a channel-based client is instantiated. 
//
module [CONNECTED_MODULE] mkTreeLayer#(Integer offset, NumTypeParam#(n_RADIX) radix, NumTypeParam#(n_LEAVES) leaves) (CONNECTION_ADDR_TREE#(ROUTER_ADDR, Tuple2#(ROUTER_ADDR, ROUTER_DATA), ROUTER_DATA))
    provisos(Add#(1, n_RADIX_extra_bits, TMul#(2, TLog#(n_RADIX))),
             Add#(1, n_RADIX_VALUES_extra_bits, TLog#(TAdd#(1, TExp#(TMul#(2, TLog#(n_RADIX)))))));

    // Generate child offsets. 
    Vector#(TAdd#(n_RADIX, 1), Integer) offsets = zipWith( \+ , replicate(offset), map( fromInteger, zipWith( \* , replicate(valueof(n_LEAVES)/valueof(n_RADIX)), genVector)));  

    let rootIfc = ?;

    // Build the child nodes.
    if (valueof(n_LEAVES) > 1)
    begin

        NumTypeParam#(TDiv#(n_LEAVES, n_RADIX)) childLeaves = ?;
        List#(CONNECTION_ADDR_TREE#(ROUTER_ADDR, Tuple2#(ROUTER_ADDR, ROUTER_DATA), ROUTER_DATA)) children <- List::zipWith3M(mkTreeLayer, List::take(valueof(n_RADIX) ,toList(offsets)), List::replicate(valueof(n_RADIX), radix), List::replicate(valueof(n_RADIX), childLeaves));

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
        CONNECTION_ADDR_TREE#(ROUTER_ADDR, Tuple2#(ROUTER_ADDR, ROUTER_DATA), ROUTER_DATA) parent <- mkTreeRouter(toVector(children), map(fromInteger, offsets), mkLocalArbiterBandwidth(genWith(genFrac)));
         
        rootIfc = parent;

    end
    else
    begin 

        messageM("Building tree leaf: offset " + integerToString(offset) + " radix " + integerToString(valueof(n_RADIX)) + " leaves " + integerToString(valueof(n_LEAVES)));
        rootIfc <- mkTreeLeafNode("TEST", offset); 

    end

    return rootIfc;

endmodule  
