//
// INTEL CONFIDENTIAL
// Copyright (c) 2015 Intel Corp.  Recipient is granted a non-sublicensable 
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


`include "asim/provides/virtual_platform.bsh"
`include "asim/provides/virtual_devices.bsh"
`include "asim/provides/physical_platform.bsh"
`include "asim/provides/low_level_platform_interface.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/dict/PARAMS_CONNECTED_APPLICATION.bsh"

`include "asim/rrr/service_ids.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_0.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_1.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_2.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_3.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_4.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_5.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_6.bsh"
`include "asim/rrr/client_stub_RRRTORTURE_7.bsh"

import Vector::*;
import FIFO::*;
import FIFOF::*;

`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/librl_bsv_storage.bsh"
`include "asim/provides/fpga_components.bsh"

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/common_services.bsh"

// types
typedef Bit#(64) PAYLOAD;

// mkApplication
module [CONNECTED_MODULE] mkConnectedApplication ();

    STDIO#(Bit#(64)) stdio <- mkStdIO();
    let msgError          <- getGlobalStringUID("RRR-test: ERROR: unexpected read val channel %d (0x%08llx) != (0x%08llx)\n"); 
    let msgGlobalStatus   <- getGlobalStringUID("RRR-test: sent %d values\n");                                                    
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    // Dynamic parameters.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();

    Param#(64) totalTransactions <- mkDynamicParameter(`PARAMS_CONNECTED_APPLICATION_RRRTORTURE_TOTAL_TRANSACTIONS, paramNode);

    // instantiate stubs
    ClientStub_RRRTORTURE_0 clientStub0 <- mkClientStub_RRRTORTURE_0();
    ClientStub_RRRTORTURE_1 clientStub1 <- mkClientStub_RRRTORTURE_1();
    ClientStub_RRRTORTURE_2 clientStub2 <- mkClientStub_RRRTORTURE_2();
    ClientStub_RRRTORTURE_3 clientStub3 <- mkClientStub_RRRTORTURE_3();
    ClientStub_RRRTORTURE_4 clientStub4 <- mkClientStub_RRRTORTURE_4();
    ClientStub_RRRTORTURE_5 clientStub5 <- mkClientStub_RRRTORTURE_5();
    ClientStub_RRRTORTURE_6 clientStub6 <- mkClientStub_RRRTORTURE_6();
    ClientStub_RRRTORTURE_7 clientStub7 <- mkClientStub_RRRTORTURE_7();

    Vector#(8, Reg#(Bit#(16))) counters <- replicateM(mkReg(0));
    Vector#(8, FIFOF#(Bit#(16))) storageFIFOs <- replicateM(mkSizedBRAMFIFOF(1024));
    Reg#(Bit#(64)) valuesSent <- mkReg(0);

    rule reportValues(valuesSent[24:0] == 0);
        stdio.printf(msgGlobalStatus, list1(valuesSent));        
    endrule

    rule terminate(valuesSent > totalTransactions);
        $display("Sending Finish Run");
        linkStarterFinishRun.send(0);
    endrule


    // Client 0
    rule do_f2h_twoway_test_req0;        
        clientStub0.makeRequest_F2HTwoWayMsg0({counters[0]+1,0,counters[0],counters[0]-1});
        counters[0] <= counters[0] + 1;
        storageFIFOs[0].enq(counters[0]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp0;
        
        PAYLOAD dummy <- clientStub0.getResponse_F2HTwoWayMsg0();
        storageFIFOs[0].deq();
        if(dummy != {storageFIFOs[0].first()+1,0,storageFIFOs[0].first(),storageFIFOs[0].first()-1})
        begin
            stdio.printf(msgError, list3(0,dummy,{storageFIFOs[0].first()+1,0,storageFIFOs[0].first(),storageFIFOs[0].first()-1}));
        end
    endrule

    // Client 1
    rule do_f2h_twoway_test_req1;        
        clientStub1.makeRequest_F2HTwoWayMsg1({counters[1]+1,1,counters[1],counters[1]-1});
        counters[1] <= counters[1] + 1;
        storageFIFOs[1].enq(counters[1]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp1;
        
        PAYLOAD dummy <- clientStub1.getResponse_F2HTwoWayMsg1();
        storageFIFOs[1].deq();
        if(dummy != {storageFIFOs[1].first()+1,1,storageFIFOs[1].first(),storageFIFOs[1].first()-1})
        begin
            stdio.printf(msgError, list3(1,dummy,{storageFIFOs[1].first()+1,1,storageFIFOs[1].first(),storageFIFOs[1].first()-1}));
        end
    endrule


    // Client 2
    rule do_f2h_twoway_test_req2;        
        clientStub2.makeRequest_F2HTwoWayMsg2({counters[2]+1,2,counters[2],counters[2]-1});
        counters[2] <= counters[2] + 1;
        storageFIFOs[2].enq(counters[2]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp2;
        
        PAYLOAD dummy <- clientStub2.getResponse_F2HTwoWayMsg2();
        storageFIFOs[2].deq();
        if(dummy != {storageFIFOs[2].first()+1,2,storageFIFOs[2].first(),storageFIFOs[2].first()-1})
        begin
            stdio.printf(msgError, list3(2,dummy,{storageFIFOs[2].first()+1,2,storageFIFOs[2].first(),storageFIFOs[2].first()-1}));
        end
    endrule
    

    // Client 3
    rule do_f2h_twoway_test_req3;        
        clientStub3.makeRequest_F2HTwoWayMsg3({counters[3]+1,3,counters[3],counters[3]-1});
        counters[3] <= counters[3] + 1;
        storageFIFOs[3].enq(counters[3]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp3;
        
        PAYLOAD dummy <- clientStub3.getResponse_F2HTwoWayMsg3();
        storageFIFOs[3].deq();
        if(dummy != {storageFIFOs[3].first()+1,3,storageFIFOs[3].first(),storageFIFOs[3].first()-1})
        begin
            stdio.printf(msgError, list3(3,dummy,{storageFIFOs[3].first()+1,3,storageFIFOs[3].first(),storageFIFOs[3].first()-1}));
        end
    endrule

    // Client 4
    rule do_f2h_twoway_test_req4;        
        clientStub4.makeRequest_F2HTwoWayMsg4({counters[4]+1,4,counters[4],counters[4]-1});
        counters[4] <= counters[4] + 1;
        storageFIFOs[4].enq(counters[4]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp4;
        
        PAYLOAD dummy <- clientStub4.getResponse_F2HTwoWayMsg4();
        storageFIFOs[4].deq();
        if(dummy != {storageFIFOs[4].first()+1,4,storageFIFOs[4].first(),storageFIFOs[4].first()-1})
        begin
            stdio.printf(msgError, list3(4,dummy,{storageFIFOs[4].first()+1,4,storageFIFOs[4].first(),storageFIFOs[4].first()-1}));
        end
    endrule

    // Client 5
    rule do_f2h_twoway_test_req5;        
        clientStub5.makeRequest_F2HTwoWayMsg5({counters[5]+1,5,counters[5],counters[5]-1});
        counters[5] <= counters[5] + 1;
        storageFIFOs[5].enq(counters[5]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp5;
        
        PAYLOAD dummy <- clientStub5.getResponse_F2HTwoWayMsg5();
        storageFIFOs[5].deq();
        if(dummy != {storageFIFOs[5].first()+1,5,storageFIFOs[5].first(),storageFIFOs[5].first()-1})
        begin
            stdio.printf(msgError, list3(5,dummy,{storageFIFOs[5].first()+1,5,storageFIFOs[5].first(),storageFIFOs[5].first()-1}));
        end
    endrule


    // Client 6
    rule do_f2h_twoway_test_req6;        
        clientStub6.makeRequest_F2HTwoWayMsg6({counters[6]+1,6,counters[6],counters[6]-1});
        counters[6] <= counters[6] + 1;
        storageFIFOs[6].enq(counters[6]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp6;
        
        PAYLOAD dummy <- clientStub6.getResponse_F2HTwoWayMsg6();
        storageFIFOs[6].deq();
        if(dummy != {storageFIFOs[6].first()+1,6,storageFIFOs[6].first(),storageFIFOs[6].first()-1})
        begin
            stdio.printf(msgError, list3(6,dummy,{storageFIFOs[6].first()+1,6,storageFIFOs[6].first(),storageFIFOs[6].first()-1}));
        end
    endrule

    // Client 7
    rule do_f2h_twoway_test_req7;        
        clientStub7.makeRequest_F2HTwoWayMsg7({counters[7]+1,7,counters[7],counters[7]-1});
        counters[7] <= counters[7] + 1;
        storageFIFOs[7].enq(counters[7]);
        valuesSent <= valuesSent + 1;
    endrule

    rule do_f2h_twoway_test_resp7;
        
        PAYLOAD dummy <- clientStub7.getResponse_F2HTwoWayMsg7();
        storageFIFOs[7].deq();
        if(dummy != {storageFIFOs[7].first()+1,7,storageFIFOs[7].first(),storageFIFOs[7].first()-1})
        begin
            stdio.printf(msgError, list3(7,dummy,{storageFIFOs[7].first()+1,7,storageFIFOs[7].first(),storageFIFOs[7].first()-1}));
        end
    endrule

endmodule
