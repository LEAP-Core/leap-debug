// RRR doesn't handle types correctly....
typedef struct {
    UInt#(32) workingSet;
    UInt#(32) stride;
    UInt#(32) iterations;
    UInt#(8)  command;
} CommandType deriving (Bits,Eq);

