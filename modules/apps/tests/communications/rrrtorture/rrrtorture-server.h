#ifndef __RRRTEST_SERVER__
#define __RRRTEST_SERVER__

#include <stdio.h>
#include <sys/time.h>

#include "asim/provides/low_level_platform_interface.h"
#include "asim/provides/rrr.h"

// Get the data types from the server stub
#define TYPES_ONLY
#include "asim/rrr/server_stub_RRRTORTURE_0.h"
#include "asim/rrr/server_stub_RRRTORTURE_1.h"
#include "asim/rrr/server_stub_RRRTORTURE_2.h"
#include "asim/rrr/server_stub_RRRTORTURE_3.h"
#include "asim/rrr/server_stub_RRRTORTURE_4.h"
#include "asim/rrr/server_stub_RRRTORTURE_5.h"
#include "asim/rrr/server_stub_RRRTORTURE_6.h"
#include "asim/rrr/server_stub_RRRTORTURE_7.h"
#undef TYPES_ONLY

// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_0_SERVER_CLASS* RRRTORTURE_0_SERVER;

class RRRTORTURE_0_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_0_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_0_SERVER_CLASS();

    ~RRRTORTURE_0_SERVER_CLASS(){
      Cleanup();
    }


    // static methods
    static RRRTORTURE_0_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p) {
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg0(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_0.h"

// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_1_SERVER_CLASS* RRRTORTURE_1_SERVER;

class RRRTORTURE_1_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_1_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_1_SERVER_CLASS();

    ~RRRTORTURE_1_SERVER_CLASS(){
      Cleanup();
    };


    // static methods
    static RRRTORTURE_1_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg1(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_1.h"


// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_2_SERVER_CLASS* RRRTORTURE_2_SERVER;

class RRRTORTURE_2_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_2_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_2_SERVER_CLASS();
    ~RRRTORTURE_2_SERVER_CLASS() {
      Cleanup();
    }


    // static methods
    static RRRTORTURE_2_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg2(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_2.h"


// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_3_SERVER_CLASS* RRRTORTURE_3_SERVER;

class RRRTORTURE_3_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_3_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_3_SERVER_CLASS();


    ~RRRTORTURE_3_SERVER_CLASS(){
      Cleanup();
    }


    // static methods
    static RRRTORTURE_3_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg3(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_3.h"



// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_4_SERVER_CLASS* RRRTORTURE_4_SERVER;

class RRRTORTURE_4_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_4_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_4_SERVER_CLASS();

    ~RRRTORTURE_4_SERVER_CLASS(){
      Cleanup();
    }


    // static methods
    static RRRTORTURE_4_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg4(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_4.h"


// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_5_SERVER_CLASS* RRRTORTURE_5_SERVER;

class RRRTORTURE_5_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_5_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_5_SERVER_CLASS();

    ~RRRTORTURE_5_SERVER_CLASS(){
      Cleanup();
    }


    // static methods
    static RRRTORTURE_5_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup() {
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg5(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_5.h"

// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_6_SERVER_CLASS* RRRTORTURE_6_SERVER;

class RRRTORTURE_6_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static RRRTORTURE_6_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_6_SERVER_CLASS();

    ~RRRTORTURE_6_SERVER_CLASS(){
      Cleanup();
    }


    // static methods
    static RRRTORTURE_6_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit(){
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg6(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_6.h"

// this module provides the RRRTest server functionalities
typedef class RRRTORTURE_7_SERVER_CLASS* RRRTORTURE_7_SERVER;

class RRRTORTURE_7_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
  static RRRTORTURE_7_SERVER_CLASS instance;

    // server stub
    RRR_SERVER_STUB serverStub;

  public:
    RRRTORTURE_7_SERVER_CLASS();

    ~RRRTORTURE_7_SERVER_CLASS() {
      // instantiate stub
      Cleanup();
    };

    // static methods
    static RRRTORTURE_7_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE p){
      PLATFORMS_MODULE_CLASS::Init(p);
    };

    void Uninit() {
      //Cleanup();
      PLATFORMS_MODULE_CLASS::Uninit();
    };

    void Cleanup(){
      delete serverStub;
    };

    UINT64 F2HTwoWayMsg7(UINT64 payload)
    {
        return payload;
    }
        
};


// Include the server stub
#include "asim/rrr/server_stub_RRRTORTURE_7.h"

#endif

