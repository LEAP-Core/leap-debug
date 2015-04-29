import Clocks::*;

(*synthesize*)
module mkGatedClockTest (ReadOnly#(Bit#(64)));

    let fastClock   <- exposeCurrentClock();

    Reg#(Bit#(1)) counter <- mkReg(0);
    let mediumClock <- mkGatedClockFromCC(True);
    CrossingReg#(Bit#(64)) regMedium <- mkNullCrossingReg(fastClock, 0, clocked_by mediumClock.new_clk);

    rule countUp;
        counter <= counter + 1;
        mediumClock.setGateCond(counter == 0);
    endrule  

    rule incrementMedium;
        regMedium <= regMedium + 2;
    endrule

    method Bit#(64) _read;
        return regMedium.crossed();
    endmethod
endmodule
