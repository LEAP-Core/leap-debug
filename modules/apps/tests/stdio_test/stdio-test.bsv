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
    STATE_flush_files,
    STATE_close_files,
    STATE_sync,
    STATE_exit,
    STATE_finish
} 
STATE deriving (Bits, Eq);


module [CONNECTED_MODULE] mkSystem ();

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    STDIO#(Bit#(8))  stdio08 <- mkStdIO();
    STDIO#(Bit#(16)) stdio16 <- mkStdIO();
    STDIO#(Bit#(32)) stdio32 <- mkStdIO();
    STDIO#(Bit#(64)) stdio64 <- mkStdIO();

    Reg#(STATE) state <- mkReg(STATE_start);

    rule start (state == STATE_start);
        linkStarterStartRun.deq();
        state <= STATE_req_filenames;
    endrule


    let filename <- getGlobalStringUID("outfile_%02d");
    rule reqFilenames (state == STATE_req_filenames);
        stdio08.sprintf_req(filename, list1(8));
        stdio16.sprintf_req(filename, list1(16));
        stdio32.sprintf_req(filename, list1(32));
        stdio64.sprintf_req(filename, list1(64));

        state <= STATE_open_files;
    endrule


    let fmode <- getGlobalStringUID("w");
    Reg#(GLOBAL_STRING_UID) fname32 <- mkRegU();
    Reg#(GLOBAL_STRING_UID) fname64 <- mkRegU();
    rule openFiles (state == STATE_open_files);
        let fn08 <- stdio08.sprintf_rsp();
        let fn16 <- stdio16.sprintf_rsp();
        let fn32 <- stdio32.sprintf_rsp();
        let fn64 <- stdio64.sprintf_rsp();

        stdio08.fopen_req(fn08, fmode);
        stdio16.fopen_req(fn16, fmode);
        stdio32.fopen_req(fn32, fmode);
        stdio64.fopen_req(fn64, fmode);

        fname32 <= fn32;
        fname64 <= fn64;
        state <= STATE_write_files;
    endrule


    let fmt0 <- getGlobalStringUID("Hello world: %d %d\n");
    let fmt1 <- getGlobalStringUID("File (%d) named: %s\n");
    Reg#(Vector#(4, STDIO_FILE)) fHandle <- mkRegU();
    rule writeFiles (state == STATE_write_files);
        Vector#(4, STDIO_FILE) f = newVector();
        f[0] <- stdio08.fopen_rsp();
        f[1] <- stdio16.fopen_rsp();
        f[2] <- stdio32.fopen_rsp();
        f[3] <- stdio64.fopen_rsp();
        fHandle <= f;

        stdio08.fprintf(f[0], fmt0, list2(25, 255));
        stdio16.fprintf(f[1], fmt0, list2(16341, 241));
        stdio32.fprintf(f[2], fmt1, list2(32, fname32));
        stdio64.fprintf(f[3], fmt1, list2(64, zeroExtend(fname64)));

        state <= STATE_delete_strings;
    endrule


    rule deleteStrings (state == STATE_delete_strings);
        stdio32.sprintf_delete(fname32);
        stdio64.sprintf_delete(fname64);

        state <= STATE_flush_files;
    endrule


    rule flushFiles (state == STATE_flush_files);
        stdio08.fflush(fHandle[0]);
        stdio16.fflush(fHandle[1]);
        stdio32.fflush(fHandle[2]);
        stdio64.fflush(fHandle[3]);

        state <= STATE_close_files;
    endrule


    rule closeFiles (state == STATE_close_files);
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

        state <= STATE_exit;
    endrule


    rule exit (state == STATE_exit);
        stdio08.sync_rsp();
        stdio16.sync_rsp();
        stdio32.sync_rsp();
        stdio64.sync_rsp();

        linkStarterFinishRun.send(0);
        state <= STATE_finish;
    endrule


    rule finish (state == STATE_finish);
        noAction;
    endrule

endmodule
