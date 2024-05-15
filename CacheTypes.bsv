import MemTypes::*;
import Types::*;
import Vector::*;

typedef Bit#(TLog#(4)) CoreID;

// MSI state
typedef enum {I, S, M} MSI deriving( Bits, Eq, FShow );

typedef enum {N, Y} YesNo deriving (Bits, Eq, FShow);
typedef struct {
    Vector#(4, MSI) state;
    Vector#(4, YesNo) status;
} ChState deriving(Bits, Eq);

// typedef enum { DataRead, StateUpdate} MType deriving( Bits, Eq, FShow );

instance Ord#(MSI);
    function Bool \< ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT);
    endfunction
    function Bool \<= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT) || (c == EQ);
    endfunction
    function Bool \> ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT);
    endfunction
    function Bool \>= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT) || (c == EQ);
    endfunction

    // This should implement M > S > I
    function Ordering compare( MSI x, MSI y );
        if( x == y ) begin
            // MM SS II
            return EQ;
        end else if( x == M || y == I) begin
            // MS MI SI
            return GT;
        end else begin
            // SM IM IS
            return LT;
        end
    endfunction

    function MSI min( MSI x, MSI y );
        if( x < y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
    function MSI max( MSI x, MSI y );
        if( x > y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
endinstance

typedef 26 AddrSz;
typedef Bit#(AddrSz) Addr;

// cache <-> mem message
typedef struct{
    Bit#(1)           fromChild;
    CoreID            core;
    Addr              addr;
    MSI               state;
    Maybe#(CacheLine) data;
} CacheMemResp deriving(Eq, Bits, FShow);

typedef struct{
    Bit#(1)     fromChild;
    CoreID      core;
    Addr        addr;
    MSI         state;
} CacheMemReq deriving(Eq, Bits, FShow);

typedef union tagged {
    CacheMemReq     Req;
    CacheMemResp    Resp;
} CacheMemMessage deriving(Eq, Bits, FShow);

// Interfaces for message FIFO connecting cache and mem
interface MessageFifo#( numeric type n );
    method Action enq_resp( CacheMemResp d );
    method Action enq_req( CacheMemReq d );
    method Bool hasResp;
    method Bool hasReq;
    method Bool notEmpty;
    method CacheMemMessage first;
    method Action deq;
endinterface

// some restricted views of message FIFO interfaces
interface MessagePut;
	method Action enq_resp(CacheMemResp d);
    method Action enq_req( CacheMemReq d );
endinterface

function MessagePut toMessagePut(MessageFifo#(n) ifc);
	return (interface MessagePut;
		method enq_resp = ifc.enq_resp;
		method enq_req = ifc.enq_req;
	endinterface);
endfunction

interface MessageGet;
    method Bool hasResp;
    method Bool hasReq;
    method Bool notEmpty;
    method CacheMemMessage first;
    method Action deq;
endinterface

function MessageGet toMessageGet(MessageFifo#(n) ifc);
	return (interface MessageGet;
		method hasResp = ifc.hasResp;
		method hasReq = ifc.hasReq;
		method notEmpty = ifc.notEmpty;
		method first = ifc.first;
		method deq = ifc.deq;
	endinterface);
endfunction
