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

// Library imports.

import FIFO::*;
import Vector::*;
import LFSR::*;


`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/librl_bsv_cache.bsh"
`include "asim/provides/fpga_components.bsh"

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/common_services.bsh"

// ========================================================================
//
//  Test driver
//
// ========================================================================

typedef 8                   QUEUES;
typedef Bit#(1)             MSHR_BIN;
typedef Bit#(TLog#(QUEUES)) QUEUE_IDX;
typedef Bit#(16)            MSHR_DATA;
typedef 4                   MSHR_ENTRIES;

typedef struct {
    QUEUE_IDX tag;
    MSHR_BIN  index;
    Bit#(32)  timestamp;
} DEQ_STRUCT
    deriving(Bits, Eq);


module [CONNECTED_MODULE] mkSystem ();

    let msgFinish     <- getGlobalStringUID("Tests Complete, Pass Vector: %x\n");
    let msgStart      <- getGlobalStringUID("Tests Starting");
    STDIO#(Bit#(64)) stdio <- mkStdIO();
   
    Reg#(Bool)     done        <- mkReg(False);
    Reg#(Bit#(32)) counter     <- mkReg(0);
    Reg#(Bool)     initialized <- mkReg(False); 


    Vector#(5, Bool) testers = newVector;

    // Test 0
    MSHR_BIN binVar = ?;
    NumTypeParam#(MSHR_ENTRIES) numMSHREntries = ?;  
    DEBUG_FILE debugLog0 <- mkDebugFile("mshr_test0.out");
    testers[0] <- mkMSHRTester(binVar, numMSHREntries, debugLog0);

    // Test 1
    Bit#(2) binVar1 = ?;
    NumTypeParam#(8) numMSHREntries1 = ?;  
    DEBUG_FILE debugLog1 <- mkDebugFile("mshr_test1.out");
    testers[1] <- mkMSHRTester(binVar1, numMSHREntries1, debugLog1);

    // Test 2
    Bit#(4) binVar2 = ?;
    NumTypeParam#(2) numMSHREntries2 = ?;  
    DEBUG_FILE debugLog2 <- mkDebugFile("mshr_test2.out");
    testers[2] <- mkMSHRTester(binVar2, numMSHREntries2, debugLog2);

    // Test 3
    Bit#(0) binVar3 = ?;
    NumTypeParam#(2) numMSHREntries3 = ?;  
    DEBUG_FILE debugLog3 <- mkDebugFile("mshr_test3.out");
    testers[3] <- mkMSHRTester(binVar3, numMSHREntries3, debugLog3);

    // Test 4
    Bit#(2) binVar4 = ?;
    NumTypeParam#(1) numMSHREntries4 = ?;  
    DEBUG_FILE debugLog4 <- mkDebugFile("mshr_test4.out");
    testers[4] <- mkMSHRTester(binVar4, numMSHREntries4, debugLog4);

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

        if(!passed &&& counter > 2000000) 
        begin
            $display("Test Failed: %b", pack(testers));
            $finish;
        end

        if(counter > 2000000)
        begin
            done <= True;
            stdio.printf(msgFinish, list1(zeroExtend(pack(testers))));
        end
        
    endrule
  
endmodule

module [CONNECTED_MODULE] mkMSHRTester#(t_MSHR_BINS binTypeVar, NumTypeParam#(n_ENTRIES) numMSHREntries, DEBUG_FILE debugLog) (Bool);

    RL_MSHR#(QUEUE_IDX, MSHR_DATA, MSHR_BIN, n_ENTRIES) mshr <- mkMSHR(debugLog);

    FIFO#(DEQ_STRUCT)                                timerQueue   <- mkSizedFIFO(64);
    Vector#(QUEUES, LFSR#(Bit#(8)))                  timerLFSRs   <- replicateM(mkLFSR_8);
    Vector#(QUEUES, Reg#(MSHR_DATA))                 countersIn   <- replicateM(mkReg(0));
    Vector#(QUEUES, Reg#(MSHR_DATA))                 countersOut  <- replicateM(mkReg(0));
    Vector#(QUEUES, LFSR#(Bit#(16)))                 enqLFSRs     <- replicateM(mkLFSR_16);
    Reg#(Bool)                                       initialized  <- mkReg(False);   
    Reg#(Bit#(32))                                   counter      <- mkReg(0);   
    Reg#(Bit#(16))                                   deqCount     <- mkReg(1);   
    Reg#(Bool)                                       done         <- mkReg(False);

    let msgError     <- getGlobalStringUID("Cycle: %d Data mismatch: queue index: %h tag: %h, expected: %d, got: %d\n");
    STDIO#(Bit#(64)) stdio <- mkStdIO();

    rule doInit(!initialized);
        initialized <= True;

        for( Integer i = 0; i < valueof(QUEUES); i = i + 1) 
        begin
            enqLFSRs[i].seed(fromInteger(i)+245); 
            timerLFSRs[i].seed(fromInteger(i+45)); 
        end        

    endrule

    rule incrCounter;
        counter <= counter + 1;
    endrule


    for( Integer i = 0; i < valueof(QUEUES); i = i + 1) 
    begin

            QUEUE_IDX enqSelect = truncate(enqLFSRs[i].value());        
            QUEUE_IDX enqTag = fromInteger(i);        
            MSHR_BIN  enqIdx = truncate(enqTag);        

            rule mshrEnq (enqSelect == enqTag && initialized && !done);               
                if(mshr.notFullMSHR(enqIdx, enqTag)) 
                begin
                    mshr.enqMSHR(enqIdx, enqTag, countersIn[enqTag]);
                    timerQueue.enq(DEQ_STRUCT{timestamp: zeroExtend(timerLFSRs[enqTag].value()[4:0]) + counter, tag: enqTag, index: enqIdx});
                    countersIn[enqTag] <= countersIn[enqTag] + 1;
                    timerLFSRs[enqTag].next();                
                end
            endrule

        rule updateSelectLFSR(initialized);
                enqLFSRs[i].next();
        endrule
    end


    // Although we allow the various enqueuers to fight to enqueue data, we dequeue in-order, and in a single rule.
    rule mshrDeq(timerQueue.first.timestamp < counter);
        if(mshr.firstMSHR(timerQueue.first.index) != countersOut[timerQueue.first.tag])
        begin
            stdio.printf(msgError, list5(zeroExtend(counter), zeroExtend(timerQueue.first.index), zeroExtend(timerQueue.first.tag), zeroExtend(countersIn[timerQueue.first.tag]), zeroExtend(mshr.firstMSHR(timerQueue.first.index))));
            $display("Cycle: %d Data mismatch: queue index: %h tag: %h, expected: %d, got: %d", counter, timerQueue.first.index, timerQueue.first.tag, countersIn[timerQueue.first.tag], mshr.firstMSHR(timerQueue.first.index));
            $finish;
        end

        timerQueue.deq();
        mshr.deqMSHR(timerQueue.first.index);

        countersOut[timerQueue.first.tag] <= countersOut[timerQueue.first.tag] + 1;
        deqCount <= deqCount + 1;
 
        if(deqCount > 50000) 
        begin
            done <= True;            
        end

    endrule
 
    rule checkHead (counter[6:0] == 0 && !done);
        $display("deqCount: %d", deqCount);
        mshr.dump();
    endrule

    return done._read();
endmodule