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

import FIFO::*;
import Vector::*;
import GetPut::*;
import LFSR::*;
import DefaultValue::*;


`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/central_cache_common.bsh"

`include "awb/provides/mem_services.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/dict/VDEV_CACHE.bsh"
`include "awb/dict/PARAMS_HARDWARE_SYSTEM.bsh"

typedef enum {
  READ,
  WRITE, 
  INVAL,
  FLUSH
} COMMAND
    deriving (Bits, Eq);

typedef struct {
  Bit#(8)    pattern;
  Bit#(8)    op;
  Bit#(8)    address;
  Bit#(10)   iteration;
  Bit#(32)   id;
  t_MEM_DATA data;
  Bool       done;
} READ_META#(type t_MEM_DATA)
    deriving (Bits, Eq);


typedef Bit#(32) CYCLE_COUNTER;
typedef 4        MAX_ADDRESS;
typedef 3        MAX_PATTERNS;

module [CONNECTED_MODULE] mkSystem ();

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");    

    Reg#(Bool) start    <- mkReg(False);
    Reg#(Bool) finished <- mkReg(False);
    Vector#(2, Bool) testDone = newVector();


    /////
    // Test 1 - a normal sized cache
    /////

    // Local functional memory cache and cache prefetcher
    NumTypeParam#(4096) num_pvt_entries = ?;
    
    let prefetcher <- mkNullCachePrefetcher;

    // Backing store. 
    let backingStore <- mkDummyBackingStore();   

    // Build a central cache interface. 
    CENTRAL_CACHE_CLIENT#(Bit#(20), Bit#(64), Bit#(10)) cache <-
    mkCentralCacheClient(`VDEV_CACHE_TORTURE,
                         num_pvt_entries,
                         prefetcher,
                         True,
                         backingStore);
    

    testDone[0] <- mkTester("MEMORY", cache, start);

    /////
    // Test 2 - a tiny cache, intended to force address conflicts
    /////

    NumTypeParam#(4) num_pvt_entries2 = ?;

    let prefetcher2 <- mkNullCachePrefetcher;

    // Backing store. 
    backingStore <- mkDummyBackingStore();   

    // Build a central cache interface. 
    cache <- mkCentralCacheClient(`VDEV_CACHE_TORTURE2,
                         num_pvt_entries2,
                         prefetcher2,
                         True,
                         backingStore);

    testDone[1] <- mkTester("MEMORY_2", cache, start);


    rule beginTest;
        linkStarterStartRun.deq();
        start <= True;
    endrule
 

    rule endTest(all(id, testDone) && !finished);
        linkStarterFinishRun.send(0);
        finished <= True;
    endrule

endmodule

//
// Tests based on the word sized, checking various container sizes.  At
// some point the native word size gets ridiculous and doesn't meet timing.
// Limit the tested base word size to 64 bits.
//
module [CONNECTED_MODULE] mkTester#(String memoryName, CENTRAL_CACHE_CLIENT#(t_ADDR, t_DATA, t_READ_META) memory, Bool enabled) (Bool)
    provisos(
        Bits#(t_DATA, t_DATA_SZ),
        Bits#(t_ADDR, t_ADDR_SZ),
        Bits#(t_READ_META, t_READ_META_SZ),
        Add#(t_DATA_EXTRA_0, 16, t_DATA_SZ),
        Add#(t_DATA_EXTENSION_1, t_DATA_SZ, 64)
    );



    // Large data (multiple containers for single datum)
    DEBUG_FILE debugLog <- mkDebugFile(memoryName + "_mem_test.out");

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    let maxIterations = 512;

    Reg#(Bit#(8))   pattern    <- mkReg(0);
    Reg#(Bit#(8))   op         <- mkReg(0);
    Reg#(Bit#(8))   address    <- mkReg(0);
    Reg#(Bit#(10))  iteration  <- mkReg(0);
    Reg#(Bit#(8))   maxAddress <- mkReg(0);
    Reg#(Bool)      doneIssue  <- mkReg(False);
    Reg#(Bool)      doneResp   <- mkReg(False);
    Reg#(Bool)      init       <- mkReg(False);     
    Reg#(Bit#(32))  reqNum     <- mkReg(0);
      
    COMMAND patterns[valueof(MAX_PATTERNS)][12] = 
    {
        {WRITE,READ,WRITE,READ,INVAL,WRITE,READ,INVAL,READ,WRITE,READ,READ},                            
        {WRITE,WRITE,READ,INVAL,WRITE,WRITE,READ,INVAL,INVAL,READ,FLUSH,READ},                            
        {WRITE,READ,WRITE,READ,READ,READ,READ,READ,FLUSH,READ,READ,READ}                            
    };

    Bit#(8) maxOp [valueof(MAX_PATTERNS)] = 
    {
        12,
        12,
        12
    };

    Vector#(MAX_ADDRESS, Reg#(t_DATA)) values <- replicateM(mkRegU);

    FIFO#(READ_META#(t_DATA)) resultFIFO <- mkSizedFIFO(256);

    let memID      <- getGlobalStringUID(memoryName);
    let msgDataErr <- getGlobalStringUID("mem%s pattern %d address %d iteration %d [0x%8x] != 0x%08x  ERROR\n");

    SCOREBOARD_FIFOF#(20, t_DATA) sortResponseQ <- mkScoreboardFIFOF();

    // Random number generator
    LFSR#(Bit#(16)) lfsr <- mkLFSR_16();

    // Tests are defined by a pattern, a pattern length, and an address length
    
    rule doInit(!init);
        lfsr.seed(1); 
        init <= True; 
    endrule

    rule issueRequest(enabled && !doneIssue && init);
        reqNum <= reqNum + 1;
       
        // Issue request
        if (patterns[pattern][op] == READ)
        begin
            // address, readMeta, globalReadMeta
            let readMeta <- sortResponseQ.enq();
            memory.readReq(resize(address), unpack(zeroExtendNP(readMeta)), defaultValue);
            resultFIFO.enq(READ_META{id: reqNum, pattern: pattern, op: op, address: address, iteration: iteration, data: values[address], done: False});  
        end

        if (patterns[pattern][op] == WRITE)
        begin
            memory.write(resize(address), unpack(zeroExtend(lfsr.value)));
            values[address] <= unpack(zeroExtend(lfsr.value));
            lfsr.next();
        end

        if (patterns[pattern][op] == FLUSH)
        begin
            memory.flushReq(resize(address), True);
        end

        if (patterns[pattern][op] == INVAL)
        begin
            memory.invalReq(resize(address), True);
        end

        // do control
        // iterate address, op, pattern, iteration, totalAddresses
        if (address + 1 < maxAddress)
        begin
            address <= address + 1;
        end
        else
        begin
            address <= 0;
            if (op + 1 < maxOp[pattern])
            begin
                op <= op + 1;
            end
            else
            begin
                op <= 0;

                if (pattern + 1 < fromInteger(valueof(MAX_PATTERNS)))
                begin
                    pattern <= pattern + 1;
                end
                else
                begin
                    pattern <= 0; 
                    if (iteration + 1 < maxIterations ) 
                    begin
                        iteration <= iteration + 1;
                    end 
                    else
                    begin
                        iteration <= 0;
                        if (maxAddress + 1 <= fromInteger(valueof(MAX_ADDRESS)))
                        begin
                            maxAddress <= maxAddress + 1;
                        end
                        else
                        begin
                            doneIssue <= True;
                        end
                    end
                end
            end
        end

    endrule

    rule clearInvalFlushResp;
        memory.invalOrFlushWait();
    endrule

    rule pushDone(doneIssue);
        resultFIFO.enq(READ_META{done: True});
    endrule

    // Caches may generate reponses out-of-order.
    rule sortResponses;
        let readResp <- memory.readResp();
        sortResponseQ.setValue(truncateNP(pack(readResp.readMeta)), readResp.val);
    endrule

    rule checkResult(!resultFIFO.first.done); 
       resultFIFO.deq();
       sortResponseQ.deq;
       if(pack(sortResponseQ.first) != pack(resultFIFO.first.data))
       begin
           stdio.printf(msgDataErr, list6(zeroExtend(memID), zeroExtend(resultFIFO.first.pattern), zeroExtend(resultFIFO.first.address), zeroExtend(resultFIFO.first.iteration), zeroExtend(pack(resultFIFO.first.data)), zeroExtend(pack(sortResponseQ.first))));            
           $display("mem%s pattern %d address %d iteration %d [0x%8x] != 0x%08x  ERROR", memoryName, resultFIFO.first.pattern, resultFIFO.first.address, resultFIFO.first.iteration, resultFIFO.first.data, sortResponseQ.first);
           $finish;  
       end

    endrule

    return resultFIFO.first.done;

endmodule


module mkDummyBackingStore (CENTRAL_CACHE_CLIENT_BACKING#(t_ADDR, t_DATA, t_READ_META))
    provisos (
        Bits#(t_DATA, t_DATA_SZ),
        Bits#(t_ADDR, t_ADDR_SZ),
        Bits#(t_READ_META, t_READ_META_SZ)
    );

    MEMORY_IFC#(Bit#(12), t_DATA) cache <- mkBRAM;
    let readAddrFIFO <- mkFIFO;
    let writeAddrFIFO <- mkFIFO;
    let writeMetaFIFO <- mkFIFO;
    let sendAckFIFO <- mkFIFO;
    let ackFIFO <- mkFIFO;
    
    Reg#(Bit#(TAdd#(1,TLog#(CENTRAL_CACHE_WORDS_PER_LINE)))) readIdx  <- mkReg(0);
    Reg#(Bit#(TAdd#(1,TLog#(CENTRAL_CACHE_WORDS_PER_LINE)))) writeIdx <- mkReg(0);
    
    rule doRead;
        cache.readReq(resize(readAddrFIFO.first()) + resize(readIdx));

        if(readIdx + 1 == fromInteger(valueof(CENTRAL_CACHE_WORDS_PER_LINE)))
        begin
            readIdx <= 0;
            readAddrFIFO.deq();
        end
        else
        begin
            readIdx <= readIdx + 1;
        end
    endrule

    // Request a full line
    method Action readLineReq(t_ADDR addr,
                              t_READ_META readMeta,
                              RL_CACHE_GLOBAL_READ_META globalReadMeta);

        readAddrFIFO.enq(addr);

    endmethod

    // The read line response is pipelined.  For every readLineReq there must
    // be one readResp for every word in the requested line.  Cache entries
    // have CENTRAL_CACHE_WORDS_PER_LINE.  Low bits of the line are received
    // first.  The bool argument indicates whether the line is cacheable.
    // The value has is consumed only in the cycle when the last word in a
    // line is transmitted.
    method ActionValue#(Tuple2#(t_DATA, Bool)) readResp();
        let data <- cache.readRsp;
        return tuple2(data,True);
    endmethod

    // Write to backing storage.  A write begins with a write request.
    // It is followed by multiple write data calls, one call per word
    // in a cache line.
    method Action writeLineReq(t_ADDR addr,
                               Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) wordValidMask,
                               Bool sendAck);
    
        sendAckFIFO.enq(sendAck);
        writeAddrFIFO.enq(addr);
        writeMetaFIFO.enq(wordValidMask);
    endmethod

    // Called multiple times after a write request is received -- once for
    // each word in a line.  THIS METHOD WILL BE CALLED FOR A WORD EVEN
    // IF THE CONTROL INFORMATION SAYS THE WORD IS NOT VALID.  Low bits
    // of the line are sent first.
    method Action writeData(t_DATA val);

        if(writeMetaFIFO.first[writeIdx])
        begin
            cache.write(resize(writeAddrFIFO.first) + resize(writeIdx), val);
        end

        if(writeIdx + 1 == fromInteger(valueof(CENTRAL_CACHE_WORDS_PER_LINE)))
        begin
            writeIdx <= 0;
            writeMetaFIFO.deq;
            sendAckFIFO.deq;
            writeAddrFIFO.deq;

            if(sendAckFIFO.first)
            begin
                ackFIFO.enq(True);
            end 
        end
        else
        begin
            writeIdx <= writeIdx + 1;
        end   
    endmethod

    // Ack from write request when sendAck is True
    method Action writeAckWait();
        ackFIFO.deq();
    endmethod

endmodule