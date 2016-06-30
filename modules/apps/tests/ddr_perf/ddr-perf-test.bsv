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
import LFSR::*;
import Vector::*;
import DefaultValue::*;

`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/ddr_sdram_device.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/dict/PARAMS_HARDWARE_SYSTEM.bsh"

typedef Bit#(64) CYCLE_COUNTER;

typedef enum
{
    STATE_init,
    STATE_ddr_init,
    STATE_write_seq,
    STATE_write_random,
    STATE_read_seq,
    STATE_read_random,
    STATE_read_write_random,
    STATE_finished,
    STATE_exit
}
STATE
    deriving (Bits, Eq);

//
// Implement a DDR performance test
//
module [CONNECTED_MODULE] mkSystem ();

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    DEBUG_FILE debugLog <- mkDebugFile("ddr_perf_test.out");

    // Output
    STDIO#(Bit#(64)) stdio <- mkStdIO();
    
    let msgInit          <- getGlobalStringUID("ddrPerfTest: start\n");
    let msgInitDone      <- getGlobalStringUID("ddrPerfTest: DDR bank %02d initialization done, cycle: %012d\n");
    let msgTestInit      <- getGlobalStringUID("ddrPerfTest: %s test start (# requests: %012d, working-set size: %012d)\n");
    let msgWriteSeq      <- getGlobalStringUID("sequential write");
    let msgWriteRand     <- getGlobalStringUID("random write");
    let msgReadSeq       <- getGlobalStringUID("sequential read");
    let msgReadRand      <- getGlobalStringUID("random read");
    let msgReadWriteRand <- getGlobalStringUID("random read/write");
    let msgWriteReq      <- getGlobalStringUID("ddrPerfTest: write request address = 0x%x, data = 0x%x\n");
    let msgReadData      <- getGlobalStringUID("ddrPerfTest: read request address = 0x%x, data = 0x%x\n");
    let msgDone          <- getGlobalStringUID("ddrPerfTest: done, cycle: %016lld, test cycle count: %016lld, # read requests: %012d, total latency: %020lld\n");
    let msgExit          <- getGlobalStringUID("ddrPerfTest: done\n");
    
    // Dynamic parameters.
    PARAMETER_NODE paramNode  <- mkDynamicParameterNode();
    Param#(1) verboseMode     <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_DDR_PERF_VERBOSE, paramNode);
    let verbose = verboseMode == 1;
    Param#(8) workingSetParam <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_DDR_PERF_WORKING_SET_SIZE_LOG, paramNode);
    Param#(8) testNumParam    <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_DDR_PERF_TEST_NUM_LOG, paramNode);
    Param#(8) maxReadsParam   <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_DDR_PERF_MAX_OUTSTANDING_READS, paramNode);
    Param#(1) addrMaskMode    <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_DDR_PERF_ADDR_MASK_MODE, paramNode);

    Reg#(STATE) state                 <- mkReg(STATE_init);
    Reg#(Bit#(2)) initCnt             <- mkReg(0);
    Reg#(CYCLE_COUNTER) cycleCnt      <- mkReg(0);
    Reg#(CYCLE_COUNTER) startCycleCnt <- mkReg(0);

    (* fire_when_enabled *)
    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    LFSR#(Bit#(64))        lfsr <- mkLFSR(); 
    LFSR#(Bit#(32))    addrLfsr <- mkLFSR(); 
    LOCAL_MEM_DDR      ddrBanks <- mkLocalMemDDRConnection();
    Reg#(DDR_BANK_IDX)  bankIdx <- mkReg(0); 

    function ActionValue#(FPGA_DDR_DUALEDGE_BEAT) genRandomTestData();
        actionvalue
            Bit#(64) random_value = lfsr.value();
            Vector#(TDiv#(FPGA_DDR_DUALEDGE_BEAT_SZ, 64), Bit#(64)) tmp_data = replicate(random_value);
            lfsr.next();
            return resize(pack(tmp_data));
        endactionvalue
    endfunction
   
    function FPGA_DDR_ADDRESS ddrAddrIncr(FPGA_DDR_ADDRESS addr) = addr + fromInteger(valueOf(DDR_WORDS_PER_BURST));
    
    function FPGA_DDR_ADDRESS getBurstAlignedAddr(FPGA_DDR_ADDRESS addr);
        return (addr << fromInteger(valueOf(DDR_BURST_WORD_IDX_SZ)));
    endfunction

    function ActionValue#(FPGA_DDR_ADDRESS) genRandomBurstAlignedAddr();
        actionvalue
            FPGA_DDR_ADDRESS random_addr = truncate(addrLfsr.value());
            addrLfsr.next();
            return getBurstAlignedAddr(random_addr);
        endactionvalue
    endfunction

    function FPGA_DDR_ADDRESS genAddrMask(Bit#(8) param, Bit#(1) mode);
        if (param <= 6 || mode == 0)
        begin
            return ((1 << workingSetParam)-1);
        end
        else
        begin
            FPGA_DDR_ADDRESS low_order_mask = (1 << 6) -1;
            FPGA_DDR_ADDRESS high_order_mask = ((1 << (param-6)) - 1);
            high_order_mask = high_order_mask << (fromInteger(valueOf(FPGA_DDR_ADDRESS_SZ)) - (param-6));
            return low_order_mask | high_order_mask;
        end
    endfunction

    Reg#(FPGA_DDR_ADDRESS) testAddrMask <- mkRegU;
    Reg#(Bit#(32))         testNumMax   <- mkRegU;
    Reg#(FPGA_DDR_ADDRESS) testAddr     <- mkReg(0);
    Reg#(Bit#(11))         testIdleCnt  <- mkReg(0);
    Reg#(Bit#(32))       workingSetSize <- mkReg(0);
    
    Reg#(Bit#(TLog#(TAdd#(1,FPGA_DDR_MAX_OUTSTANDING_READS)))) readCntMax <- mkRegU;
    Reg#(Bit#(TLog#(FPGA_DDR_BURST_LENGTH))) testAddrBurstIdx <- mkReg(0);

    Bit#(32) requestNum     = (zeroExtend(testNumMax) + 1);
    FPGA_DDR_DUALEDGE_BEAT_MASK fullMask = unpack(0);
   
    // ====================================================================
    //
    // Initialization
    //
    // ====================================================================
    
    (* fire_when_enabled *)
    rule doInit (state == STATE_init);
        linkStarterStartRun.deq();
        lfsr.seed(7);
        FPGA_DDR_ADDRESS mask = ?;
        if (workingSetParam >= fromInteger(valueOf(FPGA_DDR_ADDRESS_SZ)))
        begin
            mask = unpack(~0);
            workingSetSize <= (1 << fromInteger(valueOf(FPGA_DDR_ADDRESS_SZ))) - 1;
        end
        else
        begin
            mask = genAddrMask(workingSetParam, addrMaskMode);
            workingSetSize <= (1 << workingSetParam) - 1;
        end
        testAddrMask <= mask;
        testNumMax <= ((1 << testNumParam) -1);
        Bit#(8) read_max = ?;
        if (maxReadsParam >= fromInteger(valueOf(FPGA_DDR_MAX_OUTSTANDING_READS)))
        begin
            read_max = fromInteger(valueOf(FPGA_DDR_MAX_OUTSTANDING_READS));
        end
        else
        begin
            read_max = maxReadsParam;
        end
        readCntMax <= resize(read_max);
        stdio.printf(msgInit, List::nil);
        state <= STATE_ddr_init;
        debugLog.record($format("doInit: workingSetParam=%0d, testNumParam=%0d, maxReads=%0d, ddrBankAddrSz=%0d, addrMask=%b", 
                        workingSetParam, testNumParam, read_max, valueOf(FPGA_DDR_ADDRESS_SZ), mask));
    endrule

    (* fire_when_enabled *)
    rule ddrInit0 (state == STATE_ddr_init && initCnt == 0);
        let data <- genRandomTestData();
        ddrBanks[bankIdx].writeReq(testAddr);
        ddrBanks[bankIdx].writeData(data, fullMask);
        debugLog.record($format("ddrInit: write addr 0x%x", testAddr));
        debugLog.record($format("ddrInit: write data 0x%x, mask %b", data, fullMask));
        if (valueOf(FPGA_DDR_BURST_LENGTH) == 1) 
        begin
            if (testAddr == getBurstAlignedAddr(unpack(~0)))
            begin
                initCnt  <= 2;
                testAddr <= 0;
            end
            else
            begin
                testAddr <= ddrAddrIncr(testAddr);
            end
        end
        else
        begin
            testAddrBurstIdx <= testAddrBurstIdx + 1;
            initCnt <= 1;
        end
    endrule

    (* fire_when_enabled *)
    rule ddrInit1 (state == STATE_ddr_init && initCnt == 1);
        let data <- genRandomTestData();
        ddrBanks[bankIdx].writeData(data, fullMask);
        debugLog.record($format("ddrInit: write data 0x%x, mask %b", data, fullMask));
        testAddrBurstIdx <= testAddrBurstIdx + 1;
        if (testAddrBurstIdx == maxBound) 
        begin
            if (testAddr == getBurstAlignedAddr(unpack(~0)))
            begin
                initCnt  <= 2;
                testAddr <= 0;
            end
            else
            begin
                initCnt  <= 0;
                testAddr <= ddrAddrIncr(testAddr);
            end
        end
    endrule

    (* fire_when_enabled *)
    rule ddrInit2 (state == STATE_ddr_init && initCnt == 2);
        testIdleCnt <= testIdleCnt + 1;
        if (testIdleCnt == maxBound)
        begin
            initCnt <= 0;
            state   <= STATE_write_seq;
            stdio.printf(msgInitDone, list2(zeroExtend(bankIdx), zeroExtend(cycleCnt)));
            debugLog.record($format("DDR bank %0d initialization done, cycle=0x%011d", bankIdx, cycleCnt));
        end
   endrule 
    
    // ====================================================================
    //
    // Common test rules
    //
    // ====================================================================

    Reg#(Bool)             testInitialized  <- mkReg(False);
    Reg#(Bool)             testDoneSignal   <- mkReg(False);
    Reg#(Bool)             issueDoneSignal  <- mkReg(False);
    Reg#(CYCLE_COUNTER)    totalLatency     <- mkReg(0);
    Reg#(Bit#(32))         testNum          <- mkReg(0);
    Reg#(Bool)             issueReadReq     <- mkReg(False);
    Reg#(Bit#(32))         readReqNum       <- mkReg(0);
    
    COUNTER#(TLog#(TAdd#(1,FPGA_DDR_MAX_OUTSTANDING_READS))) readCnt <- mkLCounter(0);

    (* fire_when_enabled *)
    rule testInit(state != STATE_init && state != STATE_ddr_init && state != STATE_finished && state != STATE_exit && !testInitialized);
        let msg_test = ?;
        case (state)
            STATE_write_seq: msg_test = msgWriteSeq;
            STATE_write_random: msg_test = msgWriteRand;
            STATE_read_seq: msg_test = msgReadSeq;
            STATE_read_random: msg_test = msgReadRand;
            STATE_read_write_random: msg_test = msgReadWriteRand;
        endcase
        stdio.printf(msgTestInit, list3(zeroExtend(msg_test), zeroExtend(requestNum), zeroExtend(workingSetSize)));
        testInitialized  <= True;
        startCycleCnt    <= cycleCnt;
        testAddr         <= 0;
        testAddrBurstIdx <= 0;
        testNum          <= 0;
        totalLatency     <= 0;
        readReqNum       <= 0;
    endrule
    
    (* fire_when_enabled *)
    rule testDone(state != STATE_init && state != STATE_ddr_init && state != STATE_finished && state != STATE_exit && testInitialized && testDoneSignal);
        testIdleCnt <= testIdleCnt + 1;
        if (testIdleCnt == 0)
        begin
            stdio.printf(msgDone, list4(zeroExtend(cycleCnt), zeroExtend(cycleCnt-startCycleCnt), zeroExtend(readReqNum), zeroExtend(totalLatency)));
        end
        else if (testIdleCnt == maxBound)
        begin
            let new_state = state;
            case (state)
                STATE_write_seq: new_state = STATE_write_random;
                STATE_write_random: new_state = STATE_read_seq;
                STATE_read_seq: new_state = STATE_read_random;
                STATE_read_random: new_state = STATE_read_write_random;
                STATE_read_write_random:
                begin
                    if (bankIdx == fromInteger(valueOf(FPGA_DDR_BANKS)-1)) 
                    begin
                        new_state = STATE_finished;
                    end
                    else
                    begin
                        new_state = STATE_ddr_init;
                        bankIdx <= bankIdx + 1;
                    end
                end
            endcase
            testInitialized        <= False;
            testDoneSignal         <= False;
            issueDoneSignal        <= False;
            state                  <= new_state;
        end
    endrule

    // ====================================================================
    //
    // Write test rules
    //
    // ====================================================================

    Reg#(Bit#(1)) writeMode <- mkReg(0);

    rule writeTest0 ((state == STATE_write_seq || state == STATE_write_random) && testInitialized && !testDoneSignal && writeMode == 0);
        let w_addr = testAddr & testAddrMask;
        let w_data <- genRandomTestData();
        ddrBanks[bankIdx].writeReq(w_addr);
        ddrBanks[bankIdx].writeData(w_data, fullMask);
        debugLog.record($format("writeTest: addr 0x%x", w_addr));
        debugLog.record($format("writeTest: data 0x%x, mask %b", w_data, fullMask));
        if (verbose)
        begin
            Bit#(32) tmp_data = truncate(w_data);
            stdio.printf(msgWriteReq, list2(zeroExtend(w_addr), zeroExtend(tmp_data)));
        end
        if (valueOf(FPGA_DDR_BURST_LENGTH) == 1)
        begin
            testNum <= testNum + 1;
            if (state == STATE_write_random)
            begin
                let random_addr <- genRandomBurstAlignedAddr();
                testAddr <= random_addr;
            end
            else
            begin
                testAddr <= ddrAddrIncr(testAddr);
            end
            if (testNum == testNumMax)
            begin
                testDoneSignal <= True;
            end
        end
        else
        begin
            testAddrBurstIdx <= testAddrBurstIdx + 1;
            writeMode <= 1;
        end
    endrule
    
    rule writeTest1 ((state == STATE_write_seq || state == STATE_write_random || state == STATE_read_write_random) && testInitialized && !testDoneSignal && writeMode == 1);
        let w_data <- genRandomTestData();
        ddrBanks[bankIdx].writeData(w_data, fullMask);
        debugLog.record($format("writeTest: data 0x%x, mask %b", w_data, fullMask));
        testAddrBurstIdx <= testAddrBurstIdx + 1;
        if (testAddrBurstIdx == maxBound)
        begin
            testNum   <= testNum + 1;
            writeMode <= 0;
            if (state == STATE_write_random || state == STATE_read_write_random)
            begin
                let random_addr <- genRandomBurstAlignedAddr();
                if (state == STATE_read_write_random) 
                begin
                    issueReadReq <= (testNum == (testNumMax -1))? True : (addrLfsr.value()[0] == 0);
                end
                testAddr <= random_addr;
            end
            else
            begin
                testAddr <= ddrAddrIncr(testAddr);
            end
            if (testNum == testNumMax && state != STATE_read_write_random)
            begin
                testDoneSignal <= True;
            end
        end
    endrule
        
    // ====================================================================
    //
    // Read test rules
    //
    // ====================================================================
        
    FIFOF#(Tuple3#(FPGA_DDR_ADDRESS, CYCLE_COUNTER, Bool)) readReqQ <- mkSizedFIFOF(valueOf(FPGA_DDR_MAX_OUTSTANDING_READS));
    
    rule readTest ((state == STATE_read_seq || state == STATE_read_random) && testInitialized && !issueDoneSignal && (readCnt.value() < readCntMax));
        let r_addr = testAddr & testAddrMask;
        ddrBanks[bankIdx].readReq(r_addr);
        readReqQ.enq(tuple3(r_addr, cycleCnt, testNum == testNumMax));
        debugLog.record($format("readTest: addr 0x%x", r_addr));
        testNum  <= testNum + 1;
        readCnt.up();
        if (state == STATE_read_seq)
        begin
            testAddr <= ddrAddrIncr(testAddr);
        end
        else
        begin
            let random_addr <- genRandomBurstAlignedAddr();
            testAddr <= random_addr;
        end
        if (testNum == testNumMax)
        begin
            issueDoneSignal <= True;
        end
    endrule
    
    rule readWriteRandTest (state == STATE_read_write_random && testInitialized && !issueDoneSignal && writeMode == 0 && ((!issueReadReq) || (readCnt.value() < readCntMax)));
        let addr = testAddr & testAddrMask;
        if (issueReadReq)
        begin
            ddrBanks[bankIdx].readReq(addr);
            readReqQ.enq(tuple3(addr, cycleCnt, testNum == testNumMax));
            debugLog.record($format("readTest: read addr 0x%x", addr));
            readCnt.up();
        end
        else
        begin
            let w_data <- genRandomTestData();
            ddrBanks[bankIdx].writeReq(addr);
            ddrBanks[bankIdx].writeData(w_data, fullMask);
            debugLog.record($format("writeTest: addr 0x%x", addr));
            debugLog.record($format("writeTest: data 0x%x, mask %b", w_data, fullMask));
        end
        if (issueReadReq || valueOf(FPGA_DDR_BURST_LENGTH) == 1)
        begin
            let random_addr <- genRandomBurstAlignedAddr();
            testNum  <= testNum + 1;
            testAddr <= random_addr;
            if (testNum == testNumMax)
            begin
                issueDoneSignal <= True;
            end
            else if (testNum == (testNumMax -1))
            begin
                issueReadReq <= True;
            end
            else
            begin
                issueReadReq <= (addrLfsr.value()[0] == 0);
            end
        end
        else
        begin
            writeMode <= 1;
            testAddrBurstIdx <= testAddrBurstIdx + 1;
        end
    endrule
    
    Reg#(Bit#(TLog#(FPGA_DDR_BURST_LENGTH))) readBurstIdx <- mkReg(0);

    rule recvReadResp (((state == STATE_read_random) || (state == STATE_read_seq) || (state == STATE_read_write_random)) && testInitialized && !testDoneSignal);
        let resp <- ddrBanks[bankIdx].readRsp();
        match {.addr, .s_cycle, .is_done} = readReqQ.first();
        debugLog.record($format("recvReadResp: addr=0x%x, data=0x%x, latency=%8d", addr, resp, (cycleCnt-s_cycle) ));
        if (verbose)
        begin
            Bit#(32) tmp_data = truncate(resp);
            stdio.printf(msgReadData, list2(zeroExtend(addr), zeroExtend(tmp_data)));
        end
        readBurstIdx <= readBurstIdx + 1;
        if (valueOf(FPGA_DDR_BURST_LENGTH) == 1 || readBurstIdx == maxBound)
        begin
            totalLatency <= totalLatency + (cycleCnt-s_cycle);
            readReqNum   <= readReqNum + 1;
            readReqQ.deq();
            readCnt.down();
            if (is_done)
            begin
                testDoneSignal <= True;
            end
        end
    endrule
    
    // ====================================================================
    //
    // End of program.
    //
    // ====================================================================

    rule sendDone (state == STATE_finished);
        stdio.printf(msgExit, List::nil);
        linkStarterFinishRun.send(0);
        state <= STATE_exit;
    endrule

    rule finished (state == STATE_exit);
        noAction;
    endrule

endmodule

