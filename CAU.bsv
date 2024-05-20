import BRAM::*;
import Vector :: * ;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import CacheTypes::*;

typedef enum { LdHit, StHit, Miss } HitMissType deriving (Eq, Bits, FShow);
typedef enum { CInSync, COutOfSync, CBlocked} CAUStatus deriving (Eq, Bits, FShow);

typedef struct {
    MSI state;
    Bit#(cache_tag_size) tag;
} ClMeta#(numeric type cache_tag_size) deriving(Bits);

typedef struct {
    MSI state;
    // Bit#(TSub#(32,TLog#(line_size))) addr;
    Bit#(tag_size) tag;
    Bit#(TMul#(line_size, 8)) data;
} Cline#(numeric type line_size, numeric type tag_size) deriving(Bits);

typedef struct {
    HitMissType hitMiss;
    MSI dstMSI;
    Bit#(TMul#(word_size, 8)) ldValue;
    Maybe#(cline) cl;
} CAUResp#(numeric type word_size, type cline) deriving(Bits);

// typedef struct {
//     Bit#(4) reqId;
//     Bit#(32) addr;
// } MemReq deriving(Bits);

typedef struct{
    Bit#(4) reqId;
    Bit#(cache_tag_size) tag;
    Bit#(logNLines) index;
    Bit#(4) offset;
    Bit#(4) writeen;
    Bool isLoad;
    Bit#(32) data;
} TagIndexReq#(numeric type logNLines, numeric type cache_tag_size) deriving(Bits);

// typedef struct{
//     Bit#(logNLines) index;
//     Bit#(cache_tag_size) tag;
//     Bit#(2) offset;
// } ParsedAddress#(numeric type logNLines, numeric type cache_tag_size) deriving(Bits);

interface CAU#(numeric type logNLines, numeric type tagSize);
    method ActionValue#(Bit#(1)) req (CacheReq r);
    method ActionValue#(CAUResp#(4, Cline#(64, tagSize))) resp ();
    method ActionValue#(Bit#(1)) update(Bit#(logNLines) index, Cline#(64, tagSize) newline);
endinterface


// clSize is the size of a cacheline in bytes
// wordSize is the size of a word in bytes
// tagSize is the size of the tag in bits
module mkCAU(CAU#(logNLines, tagSize)) provisos (Add#(tagSize, logNLines, 26));

    let debug = False;
    BRAM_Configure cfg1 = defaultValue;
    BRAM_Configure cfg2 = defaultValue;
    ClMeta#(tagSize) initialClMeta = unpack({'0});
    Vector#(TExp#(logNLines), Reg#(ClMeta#(tagSize))) clMeta <- replicateM(mkReg(initialClMeta));
    // BRAM2Port#(Bit#(logNLines), ClMeta#(tagSize)) clMeta <- mkBRAM2Server(cfg1);  // also a placeholder
    // BRAM1Port#(Bit#(logNLines), Bit#(TMul#(64, 8))) clData <- mkBRAM1Server(cfg2);  // also a placeholder
    BRAM1PortBE#(Bit#(logNLines), Vector#(16, Bit#(TMul#(4, 8))), 64) clData <- mkBRAM1ServerBE(cfg1);  // also a placeholder

    FIFO#(Bit#(logNLines)) bramReadBuf <- mkBypassFIFO;
    // Reg#(CAUStatus) status <- mkReg(Ready);
    // Reg#(TagIndexReq) currReq <- mkRegU; //shadow of outer currReq 

    FIFO#(TagIndexReq#(logNLines, tagSize)) reqFifo <- mkFIFO;
    FIFO#(CAUResp#(4, Cline#(64, tagSize))) respQ <- mkBypassFIFO;

    TagIndexReq#(logNLines, tagSize) initReq = unpack({'0});
    // Ehr#(2, TagIndexReq#(logNLines, tagSize)) currReqQ <- mkEhr(initReq);
    // Ehr#(2, Maybe#(Bit#(26))) storeAddrQ <- mkEhr(tagged Invalid);
    // Ehr#(2, Maybe#(Bit#(26))) storeAddrQ <- mkEhr(tagged Invalid);
    Reg#(CAUStatus) cauStatus <- mkReg(CInSync); 
    Reg#(Bit#(32)) count <- mkReg(0);
    rule updateCount;
        count <= count + 1;
    endrule

    rule afterBramResp;
        if(debug) $display("BRAM latency %d", cfg1.latency);
        let currReq = reqFifo.first; reqFifo.deq;
        let curr_index = currReq.index;
        let clMeta_ =  clMeta[curr_index];
        let isLoad = currReq.isLoad;
        let tagMatch = clMeta_.tag == currReq.tag;
        let loadHit = isLoad && clMeta_.state > I && tagMatch;
        let storeHit = !isLoad && clMeta_.state == M && tagMatch;
        let index = currReq.index;
        let offset = currReq.offset;
        CAUResp#(4, Cline#(64, tagSize)) resp_ = ?;

       
        if(debug) $display("enq resp in CAU %d ", count);
        if (loadHit) begin
            let clData_ <- clData.portA.response.get();
            resp_.hitMiss = LdHit;
            resp_.ldValue = clData_[offset];
            
            Cline#(64, tagSize) cacheline = ?;
            cacheline.tag = clMeta_.tag;
            cacheline.state = clMeta_.state;
            cacheline.data = pack(clData_);
            resp_.cl = tagged Valid cacheline;
            respQ.enq(resp_); 
            
        end else 
        if (storeHit) begin
            resp_.hitMiss = StHit;
            respQ.enq(resp_); 
        end else begin
            // storeAddrQ[1] <= tagged Invalid;
            // Cache miss
            resp_.hitMiss = Miss;
            if (isLoad) 
                resp_.dstMSI = S;
            else resp_.dstMSI = M;
            
            resp_.cl = tagged Invalid;
            if(!tagMatch && clMeta_.state == M) begin
                Cline#(64, tagSize) cacheline = ?;
                cacheline.tag = clMeta_.tag;
                cacheline.state = clMeta_.state;
                let clData_ <- clData.portA.response.get();
                cacheline.data = pack(clData_);
                resp_.cl = tagged Valid cacheline;
            end 
            respQ.enq(resp_);
        end
    endrule

    method ActionValue#(Bit#(1)) req(CacheReq r);
        Bit#(1) local_cauStatus = 1;
        if(debug) $display("process req in CAU %d ", count);
        Bool isLoad = reduceOr(r.word_byte) == 1'b0;
        let tag_idx = valueOf(TSub#(32, tagSize));
        let index_idx = valueOf(TSub#(TSub#(32, tagSize), logNLines));
        let curr_offset = r.addr[5: 2];
        Bit#(tagSize) curr_tag = r.addr[31: tag_idx];
        Bit#(logNLines) curr_index = r.addr[tag_idx-1: index_idx];
        
        let clMeta_ = clMeta[curr_index];
        let tagMatch = clMeta_.tag == curr_tag;
        let loadHit = isLoad && clMeta_.state > I && tagMatch;
        let storeHit = !isLoad && clMeta_.state == M && tagMatch;
        if (loadHit) begin
            clData.portA.request.put(BRAMRequestBE{
                writeen: 0,
                responseOnWrite:False,
                address: curr_index,
                datain: ?
            });
        end
        else if(storeHit) begin
            Vector#(16, Bit#(4)) writeen_mask = unpack(64'b0);
            writeen_mask[curr_offset] = r.word_byte;
            let write_data = r.data;
            LineData cache_line_data = unpack(512'b0);
            cache_line_data[curr_offset] = write_data; 
            // on hot encoding
            clData.portA.request.put(BRAMRequestBE{
                writeen: pack(writeen_mask),
                responseOnWrite: False,
                address: curr_index,
                datain: cache_line_data
            });
            // clMeta[curr_index].state <= Dirty;
        end else begin
            local_cauStatus = 0;
            if ( !tagMatch && clMeta[curr_index].state == M ) begin
                clData.portA.request.put(BRAMRequestBE{
                    writeen: 0,
                    responseOnWrite:False,
                    address: curr_index,
                    datain: ?
                });
            end
        end

        TagIndexReq#(logNLines, tagSize) tag_req = ?;
        tag_req.tag = curr_tag;
        tag_req.index = curr_index;
        tag_req.isLoad = isLoad;
        tag_req.offset = curr_offset;
        tag_req.writeen = r.word_byte;
        tag_req.data = r.data;
        reqFifo.enq(tag_req);
        if(debug) $display("enq req in CAU %d ", count);
        return local_cauStatus;
    endmethod

    // afterBRAMResp  -> req because of the reqFIFO; deq happens first then enq
    //                -> resp because of the bypassFIFO; enq happens first then deq
    // additionally, it's required that resp -> req 
    method ActionValue#(CAUResp#(4, Cline#(64, tagSize))) resp();
        if(debug) $display("deq resp in CAU %d ", count);
        respQ.deq;
        return respQ.first;
    endmethod

    method ActionValue#(Bit#(1)) update(Bit#(logNLines) index, Cline#(64, tagSize) newline);
        $display("update in CAU %d, state %d, addr ", count, newline.state, fshow({newline.tag, index}));
        clData.portA.request.put(BRAMRequestBE{
            writeen: signExtend(1'b1),
            responseOnWrite: False,
            address: index,
            datain: unpack(newline.data)
        });
        ClMeta#(tagSize) clMeta_ = ?;
        clMeta_.state = newline.state;
        clMeta_.tag = newline.tag;
        clMeta[index] <= clMeta_;
        return 1'b1;
    endmethod
endmodule
