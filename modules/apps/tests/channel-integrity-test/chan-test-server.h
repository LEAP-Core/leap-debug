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

#ifndef __CHANTEST_SERVER__
#define __CHANTEST_SERVER__

#include <stdio.h>
#include <sys/time.h>

#include "asim/provides/low_level_platform_interface.h"
#include "asim/provides/rrr.h"

// Get the data types from the server stub
#define TYPES_ONLY
#include "asim/rrr/server_stub_CHANTEST.h"
#undef TYPES_ONLY

// This module provides the CHANTEST server
typedef class CHANTEST_SERVER_CLASS* CHANTEST_SERVER;

class CHANTEST_SERVER_CLASS: public RRR_SERVER_CLASS,
                             public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static CHANTEST_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

    UINT64 f2hRecvMsgs;
    UINT64 f2hRecvErrors;

    UINT64 h2fRecvErrors;
    UINT64 h2fRecvBitErrors;

  public:
    CHANTEST_SERVER_CLASS();
    ~CHANTEST_SERVER_CLASS();

    // static methods
    static CHANTEST_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();

    // Error checking
    UINT64 GetF2HRecvMsgCnt() const { return f2hRecvMsgs; };
    UINT64 GetF2HRecvErrCnt() const { return f2hRecvErrors; };

    UINT64 GetH2FRecvErrCnt() const { return h2fRecvErrors; };
    UINT64 GetH2FRecvBitErrCnt() const { return h2fRecvBitErrors; };

    //
    // RRR service methods
    //
    void F2HOneWayMsg8(UINT64 payload0,
                       UINT64 payload1,
                       UINT64 payload2,
                       UINT64 payload3,
                       UINT64 payload4,
                       UINT64 payload5,
                       UINT64 payload6,
                       UINT64 payload7);

    void H2FNoteError(UINT32 numBitsFlipped,
                      UINT32 chunkIdx,
                      UINT64 payload0,
                      UINT64 payload1,
                      UINT64 payload2,
                      UINT64 payload3,
                      UINT64 payload4,
                      UINT64 payload5,
                      UINT64 payload6,
                      UINT64 payload7);
};


// Include the server stub
#include "asim/rrr/server_stub_CHANTEST.h"

#endif
