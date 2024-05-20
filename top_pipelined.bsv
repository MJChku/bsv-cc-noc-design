// PIPELINED SINGLE CORE PROCESSOR WITH 2 LEVEL CACHE
import RVUtil::*;
import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import CacheInterface::*;
import Vector::*;
// typedef Bit#(32) Word;
import Node::*;
import Router::*;
import MessageTypes::*;
import MainMem::*;

(* synthesize *)
module mktop_pipelined(Empty);
    // Instantiate the dual ported memory   
    MainMem mainMem <- mkMainMem(); 
    FIFOF#(MainMemReq) memHostReq0 <- mkFIFOF();
    FIFOF#(MainMemResp) memHostResp0 <- mkFIFOF();
    FIFOF#(MainMemReq) memHostReq1 <- mkFIFOF();
    FIFOF#(MainMemResp) memHostResp1 <- mkFIFOF();
    FIFO#(Bit#(2)) mem_turn <- mkFIFO();
    Reg#(Bit#(2)) last_turn <- mkReg(0);

    let debug = True;
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM2PortBE#(Bit#(30), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    NodeInterface node0 <- mkNode(0, memHostReq0, memHostResp0);
    NodeInterface node1 <- mkNode(1, memHostReq1, memHostResp1);
    // Node core
    let core0 <- mkCore(0, node0);
    let core1 <- mkCore(1, node1);

    // NodeInterface node2 <- mkNode(2);
    // NodeInterface node3 <- mkNode(3);

    Router router0 <- mkRouter(0);
    Router router1 <- mkRouter(1);
    // Router router2 <- mkRouter(2);
    // Router router3 <- mkRouter(3);

    // initialize all routerNodes
    mkRouterNode(0, router0, node0);
    mkRouterNode(1, router1, node1);
    // mkRouterNode(2, router2, node2);
    // mkRouterNode(3, router3, node3);

    // connect routers
    Reg#(Maybe#(Flit)) r1_link3 <- mkReg(tagged Invalid);
    Reg#(Maybe#(Flit)) r0_link1 <- mkReg(tagged Invalid);
    // Reg#(Maybe#(Flit)) r0_link2 <- mkReg(tagged Invalid);
    // Reg#(Maybe#(Flit)) r2_link0 <- mkReg(tagged Invalid);
    // Reg#(Maybe#(Flit)) r3_link3 <- mkReg(tagged Invalid);
    // Reg#(Maybe#(Flit)) r2_link1 <- mkReg(tagged Invalid);
    // Reg#(Maybe#(Flit)) r3_link0 <- mkReg(tagged Invalid);
    // Reg#(Maybe#(Flit)) r1_link2 <- mkReg(tagged Invalid);


    (*descending_urgency="node0.cacheD.handleWaitFill, core0.requestD"*)
    (*descending_urgency="node0.cacheD.afterCAUInMsgReq, core0.requestD"*)
    (*descending_urgency="node0.cacheI.handleWaitFill, core0.requestI"*)
    (*descending_urgency="node0.cacheI.afterCAUInMsgReq, core0.requestI"*)
    
    (*descending_urgency="node1.cacheD.handleWaitFill, core1.requestD"*)
    (*descending_urgency="node1.cacheD.afterCAUInMsgReq, core1.requestD"*)
    (*descending_urgency="node1.cacheI.handleWaitFill, core1.requestI"*)
    (*descending_urgency="node1.cacheI.afterCAUInMsgReq, core1.requestI"*)
    

    rule routerPut;
        if(r1_link3 matches tagged Valid .flit) begin 
            router0.dataLinks[1].putFlit(flit);
            if(debug) $display("router0.dataLinks[1].putFlit(flit)");
            r1_link3 <= tagged Invalid;
        end 

        if(r0_link1 matches tagged Valid .flit) begin 
            router1.dataLinks[3].putFlit(flit);
            if(debug) $display("router1.dataLinks[3].putFlit(flit)");
            r0_link1 <= tagged Invalid;
        end 
        /*
        if(r0_link2 matches tagged Valid .flit) begin 
            router0.dataLinks[2].putFlit(flit);
            r0_link2 <= tagged Invalid;
        end 

        if(r2_link0 matches tagged Valid .flit) begin 
            router2.dataLinks[0].putFlit(flit);
            r2_link0 <= tagged Invalid;
        end 

        if(r3_link3 matches tagged Valid .flit) begin 
            router3.dataLinks[3].putFlit(flit);
            r3_link3 <= tagged Invalid;
        end 

        if(r2_link1 matches tagged Valid .flit) begin 
            router2.dataLinks[1].putFlit(flit);
            r2_link1 <= tagged Invalid;
        end 

        if(r3_link0 matches tagged Valid .flit) begin 
            router3.dataLinks[0].putFlit(flit);
            r3_link0 <= tagged Invalid;
        end 

        if(r1_link2 matches tagged Valid .flit) begin 
            router1.dataLinks[2].putFlit(flit);
            r1_link2 <= tagged Invalid;
        end
        */ 

    endrule
    rule routerGet;
        // W -> E  
        if(router1.dataLinks[3].hasFlit()) begin
            if(debug) $display("Router get flit outer1.dataLinks[3]");
            let flit <- router1.dataLinks[3].getFlit();
            r1_link3 <= tagged Valid flit;
            // router0.dataLinks[1].putFlit(flit);
        end 
        
        // // E -> W  
        if(router0.dataLinks[1].hasFlit()) begin
            if(debug) $display("Router get flit router0.dataLinks[1]");
            let flit <- router0.dataLinks[1].getFlit();
            r0_link1 <= tagged Valid flit;
            // router1.dataLinks[3].putFlit(flit);
        end 

        /*
        // N -> S  
        if(router2.dataLinks[0].hasFlit()) begin
            let flit <- router2.dataLinks[0].getFlit();
            r0_link2 <= tagged Valid flit;
            // router0.dataLinks[2].putFlit(flit);
        end

        // // S -> N  
        if(router0.dataLinks[2].hasFlit()) begin
            let flit <- router0.dataLinks[2].getFlit();
            r2_link0 <= tagged Valid flit;
        //     router2.dataLinks[0].putFlit(flit);
        end 

        // // E -> W  
        if(router2.dataLinks[1].hasFlit()) begin
            let flit <- router2.dataLinks[1].getFlit();
            r3_link3 <= tagged Valid flit;
        //     router3.dataLinks[3].putFlit(flit);
        end
        
        // // W -> E  
        if (router3.dataLinks[3].hasFlit()) begin
            let flit <- router3.dataLinks[3].getFlit();
            r2_link1 <= tagged Valid flit;
        //     router2.dataLinks[1].putFlit(flit);
        end

        // // S -> N  
        if(router1.dataLinks[2].hasFlit()) begin
            let flit <- router1.dataLinks[2].getFlit();
            r3_link0 <= tagged Valid flit;
        //     router3.dataLinks[0].putFlit(flit);
        end

        // // N -> S  
        if(router3.dataLinks[0].hasFlit()) begin
            let flit <- router3.dataLinks[0].getFlit();
            r1_link2 <= tagged Valid flit;
        //     router1.dataLinks[2].putFlit(flit);
        end
        */
    endrule

    rule getMemReq if(memHostReq0.notEmpty || memHostReq1.notEmpty);
        if (memHostReq0.notEmpty && ( last_turn !=0 || !memHostReq1.notEmpty )) begin
            mainMem.put(memHostReq0.first);
            memHostReq0.deq;
            mem_turn.enq(0);
            last_turn <= 0;
        end else
        if (memHostReq1.notEmpty  && ( last_turn !=1 || !memHostReq0.notEmpty )) begin
            mainMem.put(memHostReq1.first);
            memHostReq1.deq;
            mem_turn.enq(1);
            last_turn <= 1;
        end
    endrule

    rule putMemResp;
        let resp_ <- mainMem.get();
        let turn = mem_turn.first; mem_turn.deq;
        if(turn == 0) begin
            memHostResp0.enq(resp_);
        end else
        if(turn == 1) begin
            memHostResp1.enq(resp_);
        end
    endrule


endmodule
