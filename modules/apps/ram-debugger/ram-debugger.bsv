//
// INTEL CONFIDENTIAL
// Copyright (c) 2008 Intel Corp.  Recipient is granted a non-sublicensable 
// copyright license under Intel copyrights to copy and distribute this code 
// internally only. This code is provided "AS IS" with no support and with no 
// warranties of any kind, including warranties of MERCHANTABILITY,
// FITNESS FOR ANY PARTICULAR PURPOSE or INTELLECTUAL PROPERTY INFRINGEMENT. 
// By making any use of this code, Recipient agrees that no other licenses 
// to any Intel patents, trade secrets, copyrights or other intellectual 
// property rights are granted herein, and no other licenses shall arise by 
// estoppel, implication or by operation of law. Recipient accepts all risks 
// of use.
//

//
// @file ram-debugger.cpp
// @brief RAM Debugger Application
//
// @author Angshuman Parashar
//

import FIFO::*;
import FIFOF::*;
import Vector::*;
import LFSR::*;

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/ddr_sdram_device.bsh"
`include "awb/provides/low_level_platform_interface.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/connected_application.bsh"

`include "awb/rrr/server_stub_RAM_DEBUGGER.bsh"

// types

typedef enum
{
    STATE_idle,
    STATE_running,
    STATE_doReads,
    STATE_calibrating
}
STATE
    deriving (Bits, Eq);

// mkApplication

module [CONNECTED_MODULE] mkConnectedApplication ();

    let ram <- mkLocalMemDDRConnection();

    Reg#(STATE) state <- mkReg(STATE_idle);

    // instantiate stubs
    ServerStub_RAM_DEBUGGER serverStub <- mkServerStub_RAM_DEBUGGER();

    Reg#(Bit#(48)) curCycle <- mkReg(0);
    (* no_implicit_conditions *)
    (* fire_when_enabled *)
    rule updateCycle (True);
        curCycle <= curCycle + 1;
    endrule


    // receive the start request from software
    rule start_debug (state == STATE_idle);
        
        let param <- serverStub.acceptRequest_StartDebug();
        serverStub.sendResponse_StartDebug(0);
        state <= STATE_running;
        
    endrule
    
    //
    // Platform-specific debug code goes here.
    //

    //
    // Up to 32 read requests are buffered until a DoReads() request arrives.
    // This enables testing of DDR read calibration to ensure that pipelined
    // read requests work.
    //
    FIFOF#(Tuple2#(Bit#(TLog#(FPGA_DDR_BANKS)), Bit#(32))) readReqQ <- mkSizedFIFOF(valueOf(FPGA_DDR_BANKS) * 32);
    Vector#(FPGA_DDR_BANKS, FIFO#(FPGA_DDR_DUALEDGE_BEAT)) readRspQ <- replicateM(mkSizedFIFO(`DRAM_MIN_BURST * 32));

    rule accept_load_req (state == STATE_running);
        let req <- serverStub.acceptRequest_ReadReq();
        serverStub.sendResponse_ReadReq(0);

        readReqQ.enq(tuple2(truncate(req.bank), req.addr));
    endrule

    rule accept_load_doReads (state == STATE_running);
        let dummy <- serverStub.acceptRequest_DoReads();
        serverStub.sendResponse_DoReads(0);

        state <= STATE_doReads;
    endrule

    rule doReads (state == STATE_doReads);
        if (readReqQ.notEmpty())
        begin
            match {.bank, .addr} = readReqQ.first();
            ram[bank].readReq(truncate(addr));
            readReqQ.deq();
        end
        else
        begin
            state <= STATE_running;
        end
    endrule

    for (Integer bank = 0; bank < valueOf(FPGA_DDR_BANKS); bank = bank + 1)
    begin
        rule bufReads ((state == STATE_running) || (state == STATE_doReads));

            let data <- ram[bank].readRsp();
            readRspQ[bank].enq(data);

        endrule
    end
    
    rule accept_load_rsp (state == STATE_running);
        let bank <- serverStub.acceptRequest_ReadRsp();

        Vector#(8, Bit#(64)) data = unpack(resize(readRspQ[bank].first()));
        readRspQ[bank].deq();

        serverStub.sendResponse_ReadRsp(data[7], data[6], data[5], data[4],
                                        data[3], data[2], data[1], data[0]);
    endrule


    rule accept_write_req (state == STATE_running);
        let req <- serverStub.acceptRequest_WriteReq();        
        serverStub.sendResponse_WriteReq(0);

        ram[req.bank].writeReq(truncate(req.addr));
    endrule
    
    rule accept_write_data (state == STATE_running);
        let req <- serverStub.acceptRequest_WriteData();
        let data = { req.data7, req.data6, req.data5, req.data4,
                     req.data3, req.data2, req.data1, req.data0 };

        ram[req.bank].writeData(resize(data), resize(req.mask));
        serverStub.sendResponse_WriteData(0);
    endrule
    

    //
    // read_latency rules are useful for calibrating the optimal size of
    // the controller's read response buffer size.  The buffer must be large
    // enough to hold responses from all pending read requests in the RAM's
    // read pipeline.
    //

    Reg#(FPGA_DDR_ADDRESS) calAddr <- mkRegU();
    Reg#(Bit#(48)) calStartCycle <- mkRegU();
    Reg#(Bit#(32)) calReads <- mkRegU();
    Reg#(Maybe#(Bit#(48))) calFirstRespCycle <- mkRegU();
    Reg#(Bit#(32)) calReqCnt <- mkRegU();
    Reg#(Bit#(32)) calRespCnt <- mkRegU();
    Reg#(Bool) calRandomize <- mkRegU();
    LFSR#(Bit#(32)) lfsr <- mkLFSR_32(); 
    FIFO#(Bit#(48)) latencyFIFO <- mkSizedBRAMFIFO(2048); //Make this big in case we have a lot of inter-fpga latency.
    Reg#(Bit#(48)) totalLatency <- mkReg(0);
    Reg#(Bit#(TAdd#(1, TLog#(FPGA_DDR_BURST_LENGTH)))) burstCnt <- mkReg(0);

    rule accept_read_latency (state == STATE_running);
        let cal <- serverStub.acceptRequest_ReadLatency();
        ram[0].setMaxReads(truncate(cal.maxOutstanding));

        state <= STATE_calibrating;
        calAddr <= 0;
        calStartCycle <= curCycle;
        calReads <= cal.nReads;
        calFirstRespCycle <= tagged Invalid;
        calReqCnt <= 0;
        calRespCnt <= 0;
        lfsr.seed(zeroExtend(cal.randomize));
        calRandomize <= cal.randomize > 0; 
        totalLatency <= 0;
    endrule

    rule read_latency_req ((state == STATE_calibrating) &&
                           (calReqCnt < calReads));
        let randomizer = (calRandomize) ? {lfsr.value,lfsr.value} : 0;
        ram[0].readReq(calAddr ^ truncate(randomizer));
        calAddr <= calAddr + fromInteger(valueOf(TMul#(FPGA_DDR_BURST_LENGTH, TDiv#(FPGA_DDR_DUALEDGE_BEAT_SZ, FPGA_DDR_WORD_SZ))));
        calReqCnt <= calReqCnt + 1;
        latencyFIFO.enq(curCycle);
    endrule

    rule read_latency_resp (state == STATE_calibrating);
        let data  <- ram[0].readRsp();

        // We expect some number of bursts, so we only dequeue when the op is 
        // complete
        if(burstCnt + 1 == fromInteger(valueOf(FPGA_DDR_BURST_LENGTH)))
        begin
            totalLatency <= totalLatency + (curCycle - latencyFIFO.first);
            latencyFIFO.deq;
            burstCnt <= 0;
        end 
        else
        begin
            burstCnt <= burstCnt + 1;
        end

        if (! isValid(calFirstRespCycle))
        begin
            calFirstRespCycle <= tagged Valid curCycle;
        end

        if (calRespCnt + 1 == (calReads * fromInteger(valueOf(FPGA_DDR_BURST_LENGTH))))
        begin
            let first_read_latency = validValue(calFirstRespCycle) - calStartCycle;
            serverStub.sendResponse_ReadLatency(zeroExtend(first_read_latency),
                                                zeroExtend(totalLatency + (curCycle - latencyFIFO.first)),
                                                zeroExtend(curCycle - calStartCycle));
            
            state <= STATE_running;
        end

        calRespCnt <= calRespCnt + 1;
    endrule

endmodule


//
// DRAM is accessed via soft connections.  Wrap the soft connections in a
// method interface.  The methods simply forward requests to the corresponding
// soft connections.
//
interface LOCAL_MEM_DDR_BANK;
    method Action readReq(FPGA_DDR_ADDRESS addr);
    method ActionValue#(FPGA_DDR_DUALEDGE_BEAT) readRsp();

    method Action writeReq(FPGA_DDR_ADDRESS addr);
    method Action writeData(FPGA_DDR_DUALEDGE_BEAT data, FPGA_DDR_DUALEDGE_BEAT_MASK mask);

    method Action setMaxReads(Bit#(TLog#(TAdd#(`DRAM_MAX_OUTSTANDING_READS, 1))) m);
endinterface

typedef Vector#(FPGA_DDR_BANKS, LOCAL_MEM_DDR_BANK) LOCAL_MEM_DDR;


module [CONNECTED_MODULE] mkLocalMemDDRConnection
    // Interface:
    (LOCAL_MEM_DDR);

    LOCAL_MEM_DDR banks <- genWithM(mkLocalMemDDRBankConnection);
    return banks;
endmodule


module [CONNECTED_MODULE] mkLocalMemDDRBankConnection#(Integer bankIdx)
    // Interface:
    (LOCAL_MEM_DDR_BANK);

    String ddrName = "DRAM_Bank" + integerToString(bankIdx) + "_";

    CONNECTION_SEND#(FPGA_DDR_REQUEST) commandQ <-
        mkConnectionSend(ddrName + "command");

    CONNECTION_RECV#(FPGA_DDR_DUALEDGE_BEAT) readRspQ <-
        mkConnectionRecv(ddrName + "readResponse");

    CONNECTION_SEND#(Tuple2#(FPGA_DDR_DUALEDGE_BEAT, FPGA_DDR_DUALEDGE_BEAT_MASK)) writeDataQ <-
        mkConnectionSend(ddrName + "writeData");

    CONNECTION_SEND#(Bit#(TLog#(TAdd#(`DRAM_MAX_OUTSTANDING_READS, 1))))
        maxReadsConnection <- mkConnectionSend(ddrName + "setMaxReads");

    method Action readReq(FPGA_DDR_ADDRESS addr);
        commandQ.send(tagged DRAM_READ addr);
    endmethod

    method ActionValue#(FPGA_DDR_DUALEDGE_BEAT) readRsp();
        let d = readRspQ.receive();
        readRspQ.deq();

        return d;
    endmethod

    method Action writeReq(FPGA_DDR_ADDRESS addr);
        commandQ.send(tagged DRAM_WRITE addr);
    endmethod

    method Action writeData(FPGA_DDR_DUALEDGE_BEAT data, FPGA_DDR_DUALEDGE_BEAT_MASK mask);
        writeDataQ.send(tuple2(data, mask));
    endmethod

    method Action setMaxReads(Bit#(TLog#(TAdd#(`DRAM_MAX_OUTSTANDING_READS, 1))) m);
        maxReadsConnection.send(m);
    endmethod
endmodule
