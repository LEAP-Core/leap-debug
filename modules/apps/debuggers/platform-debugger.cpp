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

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <cmath>

#include "asim/syntax.h"
#include "asim/ioformat.h"
#include "asim/provides/hybrid_application.h"
#include "asim/provides/clocks_device.h"
#include "asim/provides/ddr_sdram_device.h"

using namespace std;

const char*  
getIdxName(const int idx)
{
    switch(idx)
    {
        case 0:  return "prim_device.ram1.enqueue_address_RDY()";
        case 1:  return "prim_device.ram1.enqueue_data_RDY()";
        case 2:  return "prim_device.ram1.dequeue_data_RDY()";
        case 3:  return "mergeReqQ.notEmpty()";
        case 4:  return "mergeReqQ.ports[0].notFull()";
        case 5:  return "mergeReqQ.ports[1].notFull()";
        case 6:  return "syncReadDataQ.notEmpty()";
        case 7:  return "syncReadDataQ.notFull()";
        case 8:  return "initDone";
        case 9:  return "phy reset asserted";
        case 10: return "syncRequestQ.notEmpty()";
        case 11: return "syncRequestQ.notFull()";
        case 12: return "syncWriteDataQ.notEmpty()";
        case 13: return "syncWriteDataQ.notFull()";
        case 14: return "writePending";
        case 15: return "readPending";
        case 16: return "nInflightReads.value() == 0";
        case 17: return "readBurstCnt == 0";
        case 18: return "writeBurstIdx == 0";
        case 19: return "state";
        default: return "unused";
    }
}

UINT64 
getBit(UINT64 bvec, int idx, UINT64 mask)
{
    return (bvec >> idx) & mask;
}

void
printRAMStatus(UINT64 status)
{
    cout << "RAM status:" << hex << status << dec << endl;
    for (int x = 0; x < 20; x++)
    {
        cout << "    [" << getIdxName(x) << "]: " << getBit(status, x, 1) << endl;
    }
}

void
printRAMStatusDiff(UINT64 new_status, UINT64 old_status)
{
    int any_change = 0;
    for (int x = 0; x < 20; x++)
    {
        UINT64 b_old = getBit(old_status, x, 1);
        UINT64 b_new = getBit(new_status, x, 1);
        if (b_old != b_new)
        {
            cout << "    [" << getIdxName(x) << "] Now: " <<  b_new << endl;
            any_change = 1;
        }
    }
    if (!any_change)
    {
        cout << "No RAM change." << endl;  
    }
}
// constructor
HYBRID_APPLICATION_CLASS::HYBRID_APPLICATION_CLASS(
    VIRTUAL_PLATFORM vp)
{
    clientStub = new PLATFORM_DEBUGGER_CLIENT_STUB_CLASS(NULL);
}

// destructor
HYBRID_APPLICATION_CLASS::~HYBRID_APPLICATION_CLASS()
{
    delete clientStub;
}

void
HYBRID_APPLICATION_CLASS::Init()
{
}

// main
void
HYBRID_APPLICATION_CLASS::Main()
{
    UINT64 sts, oldsts;
    UINT64 data;

    // Different memory styles have different minimum offsets This is
    // a combination of DRAM_MIN_BURST and DRAM_WORD_WIDTH.
    int MIN_IDX_OFFSET = DRAM_MIN_BURST * DRAM_WORD_WIDTH / DRAM_DIMM_WIDTH;
    UINT64 ADDR_END = 1LL << DRAM_ADDR_BITS;

    // print banner
    cout << "\n";
    cout << "Welcome to the Platform Debugger\n";
    cout << "--------------------------------\n";

    cout << endl << "Initializing hardware\n";

    sts = clientStub->StatusCheck(0);
    oldsts = sts;
    printRAMStatus(sts);

    // transfer control to hardware
    sts = clientStub->StartDebug(0);
    cout << "debugging started, sts = " << sts << endl << flush;

    sts = clientStub->StatusCheck(0);
    oldsts = sts;
    printRAMStatus(sts);

    // Masks so each data value is different
    static const UINT64 masks[4] = { 0,
                                     0x73a90e9844958762,
                                     0x8893450971234443,
                                     0xe87681345d506812 };

    // Write a pattern to memory.
    for (UINT64 addr = 0; addr < 10000; addr += MIN_IDX_OFFSET)
    {
        for (int bank = 0; bank < DRAM_NUM_BANKS; bank++)
        {
            data = ((addr + 123456) << 32) | (addr + 1001);
            if (bank != 0)
            {
                data <<= bank;
            }

            sts = clientStub->WriteReq(bank, addr);
            for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
            {
                sts = clientStub->WriteData(bank,
                                            data ^ masks[3],
                                            data ^ masks[2],
                                            data ^ masks[1],
                                            data ^ masks[0],
                                            0);
                oldsts = sts;
                data = ~data;
            }
        }
    }

    // Test for overrun.  Write a different pattern to the end of memory to
    // be sure that address bits are configured correctly.  The test
    // deliberately overruns by one write.
    for (UINT64 addr = ADDR_END - 1000 * MIN_IDX_OFFSET; addr <= ADDR_END; addr += MIN_IDX_OFFSET)
    {
        for (int bank = 0; bank < DRAM_NUM_BANKS; bank++)
        {
            data = ((addr + 654321) << 32) | (addr + 1001);
            if (bank != 0)
            {
                data <<= bank;
            }

            sts = clientStub->WriteReq(bank, addr);
            for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
            {
                sts = clientStub->WriteData(bank,
                                            data ^ masks[3],
                                            data ^ masks[2],
                                            data ^ masks[1],
                                            data ^ masks[0],
                                            0);
                oldsts = sts;
                data = ~data;
            }
        }
    }

    cout << "writes done" << endl;

    // Read the pattern back.  Alternate banks on each request.
    int errors = 0;
    int reads = 0;
    for (int j = 0; j <= 10000 - (32 * MIN_IDX_OFFSET); j += 32 * MIN_IDX_OFFSET)
    {
        for (int bank = 0; bank < DRAM_NUM_BANKS; bank++)
        {
            // Generate a burst of 32 read requests.  The actual reads won't be
            // triggered until the DoReads() below so that the RAM read bus
            // is stressed.
            for (int i = 0; i < 31; i += 1)
            {
                int addr = j + i * MIN_IDX_OFFSET;

                clientStub->ReadReq(bank, addr);
            }

            // Tell the hardware to do the reads
            clientStub->DoReads(0);

            for (int i = 0; i < 31; i += 1)
            {
                UINT64 addr = j + i * MIN_IDX_OFFSET;
    
                UINT64 expect = ((addr + 123456) << 32) | (addr + 1001);
                if (addr == 0)
                {
                    // Address 0 is a special case.  It is written twice.
                    // The second time is the overrun test.
                    expect = ((ADDR_END + 654321) << 32) | (ADDR_END + 1001);
                }

                if (bank != 0)
                {
                    expect <<= bank;
                }

                for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
                {
                    OUT_TYPE_ReadRsp d = clientStub->ReadRsp(bank);
                    const UINT64 data[4] = { d.data0, d.data1, d.data2, d.data3 };
                    for (int w = 0; w < (DRAM_WORD_WIDTH / 64); w += 1)
                    {
                        if (data[w] != (masks[w] ^ expect))
                        {
                            cout << hex << "error read data 0x" << addr << " [" << w << "] = 0x" << data[w] << " expect 0x" << (expect ^ masks[w]) << dec << endl;
                            errors += 1;
                        }
                    }
                    reads++;
                    expect = ~expect;
                }
            }
        }
    }

    cout << errors << " errors on " << reads << " reads" <<endl << endl << flush;

    //
    // Optimal read buffer size calibration
    //
#if (MEM_CHECK_LATENCY != 0)
    cout << "Latencies:" << endl;
    int min_idx = 0;
    int min_latency = 0;
    for (int i = 1; i <= DRAM_MAX_OUTSTANDING_READS; i++)
    {
        OUT_TYPE_ReadLatency r = clientStub->ReadLatency(256, i);
        cout << i << ": first " << r.firstReadLatency << " cycles, average "
             << r.totalLatency / 256.0 << " per load" << endl << flush;

        if ((min_idx == 0) || (r.totalLatency < min_latency))
        {
            min_idx = i;
            min_latency = r.totalLatency;
        }
    }

    cout << "Optimal reads in flight: " << min_idx << endl << endl << flush;
#endif

    errors = 0;
    for (int m = 0; m < (DRAM_WORD_WIDTH / 8); m++)
    {
        clientStub->WriteReq(0, 0);
        for (int b = 0; b < DRAM_MIN_BURST; b++)
        {
            clientStub->WriteData(0,
                                  -1, -1, -1, -1,
                                  0);
        }

        clientStub->WriteReq(0, 0);
        for (int b = 0; b < DRAM_MIN_BURST; b++)
        {
            clientStub->WriteData(0,
                                  0, 0, 0, 0,
                                  1 << m);
        }

        clientStub->ReadReq(0, 0);
        clientStub->DoReads(0);
        for (int b = 0; b < DRAM_MIN_BURST; b++)
        {
            OUT_TYPE_ReadRsp d = clientStub->ReadRsp(0);
            const UINT64 data[4] = { d.data0, d.data1, d.data2, d.data3 };

            UINT64 expect[4] = { 0, 0, 0, 0 };
            expect[m / 8] = 0xffL << ((m % 8) * 8);

            for (int w = 0; w < (DRAM_WORD_WIDTH / 64); w += 1)
            {
                if (data[w] != expect[w])
                {
                    printf("Mask error %d:  0x%016llx, expect 0x%016llx\n", m, data[w], expect[w]);
                    errors += 1;
                }
            }
        }
    }

    cout << errors << " mask errors" << endl << endl << flush;

    // report results and exit
    cout << "Done" << endl;
}
