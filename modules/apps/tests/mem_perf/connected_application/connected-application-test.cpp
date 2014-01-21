#include <stdio.h>
#include <sstream>
#include "awb/provides/stats_service.h"
#include "awb/rrr/client_stub_MEMPERFRRR.h"
#include "awb/provides/connected_application.h"


static UINT32 stride[] = {1,2,3,4,5,6,7,8,16,32,64,128};
static UINT32 rw[] = {0,1,0,1};

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

    //
    // Software controls the order of tests.  NOTE:  Writes for a given pattern
    // must precede reads!  The writes initialize memory values and are required
    // for read value error detection.
    //

    for (int ws = 9; ws < 13; ws++) {
	for (int rw_idx = 0; rw_idx < 3; rw_idx++) {

            for (int stride_idx = 0; stride_idx < 2; stride_idx++) {
                stringstream filename;
                cout << "Test RW: " << ((rw[rw_idx])?"Read":"Write") << " Working Set: " << (1 << ws) << " stride " << stride[stride_idx] << endl;

                OUT_TYPE_RunTest result = clientStub->RunTest(1 << ws,
                                                              stride[stride_idx],
                                                              1<<16,
                                                              rw[rw_idx]);

                filename << "cache_" << rw << "_" << stride_idx << "_" << ws << ".stats";
                STATS_SERVER_CLASS::GetInstance()->DumpStats();
                STATS_SERVER_CLASS::GetInstance()->EmitFile(filename.str());
                STATS_SERVER_CLASS::GetInstance()->ResetStatValues();
            }
        }
    }

    STARTER_DEVICE_SERVER_CLASS::GetInstance()->End(0);
  
    return 0;
}
