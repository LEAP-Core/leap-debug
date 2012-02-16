//
// Copyright (C) 2008 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

import Vector::*;
import List::*;
import LFSR::*;

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

typedef enum 
{
    STATE_start,
    STATE_req_filenames,
    STATE_open_files,
    STATE_write_files,
    STATE_delete_strings,
    STATE_close_files,

    STATE_frw_open_files_req,
    STATE_frw_open_files_rsp,
    STATE_frw_rw_files,
    STATE_frw_close_files,

    STATE_sync,
    STATE_exit,
    STATE_finish
} 
STATE deriving (Bits, Eq);


module [CONNECTED_MODULE] mkSystem ();

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    Integer ioSizeMap[4] = { 8, 16, 32, 64 };

    STDIO#(Bit#(8))  stdio08 <- mkStdIO();
    STDIO#(Bit#(16)) stdio16 <- mkStdIO();
    STDIO#(Bit#(32)) stdio32 <- mkStdIO();
    STDIO#(Bit#(64)) stdio64 <- mkStdIO();

    STDIO#(Bit#(32)) stdiop  <- mkStdIO();

    Reg#(STATE) state <- mkReg(STATE_start);

    rule start (state == STATE_start);
        linkStarterStartRun.deq();
        state <= STATE_req_filenames;
    endrule


    //
    // Construct file names (tests sprintf)
    //
    let filename <- getGlobalStringUID("outfile_%02d");
    rule reqFilenames (state == STATE_req_filenames);
        stdio08.sprintf_req(filename, list1(8));
        stdio16.sprintf_req(filename, list1(16));
        stdio32.sprintf_req(filename, list1(32));
        stdio64.sprintf_req(filename, list1(64));

        state <= STATE_open_files;
    endrule


    //
    // Open the 4 files, one for each size of StdIO node supported.
    //
    let fmode <- getGlobalStringUID("w+");
    Reg#(GLOBAL_STRING_UID) fname32 <- mkRegU();
    Reg#(GLOBAL_STRING_UID) fname64 <- mkRegU();
    let pipe32 <- getGlobalStringUID("tr a-zA-Z n-za-mN-ZA-M > outfile_pipe32");
    rule openFiles (state == STATE_open_files);
        let fn08 <- stdio08.sprintf_rsp();
        let fn16 <- stdio16.sprintf_rsp();
        let fn32 <- stdio32.sprintf_rsp();
        let fn64 <- stdio64.sprintf_rsp();

        stdio08.fopen_req(fn08, fmode);
        stdio16.fopen_req(fn16, fmode);
        stdio32.fopen_req(fn32, fmode);
        stdio64.fopen_req(fn64, fmode);

        stdiop.popen_req(pipe32, False);

        fname32 <= fn32;
        fname64 <= fn64;
        state <= STATE_write_files;
    endrule


    //
    // Write a value to each file.
    //
    let fmt0 <- getGlobalStringUID("Hello world: %d %d %d\n");
    let fmt1 <- getGlobalStringUID("File (%d) named: %s\n");
    let fmt2 <- getGlobalStringUID("Hello world: %d %d %d %d %d %d %d %d\n");
    Reg#(Vector#(5, STDIO_FILE)) fHandle <- mkRegU();
    rule writeFiles (state == STATE_write_files);
        Vector#(5, STDIO_FILE) f = newVector();
        f[0] <- stdio08.fopen_rsp();
        f[1] <- stdio16.fopen_rsp();
        f[2] <- stdio32.fopen_rsp();
        f[3] <- stdio64.fopen_rsp();

        f[4] <- stdiop.popen_rsp();

        fHandle <= f;

        stdio08.fprintf(f[0], fmt0, list3(25, 255, 142));
        stdio16.fwrite(f[1], list5('hbeef, 241, 182, 'hdead, 'h3210));
        stdio32.fprintf(f[2], fmt1, list2(32, fname32));
        stdio64.fprintf(f[3], fmt1, list2(64, zeroExtend(fname64)));

        stdiop.fprintf(f[4], fmt2, list8(1, 2, 3, 4, 5, 6, 7, 8));

        state <= STATE_delete_strings;
    endrule


    //
    // Release some strings used to create the file names.
    //
    rule deleteStrings (state == STATE_delete_strings);
        stdio32.string_delete(fname32);
        stdio64.string_delete(fname64);

        state <= STATE_close_files;
    endrule


    //
    // Close the files.
    //
    rule closeFiles (state == STATE_close_files);
        stdio08.fclose(fHandle[0]);
        stdio16.fclose(fHandle[1]);
        stdio32.fclose(fHandle[2]);
        stdio64.fclose(fHandle[3]);

        stdiop.fclose(fHandle[4]);

        state <= STATE_frw_open_files_req;
    endrule


    // ====================================================================
    //
    //   This section tests fread/fwrite by writing random values to
    //   files and verifying that they can be read back correctly.
    //
    // ====================================================================

    // Source of random write data
    LFSR#(Bit#(8))  lfsr08 <- mkLFSR();
    LFSR#(Bit#(16)) lfsr16 <- mkLFSR();
    LFSR#(Bit#(32)) lfsr32 <- mkLFSR();
    LFSR#(Bit#(64)) lfsr64 <- mkLFSR();

    // Output file names
    Vector#(4, GLOBAL_STRING_UID) frw_fn = newVector();
    frw_fn[0] <- getGlobalStringUID("outfile_frw_08");
    frw_fn[1] <- getGlobalStringUID("outfile_frw_16");
    frw_fn[2] <- getGlobalStringUID("outfile_frw_32");
    frw_fn[3] <- getGlobalStringUID("outfile_frw_64");

    //
    // Open the output files.
    //
    rule frwOpenFilesReq (state == STATE_frw_open_files_req);
        stdio08.fopen_req(frw_fn[0], fmode);
        stdio16.fopen_req(frw_fn[1], fmode);
        stdio32.fopen_req(frw_fn[2], fmode);
        stdio64.fopen_req(frw_fn[3], fmode);

        state <= STATE_frw_open_files_rsp;
    endrule


    //
    // Receive file descriptors and begin the fread/fwrite testing.
    //
    let frwStartMsg <- getGlobalStringUID("Starting fwrite/fread (size %d) tests...\n");

    rule frwOpenFilesRsp (state == STATE_frw_open_files_rsp);
        Vector#(5, STDIO_FILE) f = newVector();
        f[0] <- stdio08.fopen_rsp();
        f[1] <- stdio16.fopen_rsp();
        f[2] <- stdio32.fopen_rsp();
        f[3] <- stdio64.fopen_rsp();

        fHandle <= f;

        lfsr08.seed(1);
        lfsr16.seed(1);
        lfsr32.seed(1);
        lfsr64.seed(1);

        stdio08.printf(frwStartMsg, list1(8));
        stdio16.printf(frwStartMsg, list1(16));
        stdio32.printf(frwStartMsg, list1(32));
        stdio64.printf(frwStartMsg, list1(64));

        state <= STATE_frw_rw_files;
    endrule

    //
    // fwrite/fread testing proceeds independently for each of the 4 StdIO
    // node sizes.  Multiple file sizes are written, using a separate pass
    // for each file size.  Multiple sizes are needed to test for edge
    // conditions in the software-side detection of end-of-file.
    //

    // Base length of files.  True length is frw_fileLen + frw_pass.
    let frw_fileLen = 2500;
    Vector#(4, Reg#(Bit#(4))) frw_pass <- replicateM(mkReg(1));
    Vector#(4, Reg#(Bit#(16))) frw_writeCnt <- replicateM(mkReg(frw_fileLen + 1));
    Vector#(4, Reg#(Bit#(16))) frw_readCnt <- replicateM(mkReg(0));
    Vector#(4, Reg#(Bool)) frw_doReads <- replicateM(mkReg(False));
    Vector#(4, Reg#(Bool)) frw_eof <- replicateM(mkReg(False));
    Vector#(4, Reg#(Bool)) frw_done <- replicateM(mkReg(False));
    Vector#(4, Reg#(Bool)) frw_error <- replicateM(mkReg(False));

    let donePass <- getGlobalStringUID("Finished fread%02d pass %d PASS\n");
    let doneError <- getGlobalStringUID("Finished fread%02d pass %d READ VALUE ERROR\n");
    let doneLen <- getGlobalStringUID("Finished fread%02d pass %d INCORRECT FILE LENGTH ERROR\n");

    // Random number generators for read request sizes
    Vector#(4, LFSR#(Bit#(5))) readRandomSize <- replicateM(mkLFSR());


    //
    // frwWriteReadRules returns the fules for a single StdIO node instance.
    //
    function Rules frwWriteReadRules(STDIO#(Bit#(n)) stdio,
                                     LFSR#(Bit#(n)) lfsr,
                                     Integer i);
        return
          (rules
            //
            // Write frw_fileLen + frw_pass elements to the output file.
            //
            rule frwWriteFiles (state == STATE_frw_rw_files && ! frw_doReads[i]);
                if (frw_writeCnt[i] != 0)
                begin
                    stdio.fwrite(fHandle[i], list1(truncate(lfsr.value())));
                    lfsr.next();
                    frw_writeCnt[i] <= frw_writeCnt[i] - 1;
                end
                else
                begin
                    // Done with writes.  Rewind to the beginning of the file
                    // and read the data back.
                    stdio.rewind(fHandle[i]);
                    lfsr.seed(zeroExtendNP(frw_pass[i]));

                    frw_doReads[i] <= True;
                end
            endrule


            //
            // Request reads from the file.
            //
            rule frwFreadReq ((state == STATE_frw_rw_files) &&
                              frw_doReads[i] &&
                              ! frw_eof[i]);
                // Vary read request lengths to test software edge cases
                stdio.fread_req(fHandle[i], max(zeroExtendNP(readRandomSize[i].value()), 1));
                readRandomSize[i].next();
            endrule

            //
            // Receive reads from the file.  Check both the values and the
            // number of elements received.
            //
            rule frwFreadRsp ((state == STATE_frw_rw_files) &&
                              frw_doReads[i] &&
                              ! frw_eof[i]);
                let rsp <- stdio.fread_rsp();
                if (rsp matches tagged Valid .v)
                begin
                    // New value.  Does it match the expected value?
                    frw_readCnt[i] <= frw_readCnt[i] + 1;
                    if (v != lfsr.value)
                    begin
                        frw_error[i] <= True;
                    end

                    lfsr.next();
                end
                else
                begin
                    // End of file
                    frw_eof[i] <= True;

                    let status = donePass;
                    if (frw_error[i])
                        status = doneError;
                    else if (frw_readCnt[i] != (fromInteger(frw_fileLen) + zeroExtend(frw_pass[i])))
                        status = doneLen;

                    stdio.printf(status, list2(8 << i, zeroExtendNP(frw_pass[i])));
                end
            endrule


            //
            // End of file received.  Sink all outstanding read requests.
            // Once EOF is reached, only one read response will be returned
            // for each read request, independent of the number of elements
            // requested.
            //
            rule frwFreadSink ((state == STATE_frw_rw_files) &&
                               frw_doReads[i] &&
                               frw_eof[i] &&
                               (stdio.fread_numInFlight != 0));
                let rsp <- stdio.fread_rsp();
            endrule


            //
            // Done with read.  Either start another pass or finish.
            //
            rule frwFreadDone ((state == STATE_frw_rw_files) &&
                               frw_doReads[i] &&
                               frw_eof[i] &&
                               (stdio.fread_numInFlight == 0) &&
                               ! frw_done[i]);

                //
                // Multiple passes with different file lengths test edge
                // conditions for marshalling groups and signalling EOF.
                //
                if (frw_pass[i] == 9)
                begin
                    // Done with tests
                    frw_done[i] <= True;
                end
                else
                begin
                    // Increment pass and start the test again.
                    stdio.rewind(fHandle[i]);
                    // Use a different starting seed
                    lfsr.seed(zeroExtendNP(frw_pass[i] + 1));

                    // Go back to the head of the fwrite then fread pipeline
                    frw_writeCnt[i] <= frw_fileLen + zeroExtend(frw_pass[i] + 1);
                    frw_readCnt[i] <= 0;
                    frw_doReads[i] <= False;
                    frw_eof[i] <= False;
                    frw_error[i] <= False;

                    frw_pass[i] <= frw_pass[i] + 1;
                end
            endrule

           endrules);
    endfunction

    addRules(frwWriteReadRules(stdio08, lfsr08, 0));
    addRules(frwWriteReadRules(stdio16, lfsr16, 1));
    addRules(frwWriteReadRules(stdio32, lfsr32, 2));
    addRules(frwWriteReadRules(stdio64, lfsr64, 3));


    //
    // Done with tests for all file sizes?
    //
    rule frwDone ((state == STATE_frw_rw_files) &&
                  frw_done[0] && frw_done[1] && frw_done[2] && frw_done[3]);
        state <= STATE_frw_close_files;
    endrule


    rule frwCloseFiles (state == STATE_frw_close_files);
        stdio08.fclose(fHandle[0]);
        stdio16.fclose(fHandle[1]);
        stdio32.fclose(fHandle[2]);
        stdio64.fclose(fHandle[3]);

        state <= STATE_sync;
    endrule


    rule sync (state == STATE_sync);
        stdio08.sync_req();
        stdio16.sync_req();
        stdio32.sync_req();
        stdio64.sync_req();

        stdiop.sync_req();

        state <= STATE_exit;
    endrule


    rule exit (state == STATE_exit);
        stdio08.sync_rsp();
        stdio16.sync_rsp();
        stdio32.sync_rsp();
        stdio64.sync_rsp();

        stdiop.sync_rsp();

        linkStarterFinishRun.send(0);
        state <= STATE_finish;
    endrule


    rule finish (state == STATE_finish);
        noAction;
    endrule

endmodule
