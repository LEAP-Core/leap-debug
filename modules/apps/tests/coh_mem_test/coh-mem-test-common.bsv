`include "awb/provides/coh_mem_test_common.bsh"
typedef Bit#(64) CYCLE_COUNTER;

typedef `COH_MEM_TEST_ENGINE_NUM N_ENGINES;
typedef Bit#(TAdd#(TLog#(TAdd#(N_ENGINES,1)),1)) ENGINE_PORT_NUM;
typedef Bit#(`COH_MEM_TEST_MEMORY_ADDR_BITS) MEM_ADDRESS;
typedef Bit#(64) TEST_DATA;


typedef enum
{
    COH_TEST_REQ_WRITE_RAND,
    COH_TEST_REQ_WRITE_SEQ,
    COH_TEST_REQ_READ_RAND,
    COH_TEST_REQ_READ_SEQ,
    COH_TEST_REQ_RANDOM,
    COH_TEST_REQ_FENCE,
    COH_TEST_REQ_RANDOM_FENCE
}
COH_MEM_ENGINE_TEST_REQ
    deriving (Bits, Eq);

