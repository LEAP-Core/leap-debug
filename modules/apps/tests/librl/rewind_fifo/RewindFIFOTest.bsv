`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/soft_connections.bsh"

import FIFO::*;
import StmtFSM::*;
import LFSR::*;

typedef 1024 MaxEntries;

//Use the commit fifo to replicate the magic stream !

module [CONNECTED_MODULE] mkHWOnlyApplication(Empty);

    // required for build tree compilation.
    STDIO#(Bit#(8))  stdio08 <- mkStdIO();

    Reg#(Bit#(16)) counter <- mkReg(0);
    Reg#(Bit#(16)) outputCount <- mkReg(0);

    Reg#(Bool) shouldRewind <- mkReg(False); 
    LFSR#(Bit#(8)) lfsr <- mkLFSR_8();
    Reg#(Bit#(8)) rewindCounter <- mkReg(25);

    RewindFIFOVariableCommitLevel#(Bit#(16),MaxEntries) rewindFIFO <- mkRewindFIFOVariableCommitLevel();
    CommitFIFOLevel#(Bit#(16),MaxEntries) commitFIFO <- mkCommitFIFOLevel();
    FIFO#(Bit#(16)) expectedFIFO <- mkSizedFIFO(valueof(MaxEntries));
  
    rule enqValues;
        rewindFIFO.enq(counter);
        expectedFIFO.enq(counter);
        counter <= counter + 1;
    endrule

    rule driveTest (rewindCounter - 1 == 0);   
        rewindCounter <= lfsr.value;
        shouldRewind <= !shouldRewind;
        lfsr.next;

        if(shouldRewind)
        begin 
            $display("Aborting");
            rewindFIFO.rewind();
            commitFIFO.abort();
        end
        else 
        begin
            $display("Committing");
            rewindFIFO.commit(tagged Invalid);
            commitFIFO.commit();
        end

        rewindFIFO.deq;
        commitFIFO.enq(rewindFIFO.first);
    endrule

    rule connectFIFO(rewindCounter-1 != 0);
        rewindCounter <= rewindCounter - 1;
        rewindFIFO.deq;
        commitFIFO.enq(rewindFIFO.first);
        $display("Sending %h", rewindFIFO.first);
    endrule

    rule checkResults;
        expectedFIFO.deq;
        commitFIFO.deq;
  
        if(expectedFIFO.first != commitFIFO.first)
        begin
            $display("Error: Expected %h, Commit %h", expectedFIFO.first, commitFIFO.first);
            $finish;
        end

        outputCount <= outputCount + 1;
        if(outputCount + 1 == 0) 
        begin
            $display("Pass");
            $finish;
        end
    endrule


endmodule
