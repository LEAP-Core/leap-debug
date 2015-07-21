#include <stdio.h>
#include <sstream>
#include "awb/provides/stats_service.h"
#include "awb/rrr/client_stub_MEMPERFRRR.h"
#include "awb/provides/connected_application.h"
#include "awb/provides/fpga_components.h"


static UINT32 stride[] = {1,2,3,4,5,6,7,8,16,32,64,128};
static UINT32 rw[] = {0,1,0,1,1};

using namespace std;

// constructor                                                                                                                      
CONNECTED_APPLICATION_CLASS::CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp)
  
{
    clientStub = new MEMPERFRRR_CLIENT_STUB_CLASS(NULL);
}

// destructor                                                                                                                       
CONNECTED_APPLICATION_CLASS::~CONNECTED_APPLICATION_CLASS()
{
}

// init                                                                                                                             
void
CONNECTED_APPLICATION_CLASS::Init()
{
}

// main                                                                                                                             
int
CONNECTED_APPLICATION_CLASS::Main()
{
    int max_stride_idx = sizeof(stride) / sizeof(stride[0]);

    // The on-board DRAM controller takes a while to initialize
    // and currently sends no signal to say it is ready.  Without this
    // warm-up the initialization time is charged to the first real
    // test that misses in the L1.
    cout << "Warmup" << endl;
    clientStub->RunTest(1, 1, 1, 1);

    uint32_t iterations = 1 << MEM_PERF_ITERATIONS;

    //
    // Software controls the order of tests.  NOTE:  Writes for a given pattern
    // must precede reads!  The writes initialize memory values and are required
    // for read value error detection.
    //
    for (int ws = 9; ws < 24; ws++) {
        for (int stride_idx = 0; stride_idx < 12; stride_idx++) {
            for (int rw_idx = 0; rw_idx < 5; rw_idx++) {
                stringstream filename;
                cout << "Test RW: " << ((rw[rw_idx])?"Read":"Write") << " Working Set: " << (1 << ws) << " stride " << stride[stride_idx] << endl;

                OUT_TYPE_RunTest result = clientStub->RunTest(1 << ws,
                                                              stride[stride_idx],
                                                              iterations,
                                                              rw[rw_idx]);

                if (MEM_PERF_INDIVIDUAL_STATS)
                {                    
                    filename << "cache_" << rw << "_" << stride_idx << "_" << ws << ".stats";
                    STATS_SERVER_CLASS::GetInstance()->DumpStats();
                    STATS_SERVER_CLASS::GetInstance()->EmitFile(filename.str());
                    STATS_SERVER_CLASS::GetInstance()->ResetStatValues();
                }
            }
        }
    }

    STARTER_SERVICE_SERVER_CLASS::GetInstance()->End(0);
  
    return 0;
}
