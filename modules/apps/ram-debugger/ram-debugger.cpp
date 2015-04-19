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
// @file ram-debugger.cpp
// @brief RAM Debugger Application
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
#include "asim/provides/connected_application.h"
#include "asim/provides/clocks_device.h"
#include "asim/provides/ddr_sdram_device.h"
#include "asim/provides/debug_scan_service.h"


using namespace std;

// constructor
CONNECTED_APPLICATION_CLASS::CONNECTED_APPLICATION_CLASS(
    VIRTUAL_PLATFORM vp)
{
    clientStub = new RAM_DEBUGGER_CLIENT_STUB_CLASS(NULL);
}

// destructor
CONNECTED_APPLICATION_CLASS::~CONNECTED_APPLICATION_CLASS()
{
    delete clientStub;
}

void
CONNECTED_APPLICATION_CLASS::Init()
{
}

// main
void
CONNECTED_APPLICATION_CLASS::Main()
{
    UINT64 data;

    // Different memory styles have different minimum offsets This is
    // a combination of DRAM_MIN_BURST and DRAM_BEAT_WIDTH.
    int MIN_IDX_OFFSET = DRAM_MIN_BURST * DRAM_BEAT_WIDTH / DRAM_WORD_WIDTH;
    UINT64 ADDR_END = 1LL << DRAM_ADDR_BITS;

    // print banner
    cout << endl
         << "Welcome to the RAM Debugger" << endl
         << "--------------------------------" << endl << endl;

    cout << "Initializing hardware" << endl;

    // transfer control to hardware
    uint32_t sts = clientStub->StartDebug(0);
    cout << "debugging started, sts = " << sts << endl << flush;

    UINT64 total_mem_mb = ADDR_END / (1024 * 1024) *
                          (DRAM_WORD_WIDTH / 8) *
                          DRAM_NUM_BANKS;
    cout << "Configured for " << total_mem_mb << " MB of board memory"
         << " in " << DRAM_NUM_BANKS << (DRAM_NUM_BANKS == 1 ? " bank" : " banks") << endl
         << "  Word size: " << DRAM_WORD_WIDTH << " bits" << endl;
    if (DRAM_NUM_BANKS > 1)
    {
        cout << "  " << total_mem_mb / DRAM_NUM_BANKS << " MB per bank" << endl;
    }
    cout << endl;

    // Masks so each data value is different
    static const UINT64 masks[4] = { 0,
                                     0x73a90e9844958762,
                                     0x8893450971234443,
                                     0xe87681345d506812 };


    // Write a pattern to memory.
    UINT64 write_test_end = min(UINT64(10000), ADDR_END / MIN_IDX_OFFSET / 2);
    for (UINT64 addr = 0; addr < write_test_end; addr += MIN_IDX_OFFSET)
    {
        for (int bank = 0; bank < DRAM_NUM_BANKS; bank++)
        {
            data = ((addr + 123456) << 32) | (addr + 1001);
            if (bank != 0)
            {
                data <<= bank;
            }

            clientStub->WriteReq(bank, addr);
            for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
            {
                clientStub->WriteData(bank,
                                      0, 0, 0, 0,
                                      data ^ masks[3],
                                      data ^ masks[2],
                                      data ^ masks[1],
                                      data ^ masks[0],
                                      0);
                data = ~data;
            }
        }
    }

    cout << "writes done" << endl;

    // Read the pattern back.  Alternate banks on each request.
    int errors = 0;
    int reads = 0;
    for (int j = 0; j <= write_test_end - (32 * MIN_IDX_OFFSET); j += 32 * MIN_IDX_OFFSET)
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

                if (bank != 0)
                {
                    expect <<= bank;
                }

                for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
                {
                    OUT_TYPE_ReadRsp d = clientStub->ReadRsp(bank);
                    const UINT64 data[4] = { d.data0, d.data1, d.data2, d.data3 };
                    for (int w = 0; w < (DRAM_BEAT_WIDTH / 128); w += 1)
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
    // Test that the number of address bits is correct.
    //

    // Start by storing 0's at address 0
    cout << "Alias test:" << endl;
    errors = 0;
    
    clientStub->WriteReq(0, 0);
    for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
    {
        clientStub->WriteData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    // Write at increasing address and look for an alias
    for (UINT64 i = 2; i <= DRAM_ADDR_BITS; i += 1)
    {
        UINT64 addr = 1LL << (i - 1);

        if (addr >= MIN_IDX_OFFSET)
        {
            clientStub->WriteReq(0, addr);
            for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
            {
                clientStub->WriteData(0, i, i, i, i, i, i, i, i, 0);
            }

            // Read back address 0 and make sure it is still 0
            clientStub->ReadReq(0, 0);
            clientStub->DoReads(0);
            for (int burst = 0; burst < DRAM_MIN_BURST; burst++)
            {
                OUT_TYPE_ReadRsp d = clientStub->ReadRsp(0);
                if ((burst == 0) && (d.data0 != 0))
                {
                    cout << "  ERROR:  Address bit " << i << " is aliased!" << endl;
                    errors += 1;
                }
            }
        }
    }

    if (! errors) cout << "  Pass" << endl;
    cout << endl;


    //
    // Optimal read buffer size calibration
    //
#if (MEM_CHECK_LATENCY != 0)
    cout << "Latencies:" << endl;
    int min_idx = 0;
    float min_latency = 0;
    for(UINT16 randomize = 0; randomize < 2; randomize++)
      {
        for (int i = 1; i <= DRAM_MAX_OUTSTANDING_READS; i++)
	  {
            UINT32 loads = 1<<20;
            OUT_TYPE_ReadLatency result = clientStub->ReadLatency(loads, randomize, i);
            float averageLatency = (((float)result.totalLatency/loads/(MODEL_CLOCK_FREQ*1000000)) * 1000000000);
            float throughput = (((float)loads) * (DRAM_MIN_BURST*DRAM_BEAT_WIDTH)/(8000000))/((float)result.testCycles/(MODEL_CLOCK_FREQ*1000000));

            cout << i << ": first " << result.firstReadLatency <<
	      " cycles: "  << result.testCycles  <<
	      " totalLatency: "  << result.totalLatency  <<
	      " throughput: "  << throughput << " MB/s" <<
	      " average latency: " << averageLatency << " nS " <<endl << flush;

            if ((min_idx == 0) || (result.totalLatency < min_latency))
	      {
                min_idx = i;
                min_latency = result.totalLatency;
	      }
	  }

        cout << "Optimal reads in flight: " << min_idx << endl << endl << flush;
      }

#endif

    errors = 0;
    for (int m = 0; m < (DRAM_BEAT_WIDTH / 8); m++)
    {
        clientStub->WriteReq(0, 0);
        for (int b = 0; b < DRAM_MIN_BURST; b++)
        {
            clientStub->WriteData(0,
                                  -1, -1, -1, -1,
                                  -1, -1, -1, -1,
                                  0);
        }

        clientStub->WriteReq(0, 0);
        for (int b = 0; b < DRAM_MIN_BURST; b++)
        {
            clientStub->WriteData(0,
                                  0, 0, 0, 0,
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

            for (int w = 0; w < (DRAM_BEAT_WIDTH / 64); w += 1)
            {
                if (data[w] != expect[w])
                {
                    printf("Mask error %d:  0x%016llx, expect 0x%016llx\n", m, data[w], expect[w]);
                    errors += 1;
                }
            }
        }
    }

    cout << endl << errors << " mask errors" << endl << endl << flush;

    // report results and exit
    cout << "Done" << endl;
    exit(0);
}
