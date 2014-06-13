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
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import GetPut::*;
import LFSR::*;
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "awb/provides/coh_mem_test_common.bsh"


interface COH_MEM_TEST_ENGINE_IFC#(type t_ADDR);
    method Action setIter(Bit#(24) num);
    method Action setWorkingSet(t_ADDR range);
endinterface


module [CONNECTED_MODULE] mkCohMemTestEngine#(MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) memory,
                                              Integer engineId,
                                              DEBUG_FILE debugLog)
    // interface:
    (COH_MEM_TEST_ENGINE_IFC#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));


    // Random number generators
    LFSR#(Bit#(32)) lfsr   <- mkLFSR_32();
    LFSR#(Bit#(8))  lfsr2  <- mkLFSR_8();
    LFSR#(Bit#(16)) lfsr3  <- mkLFSR_16();

    Reg#(t_ADDR)            addr <- mkReg(unpack(0));
    Reg#(Bool)       initialized <- mkReg(False);
    Reg#(Bit#(24))       maxIter <- mkReg(0);
    Reg#(Bit#(24))      testIter <- mkReg(0);
    Reg#(t_ADDR)            wset <- mkReg(unpack(0));
    Reg#(ENGINE_PORT_NUM) myPort <- mkWriteValidatedReg();
    Reg#(Bit#(24))        errNum <- mkReg(0);

    FIFOF#(COH_MEM_ENGINE_TEST_REQ) testReqQ <- mkFIFOF(); 
    FIFOF#(t_ADDR)                 addrDiffQ <- mkFIFOF(); 
    FIFOF#(Bit#(24))               testRespQ <- mkBypassFIFOF();

    CONNECTION_ADDR_RING#(ENGINE_PORT_NUM, Tuple2#(COH_MEM_ENGINE_TEST_REQ, t_ADDR)) link_test_req <-
        mkConnectionAddrRingDynNode("Coh_mem_test_req");
    CONNECTION_ADDR_RING#(ENGINE_PORT_NUM, Tuple2#(ENGINE_PORT_NUM, Bit#(24))) link_test_resp <-
        mkConnectionAddrRingNode("Coh_mem_test_resp", myPort._read());
    
    rule doInit (!initialized && maxIter != 0 && pack(wset) != 0);
        lfsr.seed(fromInteger(engineId+1));
        lfsr2.seed(fromInteger(engineId+1));
        lfsr3.seed(fromInteger(engineId+1));
        let port_num = link_test_req.nodeID();
        myPort <= port_num;
        initialized <= True;    
        debugLog.record($format("doInit: port_num=%03d, maxIter=%08d, workingSet=0x%x", port_num, maxIter, wset));
    endrule
    
    // ====================================================================
    //
    // Receive/Send test requests/responses from/to network
    //
    // ====================================================================

    rule recvTestReq (initialized && link_test_req.notEmpty());
        match {.req, .diff} = link_test_req.first();
        link_test_req.deq();
        testReqQ.enq(req);
        addrDiffQ.enq(diff);
    endrule

    rule sendTestResp (testRespQ.notEmpty());
        let err_num = testRespQ.first();
        testRespQ.deq();
        link_test_resp.enq(0, tuple2(myPort, err_num));
    endrule

    // ====================================================================
    //
    // Running tests: write sequential/random 
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule testWriteSeq (initialized && testReqQ.first() == COH_TEST_REQ_WRITE_SEQ);
        t_DATA data = unpack(resize(pack(addr)+ pack(addrDiffQ.first())));
        memory.write(addr, data);
        debugLog.record($format("writeSeq: addr 0x%x, data 0x%x", addr, data));
        if (pack(addr) == pack(wset))
        begin
            addr <= unpack(0);
            testReqQ.deq();
            addrDiffQ.deq();
            testRespQ.enq(0);
        end
        else
        begin
            addr <= unpack(pack(addr) + 1);
        end
    endrule
    
    (* conservative_implicit_conditions *)
    rule testWriteRand (initialized && testReqQ.first() == COH_TEST_REQ_WRITE_RAND);
        t_ADDR w_addr = unpack(resize(lfsr.value()) & pack(wset));
        t_DATA data = unpack(resize(pack(w_addr)+ pack(addrDiffQ.first())));
        memory.write(w_addr, data);
        debugLog.record($format("writeRand: addr 0x%x, data 0x%x", w_addr, data));
        lfsr.next();
        if (testIter == maxIter)
        begin
            testReqQ.deq();
            addrDiffQ.deq();
            testRespQ.enq(0);
            testIter <= 0;
        end
        else
        begin
            testIter <= testIter + 1;
        end
    endrule

    // ====================================================================
    //
    // Running tests: read sequential/random
    //
    // ====================================================================

    FIFOF#(Tuple2#(t_ADDR, Bool)) readAddrQ  <- mkSizedFIFOF(64);
    Reg#(Bool) readTestReqDone <- mkReg(False);

    rule testReadRand (initialized && testReqQ.first() == COH_TEST_REQ_READ_RAND && !readTestReqDone);
        t_ADDR r_addr = unpack(resize(lfsr.value()) & pack(wset));
        lfsr.next();
        memory.readReq(r_addr);
        let done = (testIter == maxIter);
        readAddrQ.enq(tuple2(r_addr, done));
        debugLog.record($format("readRand: addr 0x%x", r_addr));
        if (done)
        begin
            addr <= unpack(0);
            readTestReqDone <= True;
            testIter <= 0;
        end
        else
        begin
            testIter <= testIter + 1;
        end
    endrule

    rule testReadSeq (initialized && testReqQ.first() == COH_TEST_REQ_READ_SEQ && !readTestReqDone);
        memory.readReq(addr);
        let done = (testIter == maxIter);
        readAddrQ.enq(tuple2(addr, done));
        debugLog.record($format("readSeq: addr 0x%x", addr));
        if (done)
        begin
            addr <= unpack(0);
            readTestReqDone <= True;
            testIter <= 0;
        end
        else
        begin
            addr <= (pack(addr) == pack(wset))? unpack(0) : unpack(pack(addr) + 1);
            testIter <= testIter + 1;
        end
    endrule

    (* descending_urgency = "testReadRecv, testReadRand, testReadSeq" *)
    rule testReadRecv (initialized && (testReqQ.first() == COH_TEST_REQ_READ_SEQ || testReqQ.first() == COH_TEST_REQ_READ_RAND));
        match {.r_addr, .done} = readAddrQ.first();
        readAddrQ.deq();
        let val <- memory.readRsp();
        let diff = addrDiffQ.first();
        debugLog.record($format("readRecv: addr 0x%x, data 0x%x", r_addr, val));
        
        // Convert value so it equals r_addr
        t_DATA tmp_v = unpack(pack(val) - resize(pack(diff)));
        t_DATA expected_v = unpack(resize(pack(r_addr)+ pack(diff)));

        let new_err_num = errNum;

        if (pack(diff) != 0 && pack(tmp_v) != resize(pack(r_addr))) 
        begin
            new_err_num = new_err_num + 1;
            debugLog.record($format("readRecv: ERROR! addr 0x%x, data 0x%x, expected 0x%x", r_addr, val, expected_v));
        end

        if (done)
        begin
            testReqQ.deq();
            addrDiffQ.deq();
            testRespQ.enq(new_err_num);
            readTestReqDone <= False;
        end

        errNum <= (done)? 0 : new_err_num; 
    
    endrule


    // ====================================================================
    //
    // Running tests: fence 
    //
    // ====================================================================

    rule testFence (initialized && testReqQ.first() == COH_TEST_REQ_FENCE);
         if (!memory.writePending() && !memory.readPending())
         begin
             testReqQ.deq();
             addrDiffQ.deq();
             testRespQ.enq(0); 
         end
    endrule

    
    // ====================================================================
    //
    // Running tests: random
    //
    // ====================================================================

    Reg#(Bool) randomTestReqDone <- mkReg(False);

    rule testRandom (initialized && testReqQ.first() == COH_TEST_REQ_RANDOM && !randomTestReqDone);
        Bit#(1) is_write_req = truncate(lfsr2.value());
        lfsr2.next();
        
        t_ADDR test_addr = unpack(resize(lfsr.value()) & pack(wset));
        lfsr.next();
        
        if (is_write_req == 1) 
        begin
            t_DATA data = unpack(resize(lfsr3.value()));
            lfsr3.next();
            memory.write(test_addr, data);
            debugLog.record($format("testRandom: write addr 0x%x, data 0x%x", test_addr, data));
        end
        else
        begin
            memory.readReq(test_addr);
            let done = (testIter == maxIter);
            readAddrQ.enq(tuple2(test_addr, done));
            debugLog.record($format("testRandom: read addr 0x%x", test_addr));
        end
        
        if (testIter == maxIter)
        begin
            randomTestReqDone <= True;
            testIter <= 0;
        end
        else
        begin
            testIter <= testIter + 1;
        end
    endrule

    rule testRandomWithFence (initialized && testReqQ.first() == COH_TEST_REQ_RANDOM_FENCE && !randomTestReqDone);
        Bit#(2) req_type = truncate(lfsr2.value());
        lfsr2.next();
        
        t_ADDR test_addr = unpack(resize(lfsr.value()) & pack(wset));
        lfsr.next();
        
        if (req_type == 0) // write request 
        begin
            t_DATA data = unpack(resize(lfsr3.value()));
            lfsr3.next();
            memory.write(test_addr, data);
            debugLog.record($format("testRandomWithFence: write addr 0x%x, data 0x%x", test_addr, data));
        end
        else if (req_type == 1) //read request
        begin
            memory.readReq(test_addr);
            let done = (testIter == maxIter);
            readAddrQ.enq(tuple2(test_addr, done));
            debugLog.record($format("testRandomWithFence: read addr 0x%x", test_addr));
        end
        else if (req_type == 2)
        begin
            memory.readFence();
            debugLog.record($format("testRandomWithFence: read fence..."));
        end
        else
        begin
            memory.writeFence();
            debugLog.record($format("testRandomWithFence: write fence..."));
        end
        
        if (testIter == maxIter)
        begin
            randomTestReqDone <= True;
            testIter <= 0;
        end
        else
        begin
            testIter <= testIter + 1;
        end
    endrule

    rule testRandomRecv ((testReqQ.first() == COH_TEST_REQ_RANDOM || testReqQ.first() == COH_TEST_REQ_RANDOM_FENCE) && readAddrQ.notEmpty());
        match {.r_addr, .done} = readAddrQ.first();
        readAddrQ.deq();
        let v <- memory.readRsp();
        debugLog.record($format("readRecv: addr 0x%x, data 0x%x", r_addr, v));
        if (done)
        begin
            testReqQ.deq();
            addrDiffQ.deq();
            testRespQ.enq(0);
            randomTestReqDone <= False;
        end
    endrule

    (* descending_urgency = "testRandomRecv, testRandomEnd, testRandom, testRandomWithFence" *)
    rule testRandomEnd ((testReqQ.first() == COH_TEST_REQ_RANDOM || testReqQ.first() == COH_TEST_REQ_RANDOM_FENCE) && !readAddrQ.notEmpty() && randomTestReqDone);
        testReqQ.deq();
        addrDiffQ.deq();
        testRespQ.enq(0);
        randomTestReqDone <= False;
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action setIter(Bit#(24) num);
        maxIter <= num - 1;
        debugLog.record($format("setTestIter: numIter = %08d", num));
    endmethod
    
    method Action setWorkingSet(t_ADDR range);
        wset <= unpack(pack(range) - 1);
        debugLog.record($format("setWorkingSet: wset = 0x%x", range));
    endmethod

endmodule

