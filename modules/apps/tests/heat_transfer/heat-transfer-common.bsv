typedef Bit#(64) CYCLE_COUNTER;

typedef 512 N_X_POINTS;
typedef 512 N_Y_POINTS;
typedef   4 N_X_ENGINES;
typedef   8 N_Y_ENGINES;
typedef TMul#(N_X_ENGINES, N_Y_ENGINES) N_TOTAL_ENGINES;
typedef  16 N_LOCAL_ENGINES;
typedef TSub#(N_TOTAL_ENGINES, N_LOCAL_ENGINES) N_REMOTE_ENGINES;
typedef TMul#(N_X_POINTS, N_Y_POINTS)  N_TOTAL_POINTS;
typedef TDiv#(N_Y_POINTS, N_Y_ENGINES) N_ROWS_PER_ENGINE;
typedef TDiv#(N_X_POINTS, N_X_ENGINES) N_COLS_PER_ENGINE;
typedef Bit#(TAdd#(TAdd#(TLog#(N_X_POINTS),TLog#(N_Y_POINTS)),2)) MEM_ADDRESS;
typedef Bit#(8) TEST_DATA;
typedef TMul#(N_ROWS_PER_ENGINE, N_COLS_PER_ENGINE)  N_POINTS_PER_ENGINE;

