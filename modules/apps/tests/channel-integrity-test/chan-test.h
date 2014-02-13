//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

#ifndef __CHANTEST_SYSTEM__
#define __CHANTEST_SYSTEM__

#include "asim/provides/command_switches.h"
#include "asim/provides/virtual_platform.h"
#include "asim/rrr/client_stub_CHANTEST.h"
#include "asim/restricted/chan-test-server.h"

// Channel integrity test system

class TEST_ITERATIONS_SWITCH_CLASS : public COMMAND_SWITCH_INT_CLASS
{
  private:
    UINT32 testIter;

  public:
    ~TEST_ITERATIONS_SWITCH_CLASS() {};
    TEST_ITERATIONS_SWITCH_CLASS() :
        COMMAND_SWITCH_INT_CLASS("test-iterations"),
        testIter(10000)
    {};

    void ProcessSwitchInt(int arg) { testIter = arg; };
    void ShowSwitch(std::ostream& ostr, const string& prefix)
    {
        ostr << prefix << "[--test-iterations=<n>] Channel test iterations" << endl;
    };

    int Value(void) const { return testIter; }
};


typedef class HYBRID_APPLICATION_CLASS* HYBRID_APPLICATION;
class HYBRID_APPLICATION_CLASS
{
  private:

    // client stub
    CHANTEST_CLIENT_STUB clientStub;

    // Arguments
    TEST_ITERATIONS_SWITCH_CLASS testIterSwitch;

    // Server stub
    CHANTEST_SERVER server;

    void SendH2FMsg();

  public:

    HYBRID_APPLICATION_CLASS(VIRTUAL_PLATFORM vp);
    ~HYBRID_APPLICATION_CLASS();

    // main
    void Init();
    void Main();
};

#endif
