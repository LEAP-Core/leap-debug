#include <stdio.h>
#include <sstream>
#include "asim/provides/stats_service.h"
#include "asim/rrr/client_stub_MEMPERFRRR.h"
#include "asim/provides/connected_application.h"



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
    // We call start for each of the test cases.                      
    // May need to call starter once to start           
    for(int rw = 0; rw < 2; rw = rw + 1) {
        for(int ws = 9; ws < 26; ws = ws + 1) {
            for(int stride = 0; stride < 13; stride = stride + 1) {
    	        stringstream filename;
		OUT_TYPE_RunTest result = clientStub->RunTest(65000);
                filename << "cache_" << rw << "_" << stride << "_" << ws << ".stats";
                STATS_SERVER_CLASS::GetInstance()->DumpStats();
		STATS_SERVER_CLASS::GetInstance()->EmitFile(filename.str());
		STATS_SERVER_CLASS::GetInstance()->ResetStatValues();
	    }
	}
    }


  STARTER_DEVICE_SERVER_CLASS::GetInstance()->End(0);
  
  return 0;
}
