// PIPELINED SINGLE CORE PROCESSOR WITH 2 LEVEL CACHE
import RVUtil::*;
import BRAM::*;
import pipelined::*;
import FIFO::*;
import SpecialFIFOs::*;
import MemTypes::*;
import CacheInterface::*;
import Vector::*;
// typedef Bit#(32) Word;
import Node::*;
import Router::*;
import MessageTypes::*;

module mktop_pipelined(Empty);
    // Instantiate the dual ported memory
    let debug = False;
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM2PortBE#(Bit#(30), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    // Node cache <- mkCacheInterface();
    NodeInterface node0 <- mkNode(0);
    NodeInterface node1 <- mkNode(1);
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

    // only node0 is connected to a core
    RVIfc rv_core <- mkpipelined;
    FIFO#(Mem) ireq <- mkFIFO;
    FIFO#(Mem) dreq <- mkFIFO;
    FIFO#(Mem) mmioreq <- mkFIFO;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule

    rule requestI;
        let req <- rv_core.getIReq;
        if (debug) $display("Get IReq cycle count %d", cycle_count, fshow(req));
        ireq.enq(req);
        node0.cacheinterface.sendReqInstr(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseI;
        let x <- node0.cacheinterface.getRespInstr();
        let req = ireq.first();
        ireq.deq();
        if (debug) $display("Get IResp %d ",  cycle_count, fshow(req), fshow(x));
        req.data = x;
        rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq;
        if (req.byte_en == 0) begin
            dreq.enq(req);
        end
        if (debug) $display("Get DReq", fshow(req));
        node0.cacheinterface.sendReqData(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    // rule requestD;
    //     let req <- rv_core.getDReq;
    //     dreq.enq(req);
    //     if (debug) $display("Get DReq", fshow(req));
    //     // $display("DATA ",fshow(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data}));
    //     cache.sendReqData(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    // endrule

    rule responseD;
        let x <- node0.cacheinterface.getRespData();
        let req = dreq.first();
        dreq.deq();
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getDResp(req);
    endrule
  
    rule requestMMIO;
        let req <- rv_core.getMMIOReq;
        if (debug) $display("Get MMIOReq", fshow(req));
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
                $display("RAN CYCLES", cycle_count);

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
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule


endmodule
