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

#include "asim/syntax.h"
#include "asim/rrr/service_ids.h"
#include "asim/provides/hybrid_application.h"

using namespace std;

// ===== service instantiation =====
CHANTEST_SERVER_CLASS CHANTEST_SERVER_CLASS::instance;

// constructor
CHANTEST_SERVER_CLASS::CHANTEST_SERVER_CLASS()
    : f2hRecvMsgs(0),
      f2hRecvErrors(0),
      h2fRecvErrors(0),
      h2fRecvBitErrors(0)
{
    // instantiate stub
    serverStub = new CHANTEST_SERVER_STUB_CLASS(this);
}

// destructor
CHANTEST_SERVER_CLASS::~CHANTEST_SERVER_CLASS()
{
    Cleanup();
}

// init
void
CHANTEST_SERVER_CLASS::Init(PLATFORMS_MODULE p)
{
    PLATFORMS_MODULE_CLASS::Init(p);
}

// uninit
void
CHANTEST_SERVER_CLASS::Uninit()
{
    Cleanup();
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
CHANTEST_SERVER_CLASS::Cleanup()
{
    delete serverStub;
}

//
// RRR service methods
//

void
CHANTEST_SERVER_CLASS::F2HOneWayMsg16(
    UINT64 payload0,
    UINT64 payload1,
    UINT64 payload2,
    UINT64 payload3,
    UINT64 payload4,
    UINT64 payload5,
    UINT64 payload6,
    UINT64 payload7,
    UINT64 payload8,
    UINT64 payload9,
    UINT64 payload10,
    UINT64 payload11,
    UINT64 payload12,
    UINT64 payload13,
    UINT64 payload14,
    UINT64 payload15)
{
    f2hRecvMsgs += 1;

    bool err = false;
    if (payload0 != ~payload8) err = true;
    if (payload1 != ~payload9) err = true;
    if (payload2 != ~payload10) err = true;
    if (payload3 != ~payload11) err = true;
    if (payload4 != ~payload12) err = true;
    if (payload5 != ~payload13) err = true;
    if (payload6 != ~payload14) err = true;
    if (payload7 != ~payload15) err = true;
    if (err)
    {
        f2hRecvErrors += 1;
        cout << "F2H Error" << endl;
    }
}

void
CHANTEST_SERVER_CLASS::H2FNoteError(
    UINT32 numBitsFlipped,
    UINT32 chunkIdx,
    UINT64 payload0,
    UINT64 payload1,
    UINT64 payload2,
    UINT64 payload3,
    UINT64 payload4,
    UINT64 payload5,
    UINT64 payload6,
    UINT64 payload7,
    UINT64 payload8,
    UINT64 payload9,
    UINT64 payload10,
    UINT64 payload11,
    UINT64 payload12,
    UINT64 payload13,
    UINT64 payload14,
    UINT64 payload15)
{
    h2fRecvErrors += 1;
    h2fRecvBitErrors += numBitsFlipped;
    cout << "H2F Error (" << numBitsFlipped << " bits, idx " << chunkIdx << ")" << endl;
    cout.fill('0');
    cout << hex;

    cout << "  0x" << std::setw(16) << payload0
         << "  0x" << std::setw(16) << payload8
         << "  0x" << std::setw(16) << ~(payload0 ^ payload8)
         << endl;

    cout << "  0x" << std::setw(16) << payload1
         << "  0x" << std::setw(16) << payload9
         << "  0x" << std::setw(16) << ~(payload1 ^ payload9)
         << endl;

    cout << "  0x" << std::setw(16) << payload2
         << "  0x" << std::setw(16) << payload10
         << "  0x" << std::setw(16) << ~(payload2 ^ payload10)
         << endl;

    cout << "  0x" << std::setw(16) << payload3
         << "  0x" << std::setw(16) << payload11
         << "  0x" << std::setw(16) << ~(payload3 ^ payload11)
         << endl;

    cout << "  0x" << std::setw(16) << payload4
         << "  0x" << std::setw(16) << payload12
         << "  0x" << std::setw(16) << ~(payload4 ^ payload12)
         << endl;

    cout << "  0x" << std::setw(16) << payload5
         << "  0x" << std::setw(16) << payload13
         << "  0x" << std::setw(16) << ~(payload5 ^ payload13)
         << endl;

    cout << "  0x" << std::setw(16) << payload6
         << "  0x" << std::setw(16) << payload14
         << "  0x" << std::setw(16) << ~(payload6 ^ payload14)
         << endl;

    cout << "  0x" << std::setw(16) << payload7
         << "  0x" << std::setw(16) << payload15
         << "  0x" << std::setw(16) << ~(payload7 ^ payload15)
         << endl;

    cout << dec;
    cout.fill(' ');
}

