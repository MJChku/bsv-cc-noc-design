import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import Ehr::*;
import Types::*;
import MessageTypes::*;
import RoutingTypes::*;

import CrossbarSwitch::*;
import MatrixArbiter::*;

import CacheTypes::*;

function Direction getRoutingInfo(CoreID self, CoreID dest);
    //   -------> X
    //  |
    //  |
    //  v Y
    Direction nextDir = local_;
    if (self == dest) nextDir = local_;
    let self_x = self[0]; let self_y = self[1];
    let dest_x = dest[0]; let dest_y = dest[1];
    if (self_x < dest_x) nextDir = east_;
    else if (self_x > dest_x) nextDir = west_;
    else if (self_y < dest_y) nextDir = south_;
    else if (self_y > dest_y) nextDir = north_;
    return nextDir;
endfunction

(* synthesize *)
module mkOutPortArbiter(NtkArbiter#(NumPorts));
    // We provide an implementation of a priority arbiter,
    // it gives you the following method: 
    // method ActionValue#(Bit#(numRequesters)) getArbit(Bit#(numRequesters) reqBit);
    // you send a bitvector of all the client that would like to access a resource,
    // and it selects one clients among all of them (returned in one-hot
    // encoding) You can look at the implementation in MatrixArbiter if you are
    // curious, but you could also use a more naive implementation that does not
    // record previous requests
    
    Integer n = valueOf(NumPorts);
    NtkArbiter#(NumPorts)	matrixArbiter <- mkMatrixArbiter(n);
    return matrixArbiter;
endmodule

typedef Vector#(NumPorts, Direction)  ArbReq;
typedef Vector#(NumPorts, Direction)  ArbReqBits;
typedef Bit#(NumPorts)                ArbRes;

interface DataLink;
    method Bool hasFlit;
    method ActionValue#(Flit)         getFlit;
    method Action                     putFlit(Flit flit);
endinterface

interface Router;
    method Bool isInited;
    interface Vector#(NumPorts, DataLink)    dataLinks;
endinterface

function DirIdx dirToPort(Direction dir);
    case(dir)
        north_: return 3'b000;
        east_: return 3'b001;
        south_: return 3'b010;
        west_: return 3'b011;
        local_: return 3'b100;
        default: return 3'b111;
    endcase
endfunction

(* synthesize *)
module mkRouter#(Bit#(2) nth_node)(Router);

    /********************************* States *************************************/
    Reg#(Bool)                                inited         <- mkReg(False);
  
    FIFO#(ArbRes)                             arbResBuf      <- mkBypassFIFO;
    Vector#(NumPorts, FIFOF#(Flit))           inputBuffer    <- replicateM(mkSizedBypassFIFOF(4));
    Vector#(NumPorts, NtkArbiter#(NumPorts))  outPortArbiter <- replicateM(mkOutPortArbiter);
    CrossbarSwitch                            cbSwitch       <- mkCrossbarSwitch;
    Vector#(NumPorts, FIFOF#(Flit))           outputLatch   <- replicateM(mkSizedBypassFIFOF(1));
    
    rule doInitialize(!inited);
        // Some initialization for the priority arbiters
        for(Integer outPort = 0; outPort < valueOf(NumPorts); outPort = outPort+1) begin
            outPortArbiter[outPort].initialize;
        end
        inited <= True;
    endrule 


    rule rl_Switch_Arbitration(inited);
      
        /*
            Please implement the Switch Arbitration stage here
            push into arbResBuf
        */ 
        ArbRes res = unpack(0);
        for (Integer outPort = 0; outPort < valueOf(NumPorts); outPort = outPort+1) begin
            Bit#(NumPorts) reqBits = unpack(0);
            for (Integer inPort = 0; inPort < valueOf(NumPorts); inPort = inPort+1) begin
                reqBits[inPort] = inputBuffer[inPort].notEmpty && dirToPort(inputBuffer[inPort].first().nextDir) == fromInteger(outPort) ? 1'b1 : 1'b0;
            end
            let res_ <- outPortArbiter[outPort].getArbit(reqBits);
            res = res | res_;
        end
        arbResBuf.enq(res);
    endrule


    rule rl_Switch_Traversal(inited);
        /*
           deq arbResBuf
           Read the input winners, and push them to the crossbar
        */ 
        let arbRes = arbResBuf.first(); arbResBuf.deq();
        for (Integer inPort = 0; inPort < valueOf(NumPorts); inPort = inPort+1) begin
            if (arbRes[inPort]==1'b1) begin
                Flit flit = inputBuffer[inPort].first();
                inputBuffer[inPort].deq();
                let outDir = flit.nextDir;
                let outPort = dirToPort(outDir);
                cbSwitch.crossbarPorts[inPort].putFlit(flit, outPort);
            end
        end
    endrule
    
    for(Integer outPort=0; outPort<valueOf(NumPorts); outPort = outPort+1)
    begin
        rule rl_enqOutLatch(inited);
            // Use several rules to dequeue from the cross bar output and push into the output ports queues 
            // check the flit is valid
            Flit flit <- cbSwitch.crossbarPorts[outPort].getFlit;
            if (flit.nextDir != null_) begin
                outputLatch[outPort].enq(flit);
            end
        endrule
    end

    /***************************** Router Interface ******************************/

    Vector#(NumPorts, DataLink) dataLinksDummy;
    for(DirIdx prt = 0; prt < fromInteger(valueOf(NumPorts)); prt = prt+1)
    begin
        dataLinksDummy[prt] =

        interface DataLink
            method Bool hasFlit;
                return outputLatch[prt].notEmpty;
            endmethod
            method ActionValue#(Flit) getFlit if(outputLatch[prt].notEmpty);
                Flit retFlit = outputLatch[prt].first();
                outputLatch[prt].deq();
                return retFlit;
            endmethod

            method Action putFlit(Flit flit) if(inputBuffer[prt].notFull);
                flit.nextDir = getRoutingInfo(nth_node, flit.dest);
                inputBuffer[prt].enq(flit);
            endmethod
        endinterface;
    end 

    interface dataLinks = dataLinksDummy;

    method Bool isInited;
        return inited; 
    endmethod

endmodule
