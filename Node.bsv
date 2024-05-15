import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache512::*;
import CacheInterface::*;
import FIFO::*;
import SpecialFIFOs::*;
import PP::*;
import Router::*;
import CacheTypes::*;
import MessageFifo::*;
import MessageTypes::*;

interface NodeInterface;
    method Action toParent(CacheMemMessage msg);
    method ActionValue#(CacheMemMessage) fromParent();
    method Action toChild(CacheMemMessage msg);
    method ActionValue#(CacheMemMessage) fromChild();
    method Bool hasFromParent();
    method Bool hasFromChild();
    interface CacheInterface cacheinterface;
endinterface

(* synthesize *)
module mkNode#(Bit#(2) nth_node)(NodeInterface);
    // need to connect Procesor, L1, and L2 cache
    // There should be one more NoC connected to MainMem
    Bool debug = True;
    // to processor and from processor
    MainMem mainMem <- mkMainMem(); 

    Cache512 cacheL2 <- mkCache;

    // this is child message FIFO
    MessageFifo#(6) childDInMsgQueue <- mkMessageFifo;
    MessageFifo#(6) childDOutMsgQueue <- mkMessageFifo;
    Cache32 cacheD <- mkCache32(nth_node, childDInMsgQueue, childDOutMsgQueue);

    MessageFifo#(6) childIInMsgQueue <- mkMessageFifo;
    MessageFifo#(6) childIOutMsgQueue <- mkMessageFifo;
    Cache32 cacheI <- mkCache32(nth_node, childIInMsgQueue, childIOutMsgQueue);

    // message routed by the router
    // this is parent/directory message FIFO
    MessageFifo#(6) parentInMsgQueue <- mkMessageFifo;
    MessageFifo#(6) parentOutMsgQueue <- mkMessageFifo;
    Reg#(Bit#(32)) count <- mkReg(0);

    mkProtocolProcessor(nth_node, parentInMsgQueue, parentOutMsgQueue, cacheL2, count);
   

    // basically the compiler is not smart enough to explore different scheduling, so I have to specify this
    (*descending_urgency="cacheD.handleWaitFill, cacheinterface.sendReqData"*)
    (*descending_urgency="cacheD.afterCAUInMsgReq, cacheinterface.sendReqData"*)
    (*descending_urgency="cacheI.handleWaitFill, cacheinterface.sendReqInstr"*)
    (*descending_urgency="cacheI.afterCAUInMsgReq, cacheinterface.sendReqInstr"*)

    (*descending_urgency="handleICacheIn, handleICacheOut, getMemResp, sendL2ToMem"*)
    /*-----handle non coherent I cache-----*/
    rule handleICacheIn;
        let resp_ <- mainMem.get();
        if(debug) $display("<handleICacheIn> ICache Resp %d", count);
        childIInMsgQueue.enq_resp(
            CacheMemResp{
                fromChild: ?,
                core: nth_node,
                addr: ?,
                state: S,
                data: tagged Valid unpack(resp_)
            }
        );
    endrule

    rule handleICacheOut if(childIOutMsgQueue.notEmpty);
        let first = childIOutMsgQueue.first; childIOutMsgQueue.deq;
        if (first matches tagged Req .m) begin
            if(debug) $display("<handleICacheOut> ICache Req %d", count);
            MainMemReq req = MainMemReq{
                write: 0,
                addr: m.addr,
                data: ?
            };
            mainMem.put(req);
        end
        else if (first matches tagged Resp .m) begin
            $display("<handleICacheOut> Error: should never happen");
        end
    endrule
    /*-----handle non coherent I cache end---*/


    rule increment;
        count <= count + 1;
    endrule

    /* -------- L2 to Mem --------- */     
    rule sendL2ToMem;
        let req <- cacheL2.getToMem();
        mainMem.put(req);
    endrule

    rule getMemResp;
        let resp <- mainMem.get();
        cacheL2.putFromMem(resp);
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
        return parentOutMsgQueue.notEmpty;
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
                $display("Send instr Req     %d", count ,fshow(req));
                cacheI.putFromProc(req);
            endmethod
            method ActionValue#(Word) getRespInstr();
                let resp <- cacheI.getToProc();
                return resp;
            endmethod
        endinterface;
    

endmodule

function Bit#(2) getDestination(CacheMemMessage msg);
    if( msg matches tagged Req .m) 
        return m.core;
    else if (msg matches tagged Resp .m)
        return m.core;
    else
        return 0;
endfunction

module mkRouterNode(Bit#(2) nth_node, Router router, NodeInterface node, Empty ifc);
    Reg#(Maybe#(CacheMemMessage)) inflight_msg <- mkReg(tagged Invalid);
    Reg#(Bit#(6)) msg_chunk_cnt <- mkReg(0);

    rule sendMsg if(inflight_msg matches tagged Valid .msg);
        // ensure the flit size is larger than msg  
        $display("put on local node %d", getDestination(msg));
        router.dataLinks[4].putFlit(
            Flit{
                nextDir: ?,
                flitData: zeroExtend(pack(msg)),
                dest: getDestination(msg)                         
            });
        inflight_msg <= tagged Invalid;
    endrule

    rule issueMsgFromLocalNode if (node.hasFromParent() || node.hasFromChild());
        $display("issueMsgFromLocalNode");
        CacheMemMessage msg = ?;
        if (node.hasFromParent())
            msg <- node.fromParent();
        else
            msg <- node.fromChild();
        inflight_msg <= tagged Valid msg;
    endrule

    rule putMsgFromRemoteNode if (router.dataLinks[4].hasFlit());
        $display("putMsgFromRemoteNode");
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