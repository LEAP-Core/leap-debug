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
// @file rrrtest.cpp
// @brief RRR Test System
//
// @author Angshuman Parashar
//

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>

#include "asim/syntax.h"
#include "asim/ioformat.h"
#include "asim/rrr/service_ids.h"
#include "asim/provides/connected_application.h"
#include "asim/provides/clocks_device.h"
#include "asim/rrr/client_stub_CLOCKTEST.h"
#include "clock_test.h"

using namespace std;

// constructor
CONNECTED_APPLICATION_CLASS::CONNECTED_APPLICATION_CLASS(
    VIRTUAL_PLATFORM vp)
{
    // instantiate client stub
    clientStub = new CLOCKTEST_CLIENT_STUB_CLASS(NULL);
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
    printf("Beginning Clock test.\n");
    fflush(stdout);
    for(int i = 0; i < (1<<20); i++) { 
      int result  = clientStub->test(i);
      if(i%1000 == 0) {
        printf("Clock Test @ %d\n", i);
	fflush(stdout);
      }
      if(i != result) {
        printf("Got %x, expected %x\n", result, i);
	fflush(stdout);
      }
    }

    printf("Finishing Clock test.\n");
    fflush(stdout);
}
