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

import ConfigReg::*;

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/ddr_sdram_device.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/dict/PARAMS_HARDWARE_SYSTEM.bsh"

// ========================================================================
//
// Copied from local-mem-ddr-common.bsv
// (In this test, local-mem-null is chosen to disable central cache so 
// some interfaces are missing)
//
// ========================================================================

// The DRAM driver breaks reads and writes into multi-cycle bursts.
typedef TMul#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT_SZ) DDR_BURST_DATA_SZ;
typedef Bit#(DDR_BURST_DATA_SZ) DDR_BURST_DATA;

// Compute index of the DDR words within a burst
typedef TMul#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_WORDS_PER_BEAT) DDR_WORDS_PER_BURST;
typedef TLog#(DDR_WORDS_PER_BURST) DDR_BURST_WORD_IDX_SZ;
typedef Bit#(DDR_BURST_WORD_IDX_SZ) DDR_BURST_WORD_IDX;

// Compute burst-aligned address sizes in DDR-space within a single bank
typedef TSub#(FPGA_DDR_ADDRESS_SZ, DDR_BURST_WORD_IDX_SZ) DDR_BURST_ADDRESS_SZ;
typedef Bit#(DDR_BURST_ADDRESS_SZ) DDR_BURST_ADDRESS;

// Bank index
typedef Bit#(TLog#(FPGA_DDR_BANKS)) DDR_BANK_IDX;

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

    String platformName <- getSynthesisBoundaryPlatform();
    String ddrName = "DRAM_Bank" + integerToString(bankIdx) + "_" + platformName + "_";

    CONNECTION_SEND#(FPGA_DDR_REQUEST) commandQ <-
        mkConnectionSend(ddrName + "command");

    CONNECTION_RECV#(FPGA_DDR_DUALEDGE_BEAT) readRspQ <-
        mkConnectionRecv(ddrName + "readResponse");

    CONNECTION_SEND#(Tuple2#(FPGA_DDR_DUALEDGE_BEAT, FPGA_DDR_DUALEDGE_BEAT_MASK)) writeDataQ <-
        mkConnectionSend(ddrName + "writeData");


`ifndef LOCAL_MEM_DDR_SLOW_MODEL_EN_Z
    
    // Dynamic parameters.
    PARAMETER_NODE paramNode  <- mkDynamicParameterNode();
    Param#(16) latencyParam   <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_LOCAL_MEM_DDR_MIN_LATENCY, paramNode);
    Param#(8) bandwidthParam  <- mkDynamicParameter(`PARAMS_HARDWARE_SYSTEM_LOCAL_MEM_DDR_BANDWIDTH_LIMIT, paramNode);
    
    FIFOF#(Bit#(64)) readReqCycleQ <- mkSizedFIFOF(valueOf(FPGA_DDR_MAX_OUTSTANDING_READS));
    Reg#(Bit#(64))   cycleCnt      <- mkReg(0);
    Reg#(Bit#(7))    reqCnt        <- mkConfigReg(0);
    Reg#(Bit#(7))    reqCntMax     <- mkRegU;
    Reg#(Bit#(16))   latencyMin    <- mkRegU;
    Reg#(Bool)       initialized   <- mkReg(False);
    PulseWire        requestEnW    <- mkPulseWire();
    PulseWire        responseEnW   <- mkPulseWire();

    Reg#(Bit#(TLog#(FPGA_DDR_BURST_LENGTH))) readBurstIdx <- mkReg(0);

    function Bool bandwidthFree() = (reqCnt <= reqCntMax);
    function Bool underMinlatency() = ((cycleCnt - readReqCycleQ.first()) < zeroExtend(latencyMin));
        
    (* fire_when_enabled *)
    rule countCycle(True);
        cycleCnt <= cycleCnt + 1;
    endrule
    
    (* fire_when_enabled *)
    rule doInit (!initialized);
        initialized <= True;
        reqCntMax   <= truncate(bandwidthParam -1);
        latencyMin  <= latencyParam;
    endrule

    (* fire_when_enabled *)
    rule updReqCnt (True);
        Bit#(7) cycle = truncate(cycleCnt);
        reqCnt <= (cycle == 0)? zeroExtend(pack(requestEnW)) : (reqCnt + zeroExtend(pack(requestEnW)));
    endrule
    
    (* fire_when_enabled *)
    rule deqReadReqQ (responseEnW);
        if (valueOf(FPGA_DDR_BURST_LENGTH) == 1)
        begin
            readReqCycleQ.deq();
        end
        else
        begin
            readBurstIdx <= readBurstIdx + 1;
            if (readBurstIdx == maxBound)
            begin
                readReqCycleQ.deq();
            end
        end
    endrule

    method Action readReq(FPGA_DDR_ADDRESS addr) if (initialized && bandwidthFree());
        commandQ.send(tagged DRAM_READ addr);
        readReqCycleQ.enq(cycleCnt);
        requestEnW.send();
    endmethod

    method ActionValue#(FPGA_DDR_DUALEDGE_BEAT) readRsp() if (initialized && !underMinlatency());
        let d = readRspQ.receive();
        readRspQ.deq();
        responseEnW.send();
        return d;
    endmethod

    method Action writeReq(FPGA_DDR_ADDRESS addr) if (initialized && bandwidthFree());
        commandQ.send(tagged DRAM_WRITE addr);
        requestEnW.send();
    endmethod

    method Action writeData(FPGA_DDR_DUALEDGE_BEAT data, FPGA_DDR_DUALEDGE_BEAT_MASK mask) if (initialized);
        writeDataQ.send(tuple2(data, mask));
    endmethod

`else

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

`endif

endmodule

