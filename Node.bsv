import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache512::*;
import CacheInterface::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import PP::*;
import Router::*;
import CacheTypes::*;
import MessageFifo::*;
import MessageTypes::*;
import pipelined::*;


interface NodeInterface;
    method Action toParent(CacheMemMessage msg);
    method ActionValue#(CacheMemMessage) fromParent();
    method Action toChild(CacheMemMessage msg);
    method ActionValue#(CacheMemMessage) fromChild();
    method Bool hasFromParent();
    method Bool hasFromChild();
    interface CacheInterface cacheinterface;
endinterface

// (* synthesize *)
module mkNode(
    Bit#(2) coreId, 
    FIFOF#(MainMemReq) memHostReq,
    FIFOF#(MainMemResp) memHostResp,
    NodeInterface ifc);
    // need to connect Procesor, L1, and L2 cache
    // There should be one more NoC connected to MainMem
    let debug = True;
    // to processor and from processor

    Cache512 cacheL2 <- mkCache;

    // this is child message FIFO
    MessageFifo#(6) childDInMsgQueue <- mkMessageFifo;
    MessageFifo#(6) childDOutMsgQueue <- mkMessageFifo;
    Cache32 cacheD <- mkCache32(coreId, childDInMsgQueue, childDOutMsgQueue);

    MessageFifo#(6) childIInMsgQueue <- mkMessageFifo;
    MessageFifo#(6) childIOutMsgQueue <- mkMessageFifo;
    Cache32 cacheI <- mkCache32(coreId, childIInMsgQueue, childIOutMsgQueue);

    // message routed by the router
    // this is parent/directory message FIFO
    MessageFifo#(6) parentInMsgQueue <- mkMessageFifo;
    MessageFifo#(6) parentOutMsgQueue <- mkMessageFifo;
    Reg#(Bit#(32)) count <- mkReg(0);

    Reg#(Bit#(1)) trackIMem <- mkReg(0);
    Reg#(Bit#(1)) trackL2Mem <- mkReg(0);

    mkProtocolProcessor(coreId, parentInMsgQueue, parentOutMsgQueue, cacheL2, count);
   
    // basically the compiler is not smart enough to explore different scheduling, so I have to specify this
    // (*descending_urgency="cacheD.handleWaitFill, cacheinterface.sendReqData"*)
    // (*descending_urgency="cacheD.afterCAUInMsgReq, cacheinterface.sendReqData"*)
    // (*descending_urgency="cacheI.handleWaitFill, cacheinterface.sendReqInstr"*)
    // (*descending_urgency="cacheI.afterCAUInMsgReq, cacheinterface.sendReqInstr"*)
    (*descending_urgency="handleICacheIn, handleICacheOut, getMemResp, sendL2ToMem"*)

    
    /*-----handle non coherent I cache-----*/
    rule handleICacheIn if(trackIMem == 1 && trackL2Mem == 0);
        // childIOutMsgQueue.deq;
        let resp_ = memHostResp.first; memHostResp.deq;
        if(debug) $display("<CoreId %d handleICacheIn> ICache Resp %d", coreId, count);
        childIInMsgQueue.enq_resp(
            CacheMemResp{
                fromChild: ?,
                core: coreId,
                addr: ?,
                state: S,
                data: tagged Valid unpack(resp_)
            }
        );
        trackIMem <= 0;
    endrule

    rule handleICacheOut if(childIOutMsgQueue.notEmpty && trackIMem == 0 && trackL2Mem == 0);
        let first = childIOutMsgQueue.first; childIOutMsgQueue.deq;
        if(debug) $display("<CoreId %d handleICacheOut> ICache Req %d", coreId, count);
        if (first matches tagged Req .m) begin
            trackIMem <= 1;
            memHostReq.enq(MainMemReq{
                write: 0,
                addr: m.addr,
                data: ?
            });
        end
        else if (first matches tagged Resp .m) begin
            if(debug) $display("<handleICacheOut> Error: should never happen");
        end
    endrule
    /*-----handle non coherent I cache end---*/


    rule increment;
        count <= count + 1;
    endrule

    /* -------- L2 to Mem --------- */     
    rule sendL2ToMem if(trackIMem == 0 && trackL2Mem == 0);
        if(debug) $display("<CoreId %d> send L2 to Mem", coreId);
        let req <- cacheL2.getToMem();
        // mainMem.put(req);
        memHostReq.enq(req);
        trackL2Mem <= 1;
    endrule

    rule getMemResp if(trackIMem == 0 && trackL2Mem == 1);
        if(debug) $display("<CoreId %d> get Mem resp to L2", coreId);
        // let resp <- mainMem.get();
        let resp = memHostResp.first; memHostResp.deq;
        cacheL2.putFromMem(resp);
        
        trackL2Mem <= 0;
    endrule

    /* -------- L2 to Mem End---- */

    // router need to call these methods
    // remember child can only talk to parent; 
    // parent only talk to child
    // even though the parent and child are distributed, parents/children themselves don't talk at all
    // the router needs to talk both parent and child
    method Action toParent(CacheMemMessage msg);
        if (msg matches tagged Req .m)
            parentInMsgQueue.enq_req(m);
        else if (msg matches tagged Resp .m)
            parentInMsgQueue.enq_resp(m);
    endmethod

    method Bool hasFromParent();
        return parentOutMsgQueue.notEmpty;
    endmethod

    method Bool hasFromChild();
        return childDOutMsgQueue.notEmpty;
    endmethod

    method ActionValue#(CacheMemMessage) fromParent();
        parentOutMsgQueue.deq;
        return parentOutMsgQueue.first; 
    endmethod

    method Action toChild(CacheMemMessage msg);
        if (msg matches tagged Req .m)
            childDInMsgQueue.enq_req(m);
        else if (msg matches tagged Resp .m)
            childDInMsgQueue.enq_resp(m);
    endmethod

    method ActionValue#(CacheMemMessage) fromChild();
        childDOutMsgQueue.deq;
        return childDOutMsgQueue.first;
    endmethod

    interface cacheinterface = 
        interface CacheInterface
            method Action sendReqData(CacheReq req);
                cacheD.putFromProc(req);
            endmethod
            method ActionValue#(Word) getRespData();
                let resp <- cacheD.getToProc();
                return resp;
            endmethod
            method Action sendReqInstr(CacheReq req);
                if(debug) $display("Send instr Req     %d", count ,fshow(req));
                cacheI.putFromProc(req);
            endmethod
            method ActionValue#(Word) getRespInstr();
                let resp <- cacheI.getToProc();
                return resp;
            endmethod
        endinterface;
    

endmodule

function Bit#(2) getDestination(CacheMemMessage msg);
    // if it's a message from a child, then it has no idea where to go
    // if it's a message from a parent, it knows where to go
    if( msg matches tagged Req .m)
        if (m.fromChild == 1)
            return {0, m.addr[7:7]};
        else
            return m.core; 
    else if (msg matches tagged Resp .m)
        if (m.fromChild == 1)
            return {0, m.addr[7:7]};
        else
            return m.core; 
    else
        return 0;
endfunction

module mkRouterNode(Bit#(2) coreId, Router router, NodeInterface node, Empty ifc);
    Reg#(Maybe#(CacheMemMessage)) inflight_msg <- mkReg(tagged Invalid);
    Reg#(Bit#(6)) msg_chunk_cnt <- mkReg(0);
    
    Bool debug = True;

    rule sendMsg if(inflight_msg matches tagged Valid .msg);
        // ensure the flit size is larger than msg  
        if(debug) $display("<CoreId %d> put on local node, destination %d", coreId, getDestination(msg));
        router.dataLinks[4].putFlit(
            Flit{
                nextDir: ?,
                flitData: zeroExtend(pack(msg)),
                dest: getDestination(msg)                         
            });
        inflight_msg <= tagged Invalid;
    endrule

    rule issueMsgFromLocalNode if (inflight_msg matches tagged Invalid &&& (node.hasFromParent() || node.hasFromChild()));
        if(debug) $display("<CoreId %d>issueMsgFromLocalNode", coreId);
        CacheMemMessage msg = ?;
        if (node.hasFromParent())
            msg <- node.fromParent();
        else
            msg <- node.fromChild();
        inflight_msg <= tagged Valid msg;
    endrule

    rule putMsgFromRemoteNode if (router.dataLinks[4].hasFlit());
        if(debug) $display("<CoreId %d>putMsgFromRemoteNode", coreId);
        let flit <- router.dataLinks[4].getFlit();
        CacheMemMessage msg = unpack(flit.flitData[544:0]);
        if(msg matches tagged Req .m) begin
            if(m.fromChild == 1) 
                node.toParent(msg);
            else
                node.toChild(msg);
        end
        else if (msg matches tagged Resp .m) begin
            if(m.fromChild == 1) 
                node.toParent(msg);
            else
                node.toChild(msg);
        end
    endrule
endmodule

module mkCore(
    Bit#(2) coreId,
    NodeInterface node, 
    Empty ifc);
    let debug = True;
    RVIfc rv_core <- mkpipelined(coreId);
    FIFO#(Mem) ireq <- mkFIFO;
    FIFO#(Mem) dreq <- mkFIFO;
    FIFO#(Mem) mmioreq <- mkFIFO;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule

    rule requestI;
        let req <- rv_core.getIReq;
        if (debug) $display("<CoreId %d>Get IReq cycle count ", coreId, cycle_count, fshow(req));
        ireq.enq(req);
        node.cacheinterface.sendReqInstr(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseI;
        let x <- node.cacheinterface.getRespInstr();
        let req = ireq.first();
        ireq.deq();
        if (debug) $display("<CoreId %d>Get IResp ", coreId, cycle_count, fshow(req), fshow(x));
        req.data = x;
        rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq;
        if (req.byte_en == 0) begin
            dreq.enq(req);
        end
        if (debug) $display("<CoreId %d>Get DReq", coreId, fshow(req));
        node.cacheinterface.sendReqData(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule


    rule responseD;
        let x <- node.cacheinterface.getRespData();
        let req = dreq.first();
        dreq.deq();
        if (debug) $display("<CoreId %d>Get IResp ", coreId, fshow(req), fshow(x));
        req.data = x;
        rv_core.getDResp(req);
    endrule
  
    rule requestMMIO;
        let req <- rv_core.getMMIOReq;
        if (debug) $display("<CoreId %d>Get MMIOReq", coreId, fshow(req));
        if (req.byte_en == 'hf) begin
            if (req.addr == 'hf000_fff4) begin
                // Write integer to STDERR
                        $fwrite(stderr, "%0d", req.data);
                        $fflush(stderr);
            end
        end
        if (req.addr ==  'hf000_fff0) begin
                // Writing to STDERR
                $fwrite(stderr, "%c", req.data[7:0]);
                $fflush(stderr);
        end else
            if (req.addr == 'hf000_fff8) begin
                $display("<CoreId %d>RAN CYCLES", coreId, cycle_count);

            // Exiting Simulation
                if (req.data == 0) begin
                        $fdisplay(stderr, "  [0;32mPASS[0m");
                end
                else
                    begin
                        $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                    end
                $fflush(stderr);
                $finish;
            end

        mmioreq.enq(req);
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("<CoreId %d>Put MMIOResp", coreId, fshow(req));
        rv_core.getMMIOResp(req);
    endrule

endmodule