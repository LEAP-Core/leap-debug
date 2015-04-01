#ifndef __RRRTEST_SYSTEM__
#define __RRRTEST_SYSTEM__

#include "asim/provides/command_switches.h"
#include "asim/provides/virtual_platform.h"

typedef class CONNECTED_APPLICATION_CLASS* CONNECTED_APPLICATION;
class CONNECTED_APPLICATION_CLASS
{
  private:

  public:

    CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp);
    ~CONNECTED_APPLICATION_CLASS();

    // main
    void Init();
    void Main();
};

#endif
