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
// @file platform-debugger.cpp
// @brief Platform Debugger Application
//
// @author Angshuman Parashar
//

import FIFO::*;
import FIFOF::*;
import Vector::*;

`include "asim/provides/virtual_platform.bsh"
`include "asim/provides/virtual_devices.bsh"
`include "asim/provides/physical_platform.bsh"
`include "asim/provides/ddr_sdram_device.bsh"
`include "asim/provides/low_level_platform_interface.bsh"

`include "asim/provides/hybrid_application.bsh"

`include "asim/rrr/server_stub_PLATFORM_DEBUGGER.bsh"

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

module mkApplication#(VIRTUAL_PLATFORM vp)();
    
    LowLevelPlatformInterface llpi    = vp.llpint;
    PHYSICAL_DRIVERS          drivers = llpi.physicalDrivers;
    let sram = drivers.ddrDriver;
    
    Reg#(STATE) state <- mkReg(STATE_idle);
    
    // instantiate stubs
    ServerStub_PLATFORM_DEBUGGER serverStub <- mkServerStub_PLATFORM_DEBUGGER(llpi.rrrServer);
    
    Reg#(Bit#(64)) curCycle <- mkReg(0);
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
    Vector#(FPGA_DDR_BANKS, FIFO#(FPGA_DDR_DUALEDGE_DATA)) readRspQ <- replicateM(mkSizedFIFO(`DRAM_MIN_BURST * 32));

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
            sram[bank].readReq(truncate(addr));
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

            let data <- sram[bank].readRsp();
            readRspQ[bank].enq(truncate(data));

        endrule
    end
    
    rule accept_load_rsp (state == STATE_running);

        let bank <- serverStub.acceptRequest_ReadRsp();

        Vector#(4, Bit#(64)) data = unpack(resize(readRspQ[bank].first()));
        readRspQ[bank].deq();

        serverStub.sendResponse_ReadRsp(data[3], data[2], data[1], data[0]);

    endrule


    rule accept_write_req (state == STATE_running);
        
        let req <- serverStub.acceptRequest_WriteReq();        
        serverStub.sendResponse_WriteReq(0);

        sram[req.bank].writeReq(truncate(req.addr));
        
    endrule
    
    rule accept_write_data (state == STATE_running);
        
        let req <- serverStub.acceptRequest_WriteData();
        let data = { req.data3, req.data2, req.data1, req.data0 };

        sram[req.bank].writeData(truncate(data), truncate(req.mask));
        serverStub.sendResponse_WriteData(0);
        
    endrule
    
    rule accept_status_check (True);
        
        let bank <- serverStub.acceptRequest_StatusCheck();
        serverStub.sendResponse_StatusCheck(sram[bank[0]].statusCheck());
        
    endrule
    

    //
    // read_latency rules are useful for calibrating the optimal size of
    // the controller's read response buffer size.  The buffer must be large
    // enough to hold responses from all pending read requests in the RAM's
    // read pipeline.
    //

    Reg#(FPGA_DDR_ADDRESS) calAddr <- mkRegU();
    Reg#(Bit#(64)) calStartCycle <- mkRegU();
    Reg#(Bit#(16)) calReads <- mkRegU();
    Reg#(Maybe#(Bit#(64))) calFirstRespCycle <- mkRegU();
    Reg#(Bit#(16)) calReqCnt <- mkRegU();
    Reg#(Bit#(16)) calRespCnt <- mkRegU();

    rule accept_read_latency (state == STATE_running);
        let cal <- serverStub.acceptRequest_ReadLatency();
        sram[0].setMaxReads(truncate(cal.maxOutstanding));

        state <= STATE_calibrating;
        calAddr <= 0;
        calStartCycle <= curCycle;
        calReads <= cal.nReads;
        calFirstRespCycle <= tagged Invalid;
        calReqCnt <= 0;
        calRespCnt <= 0;
    endrule

    rule read_latency_req ((state == STATE_calibrating) &&
                           (calReqCnt < calReads));
        sram[0].readReq(calAddr);
        calAddr <= calAddr + fromInteger(valueOf(TMul#(FPGA_DDR_BURST_LENGTH, TDiv#(FPGA_DDR_DUALEDGE_DATA_SZ, FPGA_DDR_WORD_SZ))));
        calReqCnt <= calReqCnt + 1;
    endrule

    (* descending_urgency = "accept_status_check, read_latency_resp" *)
    rule read_latency_resp (state == STATE_calibrating);
        let data  <- sram[0].readRsp();
        if (! isValid(calFirstRespCycle))
        begin
            calFirstRespCycle <= tagged Valid curCycle;
        end

        if (calRespCnt + 1 == (calReads * fromInteger(valueOf(FPGA_DDR_BURST_LENGTH))))
        begin
            let first_read_latency = validValue(calFirstRespCycle) - calStartCycle;
            let total_latency = curCycle - calStartCycle;
            serverStub.sendResponse_ReadLatency(truncate(first_read_latency),
                                                truncate(total_latency));
            
            state <= STATE_running;
        end

        calRespCnt <= calRespCnt + 1;
    endrule

endmodule
