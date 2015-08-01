#include <stdio.h>
#include <sstream>
#include "awb/provides/stats_service.h"
#include "awb/provides/connected_application.h"
#include "awb/provides/fpga_components.h"

using namespace std;

// constructor                                                                                                                      
CONNECTED_APPLICATION_CLASS::CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp)  
{

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
    // send dynamic parameter.
    DYNAMIC_PARAMS_SERVICE_CLASS::GetInstance()->SendParam("TestNode", 0xdeadbeef);     
  
    return 0;
}
