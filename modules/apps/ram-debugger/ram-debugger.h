#ifndef __RAM_DEBUGGER__
#define __RAM_DEBUGGER__

#include "asim/provides/command_switches.h"
#include "asim/provides/virtual_platform.h"
#include "asim/rrr/client_stub_RAM_DEBUGGER.h"

typedef class CONNECTED_APPLICATION_CLASS* CONNECTED_APPLICATION;
class CONNECTED_APPLICATION_CLASS
{
  private:

    // client stub
    RAM_DEBUGGER_CLIENT_STUB clientStub;

  public:

    CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp);
    ~CONNECTED_APPLICATION_CLASS();

    // main
    void Init();
    void Main();
};

#endif
