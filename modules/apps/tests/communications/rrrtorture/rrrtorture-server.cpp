#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>

#include "asim/syntax.h"
#include "asim/rrr/service_ids.h"
#include "asim/provides/connected_application.h"

using namespace std;

// ===== service instantiation =====
RRRTORTURE_0_SERVER_CLASS RRRTORTURE_0_SERVER_CLASS::instance;
RRRTORTURE_1_SERVER_CLASS RRRTORTURE_1_SERVER_CLASS::instance;
RRRTORTURE_2_SERVER_CLASS RRRTORTURE_2_SERVER_CLASS::instance;
RRRTORTURE_3_SERVER_CLASS RRRTORTURE_3_SERVER_CLASS::instance;
RRRTORTURE_4_SERVER_CLASS RRRTORTURE_4_SERVER_CLASS::instance;
RRRTORTURE_5_SERVER_CLASS RRRTORTURE_5_SERVER_CLASS::instance;
RRRTORTURE_6_SERVER_CLASS RRRTORTURE_6_SERVER_CLASS::instance;
RRRTORTURE_7_SERVER_CLASS RRRTORTURE_7_SERVER_CLASS::instance;

RRRTORTURE_0_SERVER_CLASS::RRRTORTURE_0_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_0_SERVER_STUB_CLASS(this);
};

RRRTORTURE_1_SERVER_CLASS::RRRTORTURE_1_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_1_SERVER_STUB_CLASS(this);
};

RRRTORTURE_2_SERVER_CLASS::RRRTORTURE_2_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_2_SERVER_STUB_CLASS(this);
};

RRRTORTURE_3_SERVER_CLASS::RRRTORTURE_3_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_3_SERVER_STUB_CLASS(this);
};

RRRTORTURE_4_SERVER_CLASS::RRRTORTURE_4_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_4_SERVER_STUB_CLASS(this);
};

RRRTORTURE_5_SERVER_CLASS::RRRTORTURE_5_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_5_SERVER_STUB_CLASS(this);
};

RRRTORTURE_6_SERVER_CLASS::RRRTORTURE_6_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_6_SERVER_STUB_CLASS(this);
};

RRRTORTURE_7_SERVER_CLASS::RRRTORTURE_7_SERVER_CLASS() {
    // instantiate stub
    serverStub = new RRRTORTURE_7_SERVER_STUB_CLASS(this);
};
