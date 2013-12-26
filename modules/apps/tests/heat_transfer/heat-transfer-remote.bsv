//
// Copyright (C) 2013 MIT
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
import DefaultValue::*;

`include "asim/provides/librl_bsv.bsh"

`include "asim/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "asim/provides/mem_services.bsh"
`include "asim/provides/common_services.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "asim/provides/coherent_scratchpad_memory_service.bsh"
`include "asim/provides/heat_transfer_common_params.bsh"
`include "awb/provides/heat_transfer_common.bsh"

`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/PARAMS_HEAT_TRANSFER_COMMON.bsh"

//
// Implement a heat transfer test
//
module [CONNECTED_MODULE] mkHeatTransferTestRemote ()
    provisos (Bits#(MEM_ADDRESS, t_MEM_ADDR_SZ),
              Bits#(TEST_DATA, t_MEM_DATA_SZ));

    if (valueOf(N_REMOTE_ENGINES)>0)
    begin
        //
        // Allocate coherent scratchpads for heat engines
        //
        COH_SCRATCH_CONFIG conf = defaultValue;
        conf.cacheMode = (`HEAT_TRANSFER_TEST_PVT_CACHE_ENABLE != 0) ? COH_SCRATCH_CACHED : COH_SCRATCH_UNCACHED;
        
        Vector#(N_REMOTE_ENGINES, DEBUG_FILE) debugLogMs = newVector();
        Vector#(N_REMOTE_ENGINES, DEBUG_FILE) debugLogEs = newVector();
        Vector#(N_REMOTE_ENGINES, MEMORY_WITH_FENCE_IFC#(MEM_ADDRESS, TEST_DATA)) memories = newVector();
        Vector#(N_REMOTE_ENGINES, HEAT_ENGINE_IFC#(MEM_ADDRESS)) engines = newVector();

        for(Integer p = 0; p < valueOf(N_REMOTE_ENGINES); p = p + 1)
        begin
            debugLogMs[p] <- mkDebugFile("heat_engine_memory_" + integerToString(p + valueOf(N_LOCAL_ENGINES)) + ".out");
            debugLogEs[p] <- mkDebugFile("heat_engine_" + integerToString(p + valueOf(N_LOCAL_ENGINES)) + ".out");
            memories[p] <- mkDebugCoherentScratchpadClient(`VDEV_SCRATCH_HEAT_DATA, p + valueOf(N_LOCAL_ENGINES), conf, debugLogMs[p]);
            engines[p] <- mkHeatEngine(memories[p], debugLogEs[p], False);
        end

        DEBUG_FILE debugLog <- mkDebugFile("heat_transfer_test_remote.out");

        Reg#(Bit#(5))  bidX               <- mkReg(0);
        Reg#(Bit#(5))  bidY               <- mkReg(0);
        Reg#(Bit#(10)) engineID           <- mkReg(0);
        Reg#(Bool)     blockIdInitDone    <- mkReg(False);
  
        rule blockIdInit (!blockIdInitDone);
            if (engineID >= fromInteger(valueOf(N_LOCAL_ENGINES)))
            begin
                MEM_ADDRESS addr_x = unpack(zeroExtend(bidX) * fromInteger(valueOf(N_COLS_PER_ENGINE)));
                MEM_ADDRESS addr_y = unpack(zeroExtend(bidY) * fromInteger(valueOf(N_ROWS_PER_ENGINE)));
                engines[resize(engineID - fromInteger(valueOf(N_LOCAL_ENGINES)))].setAddrX(addr_x);
                engines[resize(engineID - fromInteger(valueOf(N_LOCAL_ENGINES)))].setAddrY(addr_y);
                debugLog.record($format("blockIdInit: engineID: %2d, addrX: 0x%x, addrY: 0x%x", engineID, addr_x, addr_y));
            end
            if (engineID == fromInteger(valueOf(N_TOTAL_ENGINES)-1))
            begin
                blockIdInitDone <= True;
            end
            else if (bidX == fromInteger(valueOf(N_X_ENGINES)-1))
            begin
                bidX <= 0;
                bidY <= bidY + 1;
            end
            else
            begin
                bidX <= bidX + 1;
            end
            engineID <= engineID + 1;
        endrule

    end

endmodule
