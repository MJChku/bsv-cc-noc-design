// SINGLE CORE ASSOIATED CACHE -- stores words

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector::*;
import CAU::*;
import CacheTypes::*;

// The types live in MemTypes.bsv

// Notice the asymmetry in this interface, as mentioned in lecture.
// The processor thinks in 32 bits, but the other side thinks in 512 bits.
interface Cache32;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
    // method ActionValue#(MainMemReq) getToMem();
    // method Action putFromMem(MainMemResp e);
endinterface

// delete when you're done with it
typedef Bit#(1) PLACEHOLDER;

typedef Bit#(32) Word;

// typedef enum {
//     Ready,
//     StartMiss,
//     SendWriteBackReq,
//     SendFillReq,
//     WaitFillResp
// } MSHRState deriving (Eq, Bits, FShow);

typedef CacheReq MSHRReq;

typedef enum {
    WaitCAUResp,
    SentFillReq,
    WaitFillResp
} MSHRState deriving (Eq, Bits, FShow);

function Bit#(32) byteMaskedData(Bit#(32) data_, Bit#(4) mask_);
        Bit#(8) mask0 = signExtend(mask_[0]);
        Bit#(8) mask1 = signExtend(mask_[1]);
        Bit#(8) mask2 = signExtend(mask_[2]);
        Bit#(8) mask3 = signExtend(mask_[3]);
        Bit#(32) final_mask = {mask3, mask2, mask1, mask0};
        return data_ & final_mask;
endfunction

// (* synthesize *)
module mkCache32(
    Bit#(2) nth_node,
    MessageFifo#(6) inMsgQueue,
    MessageFifo#(6) outMsgQueue,
    Cache32 ifc);

    let debug = False;
    // tag is 19bits, index is 7 bits
    CAU#(7, 19) cau <- mkCAU;

    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero.vmh";  // zero out for you
    // Define cache metadata
    // initialized to 0, with InValid state and 0 tag
    // FIFOF#(Bit#(32)) hitQ <- mkSizedBypassFIFOF(10);
    // FIFOF#(MSHRReq) currReqQ <- mkSizedBypassFIFOF(10);
    FIFO#(Bit#(32)) hitQ <- mkBypassFIFO;

    Reg#(Bit#(1)) cau_upto_date <- mkReg(1'b1);

    FIFO#(MainMemReq) outterReqBuf <- mkFIFO;

    FIFO#(MainMemResp) outterRespQ <- mkFIFO;

    // Reg#(MSHRReq) mshr_req <- mkRegU;
    // FIFOF#(MSHRReq) currReqQ <- mkPipelineFIFO;
    FIFO#(MSHRReq) currReqQ <- mkFIFO;
    Reg#(MSHRState) mshr <- mkReg(WaitCAUResp);

    Reg#(Bit#(32)) count <- mkReg(0);  

    // (*descending_urgency="handleWaitFill, putFromProc"*)

    (*descending_urgency="handleWaitFill, waitCAUResp, processInMsgReq, afterCAUInMsgReq"*)

    rule waitCAUResp if (mshr == WaitCAUResp);
        if(debug) $display("waitCAUResp, cnt %d", count);
        let curr_req = currReqQ.first;
        ParsedAddress addr = parseAddress(curr_req.addr);
        let curr_index = addr.index;
        let curr_tag = addr.tag;
        
        let resp_ <- cau.resp();
        if (resp_.hitMiss == LdHit) begin
            if(debug) $display("LdHit");
            hitQ.enq(resp_.ldValue);
            currReqQ.deq;
        end
        else if (resp_.hitMiss == StHit) begin
            if(debug) $display("StHit");
            // since no reply is expected, just deq the request
            // the request is considered completed
            currReqQ.deq;
        end
        else if (resp_.hitMiss == Miss) begin
            if(debug) $display("Miss");
            if (resp_.cl matches tagged Valid .cl) begin
                // other states don't care
                // volunteer write back M data
                if (cl.state == M) begin 
                    let clAddr = {cl.tag, curr_index};
                    if(debug) $display("Volunteer write back");
                    outMsgQueue.enq_resp(
                        CacheMemResp{
                            fromChild: 1,
                            core: nth_node,
                            addr: clAddr,
                            state: I,
                            data: tagged Valid unpack(cl.data)
                        }
                    );
                end 
            end

            if(debug) $display("outMsg enq_req for data %d", nth_node, fshow({curr_tag, curr_index}));
            outMsgQueue.enq_req(
                CacheMemReq{
                    fromChild: 1,
                    core: nth_node,
                    addr: {curr_tag, curr_index},
                    state: resp_.dstMSI
                }
            );
            mshr <= WaitFillResp;
        end
    endrule

    // wait for the fill response from the memory
    // update the cache line metadata, tag and state
    // update the cache line data by issueing a BRAM write req
    rule afterCAUInMsgReq if( inMsgQueue.first matches tagged Req .m);
        let resp_ <- cau.resp();
        inMsgQueue.deq;
        if (resp_.hitMiss == Miss) begin
            // my cache doesn't have this cacheline
            outMsgQueue.enq_resp(
                CacheMemResp{
                    fromChild: 1,
                    core: nth_node,
                    addr: m.addr,
                    state: I,
                    data: tagged Invalid
                }
            );
        end else if (resp_.hitMiss == LdHit) begin
            // my cache has this cacheline
            if(resp_.cl matches tagged Valid .cl) begin
                let index = m.addr[6:0];
                Cline#(64, 19) newline = ?;
                newline.data = cl.data;
                newline.state = m.state;
                newline.tag = cl.tag;
                let ret <- cau.update(
                    index,
                    newline
                );
                if(cl.state == M && m.state < cl.state) begin
                    // need to send writeback request
                    outMsgQueue.enq_resp(
                        CacheMemResp{
                            fromChild: 1,
                            core: nth_node,
                            addr: m.addr,
                            state: m.state,
                            data: tagged Valid unpack(cl.data)
                        }
                    );
                end else if (cl.state == S && m.state == I) begin
                    outMsgQueue.enq_resp(
                        CacheMemResp{
                            fromChild: 1,
                            core: nth_node,
                            addr: m.addr,
                            state: m.state,
                            data: tagged Invalid
                        }
                    );
                end  
            end 
        end
    endrule 
    
    rule processInMsgReq if( inMsgQueue.first matches tagged Req .m);
        // request for downgrade
        let addr = m.addr; 
        // it's a read, it should hit if the cacheline exists
        let ret <- cau.req(
            CacheReq{
                addr: {addr, 6'b0},
                word_byte: 4'b0,
                data: 0
            }
        );
    endrule

    // rule processInMsgResp if( inMsgQueue.first matches CacheMemResp .m);
    //     // response for upgrade request
    //     if (m.state == M || m.state == S) begin
    //         if (m.data matches tagged Valid .cl) begin
    //             outterRespQ.enq(pack(cl))
    //         end
    //     end 
    // endrule

    rule handleWaitFill if (mshr == WaitFillResp &&& inMsgQueue.first matches tagged Resp .m);
        if(debug) $display("handleWaitFill");
        LineData resp = ?;
        if (m.data matches tagged Valid .cl) begin
            if(debug) $display("inMsgQueue resp data ", fshow(cl));
            resp = cl;
        end
        inMsgQueue.deq;
        let mshr_req = currReqQ.first; currReqQ.deq;
        ParsedAddress addr = parseAddress(mshr_req.addr);
        let curr_tag = addr.tag;
        let curr_index = addr.index;
        let word_offset = addr.offset;
        let new_state = m.state;
        if (mshr_req.word_byte != 4'b0) begin
            if(debug) $display("byteMaskedData");
            let word_data = byteMaskedData(mshr_req.data, mshr_req.word_byte);
            let origin_data = byteMaskedData(resp[word_offset], 4'hf - mshr_req.word_byte);
            resp[word_offset] = origin_data | word_data;
            // new_state = M;
            // assert(m.state == M);
            if (m.state != M) 
                $display("Error: m state should == M");
        end
        else begin
            if(debug) $display("enq hitQ");
            hitQ.enq(resp[word_offset]);
        end

        Cline#(64, 19) newline = ?;
        newline.data = pack(resp);
        newline.state = new_state;
        newline.tag = curr_tag;
        let cau_ret <- cau.update(curr_index, newline);
        cau_upto_date <= cau_ret;
        mshr <= WaitCAUResp;
    endrule

    rule counter;
        count <= count + 1;
    endrule 
    // blocking cache
    // if the cache is busy, the processor will wait until the cache is ready
    // if read hit then issue BRAM read req, and enq word_offset
    // if write hit then issue BRAM write req, and update the cache line metadata.
    // if not hit, then start miss, no BRAM req is sent yet.

    //        cau_resp -> cau_req needs to be satisfied by the CAU
    // the WaitCAUResp -> putFromProc currReqQ is FIFO which is deq first then enq 
     method Action putFromProc(CacheReq e) if (cau_upto_date == 1 );
        if(debug) $display("L1 putFromProc, cnt = %d reqQ depth", count);
        // Check if the data is in the cache
        let cau_ret <- cau.req(e);
        cau_upto_date <= cau_ret;
        currReqQ.enq(e);
    endmethod
    
    // the WaitCAUResp -> getToProc because hitQ is bypassFIFO
    // want getToProc -> putFromProc
    // but WaitCAUResp will never happen before because mshr read and write; ACTION: remove mshr read
    method ActionValue#(Word) getToProc();
        if(debug) $display("getToProc, cnt = %d", count);
        let resp = hitQ.first;
        hitQ.deq;
        return resp;
    endmethod
        
    // method ActionValue#(MainMemReq) getToMem();
    //     if(debug) $display("getToMem");
    //     let req = outterReqQ.first;
    //     outterReqQ.deq;
    //     return req;
    // endmethod
        
    // method Action putFromMem(MainMemResp e);
    //     if(debug) $display("putFromMem");
    //     outterRespQ.enq(e);
    // endmethod
endmodule
