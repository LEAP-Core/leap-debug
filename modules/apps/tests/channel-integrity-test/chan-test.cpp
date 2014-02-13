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

//
// @file chan-test.cpp
// @brief Channel integrity test
//
// @author Michael Adler
//

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <time.h>

#include "asim/syntax.h"
#include "asim/ioformat.h"
#include "asim/rrr/service_ids.h"
#include "asim/provides/hybrid_application.h"
#include "asim/provides/clocks_device.h"

using namespace std;

// constructor
HYBRID_APPLICATION_CLASS::HYBRID_APPLICATION_CLASS(
    VIRTUAL_PLATFORM vp)
{
    // instantiate client stub
    clientStub = new CHANTEST_CLIENT_STUB_CLASS(NULL);
    server = CHANTEST_SERVER_CLASS::GetInstance();

    srandom(time(NULL));
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

void
HYBRID_APPLICATION_CLASS::SendH2FMsg()
{
    UINT64 v[4];

    for (int i = 0; i < 4; i++)
    {
        // Make pairs of values identical so it is possible to figure out
        // what value was sent.
        UINT64 r0 = random();
        UINT64 r1 = random();
        UINT64 r2 = random();
        v[i] = (r2 << 38) ^ (r1 << 20) ^ r0;
    }

#ifdef FAILURE_PATTERN
    // This pattern has high probability of triggering a failure when
    // error checking is disabled in the Nallatech/ACP v2.0.1 channel.
    v[0] = 0x32757fff41a6f659;
    v[1] = 0xfb1c2be8434701de;
    v[2] = 0xea5fc471bbe63998;
    v[3] = 0x18f8bad18307d8db;
#endif
    
    // Send the 4 values and their complements
    clientStub->H2FOneWayMsg8(v[0], v[1], v[2], v[3],
                              ~v[0], ~v[1], ~v[2], ~v[3]);
}


// main
void
HYBRID_APPLICATION_CLASS::Main()
{
    UINT64 test_length  = testIterSwitch.Value();

    // print banner and test parameters
    cout << endl
         << "Test Parameters" << endl
         << "---------------" << endl
         << "Number of Transactions  = " << dec << test_length << endl;

    cout << endl
         << "Running..." << endl
         << "---------------" << endl;

    //
    // Have the FPGA start sending test data to the host.
    //
    clientStub->F2HStartOneWayTest(test_length);

    //
    // Send data from the host to the FPGA.  This may run in parallel with
    // the FPGA -> Host test started above.
    //
    for (UINT64 i = 0; i < test_length; i++)
    {
        SendH2FMsg();
    }

    // Get count of host -> FPGA errors
    OUT_TYPE_H2FGetStats stats;
    stats = clientStub->H2FGetStats(0);
    cout << endl
         << "Test Results" << endl
         << "---------------" << endl;

    cout << "Host -> FPGA total packets:      " << stats.recvPackets << endl
         << "Host -> FPGA error packets:      " << stats.packetErrors << endl
         << "Host -> FPGA total bits flipped: " << stats.totalBitsFlipped << endl;

    cout << "FPGA -> Host total packets:      " << server->GetF2HRecvMsgCnt() << endl
         << "FPGA -> Host error packets:      " << server->GetF2HRecvErrCnt() << endl;

    // done!
    cout << endl
         << "Tests Complete.\n";
}
