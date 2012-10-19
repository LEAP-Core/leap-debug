#include <stdio.h>
#include <sstream>
#include "asim/provides/stats_service.h"
#include "asim/rrr/client_stub_MEMPERFRRR.h"
#include "asim/provides/connected_application.h"

//static UINT32 stride[] = {1,2,3,4,5,6,7,8,16,32,64,128};
static UINT32 stride[] = {128};

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

    for (int rw = 0; rw < 2; rw++) {
        for (int ws = 16; ws < 26; ws++) {
            for (int stride_idx = 0; stride_idx < max_stride_idx; stride_idx++) {
                stringstream filename;
                OUT_TYPE_RunTest result = clientStub->RunTest(1 << ws,
                                                              stride[stride_idx],
                                                              1<<16,
                                                              rw);

                filename << "cache_" << rw << "_" << stride_idx << "_" << ws << ".stats";
                STATS_SERVER_CLASS::GetInstance()->DumpStats();
                STATS_SERVER_CLASS::GetInstance()->EmitFile(filename.str());
                STATS_SERVER_CLASS::GetInstance()->ResetStatValues();
            }
        }
    }

    // Send "done" command
    clientStub->RunTest(0, 0, 0, 2);

    STARTER_DEVICE_SERVER_CLASS::GetInstance()->End(0);
  
    return 0;
}
