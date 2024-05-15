import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;

// Note that this interface *is* symmetric. 
interface Cache512;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

typedef struct {
    LineState state;
    LineTagL2 tag;
} CacheLineMeta deriving (Bits, Eq);

typedef enum {
    Ready,
    StartMiss,
    SendWriteBackReq,
    SendFillReq,
    WaitFillResp
} MSHRState deriving (Eq, Bits, FShow);

typedef MainMemReq MSHRReq;

(* synthesize *)
module mkCache(Cache512);
    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero512.vmh";  // zero out for you

    // At that level, probably no need of byteenable BRAM
    CacheLineMeta initialClMeta = CacheLineMeta{state: Invalid, tag: 18'b0};
    Vector#(256, Reg#(CacheLineMeta)) clMeta <- replicateM(mkReg(initialClMeta));

    // since BRAM is 256 cacheline the addr bits are log(256) = 8
    BRAM1Port#(LineIndexL2, Bit#(512)) clData <- mkBRAM1Server(cfg);

    // Define the FIFOs of hitQ which contains hit data for request
    FIFO#(Bit#(512)) hitQ <- mkBypassFIFO;

    FIFO#(OutterMemReq) outterReqQ <- mkFIFO;
    FIFO#(OutterMemResp) outterRespQ <- mkFIFO;

    Reg#(MSHRReq) mshr_req <- mkRegU;
    Reg#(MSHRState) mshr <- mkReg(Ready);

    // Remember the previous hints when applicable, especially defining useful types.

    // handle the miss request
    // if the cache line is dirty, fetch the dirty data from BRAM
    // move to next state depending on whether write back should be sent
    // or we could move BRAM request earlier
    rule handleMiss if (mshr == StartMiss);
        let addr = parseAddressL2(mshr_req.addr);
        let curr_tag = addr.tag;
        let curr_index = addr.index;
        let is_dirty_line = clMeta[curr_index].state == Dirty;
        if (is_dirty_line) begin
            clData.portA.request.put(BRAMRequest{
                    write: False,
                    responseOnWrite: False,
                    address: curr_index,
                    datain: ?
            });
            mshr <= SendWriteBackReq;
        end
        else begin
            mshr <= SendFillReq;
        end

    endrule

    // send write back request to the memory
    // optionally update the cache line metadata to invalid
    rule handleWriteBack if (mshr == SendWriteBackReq);
        let addr = parseAddressL2(mshr_req.addr);
        let curr_index = addr.index;
        let dirty_addr = {clMeta[curr_index].tag, curr_index};
        let dirty_data <- clData.portA.response.get();
        outterReqQ.enq(OutterMemReq{
            write: 1,
            addr: dirty_addr,
            data: pack(dirty_data)
        });
        mshr <= SendFillReq;
        clMeta[curr_index].state <= Invalid;
    endrule

    // send fill request to the memory
    rule handleSendMiss if (mshr == SendFillReq);
        let addr = parseAddressL2(mshr_req.addr);
        let curr_tag = addr.tag;
        let curr_index = addr.index;
        // skip fetch, because we are writing a whole cachline
        // update the cache line metadata, tag and state
        // update the BRAM data by issueing a BRAM write req
        if (mshr_req.write == 1'b1) begin
            clMeta[curr_index] <= CacheLineMeta{
                state: Dirty,
                tag: curr_tag
            };
            clData.portA.request.put(BRAMRequest{
                write: True,
                responseOnWrite: False,
                address: curr_index,
                datain: mshr_req.data
            });
            mshr <= Ready;
        end
        else begin
            outterReqQ.enq(OutterMemReq{
                    write: 0,
                    addr: mshr_req.addr,
                    data: ?
            }); 
            mshr <= WaitFillResp;
        end
    endrule

    // wait for the fill response from the memory
    // update the cache line metadata, tag and state
    // update the cache line data by issueing a BRAM write req
    rule handleWaitFill if (mshr == WaitFillResp);
        LineDataL2 resp = unpack(outterRespQ.first);
        outterRespQ.deq;

        let addr = parseAddressL2(mshr_req.addr);
        let curr_tag = addr.tag;
        let curr_index = addr.index;
        let new_state = Clean;

        hitQ.enq(resp);
        clMeta[curr_index] <= CacheLineMeta{
            state: Clean,
            tag: curr_tag
        };

        clData.portA.request.put(BRAMRequest{
            write: True,
            responseOnWrite: False,
            address: curr_index,
            datain: resp
        });
        mshr <= Ready;
    endrule

    // You may instead find it useful to use the CacheArrayUnit abstraction presented
    // in lecture. In that case, most of your logic would be in that module, which you 
    // can instantiate within this one.

    // Hint: Refer back to the slides for implementation details.
    // Hint: You may find it helpful to outline the necessary states and rules you'll need for your cache
    // Hint: Don't forget about $display
    // Hint: If you want to add in a store buffer, do it after getting it working without one.
    
    // if mshr is not busy, get response from BRAM and enq to hitQ
    // doesn't touch the cache line metadata
    rule enqHitQ if (mshr == Ready);
        let cache_line_data <- clData.portA.response.get();
        hitQ.enq(cache_line_data);
    endrule

    // blocking cache
    // if the cache is busy, the processor will wait until the cache is ready
    // if read hit then issue BRAM read req, and enq word_offset
    // if write hit then issue BRAM write req, and update the cache line metadata.
    // if not hit, then start miss, no BRAM req is sent yet.
    method Action putFromProc(MainMemReq e) if (mshr == Ready);
        // Check if the data is in the cache
        Bool is_read = e.write == 1'b0;
        let addr = parseAddressL2(e.addr);
        let curr_tag = addr.tag;
        let curr_index = addr.index;
        let hit = clMeta[curr_index].state != Invalid && clMeta[curr_index].tag == curr_tag;
       
        if (hit) begin 
            if (is_read) begin
                clData.portA.request.put(BRAMRequest{
                    write: False,
                    responseOnWrite:False,
                    address: curr_index,
                    datain: ?
                });
            end
            else begin
                clData.portA.request.put(BRAMRequest{
                    write: True,
                    responseOnWrite: False,
                    address: curr_index,
                    datain: e.data
                });
                clMeta[curr_index].state <= Dirty;
            end
        end
        else begin
            mshr <= StartMiss;
            mshr_req <= e;
        end        
    endmethod
        
    method ActionValue#(MainMemResp) getToProc();
        let resp = hitQ.first;
        hitQ.deq;
        return resp;
    endmethod
        
    method ActionValue#(MainMemReq) getToMem();
        let req = outterReqQ.first;
        outterReqQ.deq;
        return req;
    endmethod
        
    method Action putFromMem(MainMemResp e);
        outterRespQ.enq(e);
    endmethod

endmodule
