import Clocks::*; 
import List::*;

`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/gating_test.bsh"


module [CONNECTED_MODULE] mkConnectedApplication ();

    STDIO#(Bit#(64)) stdio  <- mkStdIO();

    let msg <- getGlobalStringUID("Fast Clock: %d (%d), Medium Clock: %d(%d) Medium ModuleClock: %d(%d), Slow Clock: %d(%d)\n");
    
    Reg#(Bit#(32)) counter <- mkReg(0);

    let fastClock   <- exposeCurrentClock();
    let mediumClock <- mkGatedClockFromCC(True);
    let slowClock   <- mkGatedClockFromCC(True);
    
    rule countUp;
        counter <= counter + 1;
        mediumClock.setGateCond(counter[0]==0);
        slowClock.setGateCond(counter[1:0]==0);
    endrule  

    Reg#(Bit#(64))         regFast   <- mkReg(0);
    CrossingReg#(Bit#(64)) regMedium <- mkNullCrossingReg(fastClock, 0, clocked_by mediumClock.new_clk);
    CrossingReg#(Bit#(64)) regSlow   <- mkNullCrossingReg(fastClock, 0, clocked_by slowClock.new_clk);
    ReadOnly#(Bit#(64))    regModule <- mkGatedClockTest();

    Reg#(Bit#(64)) regFastLast   <- mkReg(0);
    Reg#(Bit#(64)) regMediumLast <- mkReg(0);
    Reg#(Bit#(64)) regSlowLast   <- mkReg(0);
    Reg#(Bit#(64)) regModuleLast   <- mkReg(0);
    
    rule printResults;
        stdio.printf(msg, List::map(zeroExtend,list8(regFast, regFast - regFastLast, 
                                regMedium.crossed(), regMedium.crossed() - regMediumLast, 
                                regModule, regModule - regModuleLast,
                                regSlow.crossed(), regSlow.crossed() - regSlowLast)));

        regFastLast <= regFast; 
        regMediumLast <= regMedium.crossed(); 
        regSlowLast <= regSlow.crossed(); 
        regModuleLast <= regModule; 
    endrule
    
    rule incrementFast;
        regFast <= regFast + 1;
    endrule

    rule incrementMedium;
        regMedium <= regMedium + 2;
    endrule

    rule incrementSlow;
        regSlow <= regSlow + 4;
    endrule

endmodule

