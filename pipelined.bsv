import FIFO::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import Ehr::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
    method ActionValue#(Mem) getIReq();
    method Action getIResp(Mem a);
    method ActionValue#(Mem) getDReq();
    method Action getDResp(Mem a);
    method ActionValue#(Mem) getMMIOReq();
    method Action getMMIOResp(Mem a);
endinterface
typedef struct { Bool isUnsigned; Bit#(2) size; Bit#(2) offset; Bool mmio; } MemBusiness deriving (Eq, FShow, Bits);

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        default: False;
    endcase;
    return x;
endfunction

typedef struct { Bit#(32) pc;
                 Bit#(32) ppc;
                 Bit#(1) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

interface Scoreboard#(numeric type n);
    method Action insert(Bit#(5) src_idx);
    method Action remove0(Bit#(5) src_idx);
    method Action remove1(Bit#(5) src_idx);
    method Bool search(Bit#(5) src_idx);
endinterface

module mkCFScoreboard (Scoreboard#(n));
    Vector#(n, Ehr#(3, Bool)) scoreboard <- replicateM(mkEhr(False));
    method Action insert(Bit#(5) src_idx);
        scoreboard[src_idx][2] <= True; 
    endmethod
    method Action remove0(Bit#(5) src_idx);
        scoreboard[src_idx][0] <= False;
    endmethod
    method Action remove1(Bit#(5) src_idx);
        scoreboard[src_idx][1] <= False;
    endmethod
    method Bool search(Bit#(5) src_idx);
        return scoreboard[src_idx][2];
    endmethod
endmodule

interface NextAddrIfc#(numeric type n, numeric type tagbits);
    method Action update(Bit#(32) pc, Bit#(32) ppc, Bool taken);
    method Bit#(32) nap(Bit#(32) pc);
endinterface


module mkBTB(NextAddrIfc#(n, tagbits));
    Vector#(TExp#(n), Ehr#(2, Bit#(tagbits))) tag <- replicateM(mkEhr(0));
    Vector#(TExp#(n), Ehr#(2, Bit#(32))) target <- replicateM(mkEhr(0));
    Vector#(TExp#(n), Ehr#(2, Bool)) valid <- replicateM(mkEhr(False));
    
    function Bit#(n) ext_idx(Bit#(32) pc);
        return pc[valueof(n)+1:2];
    endfunction
    
    function Bit#(tagbits) ext_tag(Bit#(32) pc);
        return pc[valueof(n)+valueof(tagbits)+1:valueof(n)+2];
    endfunction

    
    method Action update(Bit#(32) pc, Bit#(32) ppc, Bool taken);
        let idx = ext_idx(pc);
        if (taken) begin
            tag[idx][0] <= ext_tag(pc);
            target[idx][0] <= ppc;
            valid[idx][0] <= True;
        end
        else begin
            valid[idx][0] <= False;
        end
    endmethod

    method Bit#(32) nap(Bit#(32) pc);
        let idx = ext_idx(pc);
        if (valid[idx][1] && tag[idx][1] == ext_tag(pc)) begin
            return target[idx][1];
        end
        else begin
            return pc+4;
        end
    endmethod
endmodule

module mkNPipelineFIFO (FIFO#(a)) provisos (Bits#(a, b));
    Vector#(2, FIFO#(a)) fifos <- replicateM(mkPipelineFIFO);
    Reg#(Bit#(1)) enq_turn <- mkReg(0);
    Reg#(Bit#(1)) deq_turn <- mkReg(0);
    method Action enq(a x);
        fifos[enq_turn].enq(x);
        enq_turn <= enq_turn+1;
    endmethod
    method Action deq;
        fifos[deq_turn].deq();
        deq_turn <= deq_turn+1;
    endmethod
    method a first;
        let resp_ = fifos[deq_turn].first();
        return resp_;
    endmethod

    method Action clear();
        for (int i = 0; i < 2; i=i+1) begin
            fifos[i].clear();
        end
    endmethod
endmodule

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem) toImem <- mkBypassFIFO;
    FIFO#(Mem) fromImem <- mkBypassFIFO;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;
    Scoreboard#(32) scoreboard <- mkCFScoreboard;
    NextAddrIfc#(6, 5) btb <- mkBTB;

    FIFO#(F2D) f2d <- mkFIFO;
    FIFO#(D2E) d2e <- mkFIFO;
    FIFO#(E2W) e2w <- mkFIFO;

    // Reg#(Bit#(32)) pc <- mkReg(32'h0000000);
    Ehr#(3, Bit#(32)) pc <- mkEhr(32'h0000000);
    Vector#(32, Ehr#(2, Bit#(32))) rf <- replicateM(mkEhr(32'h0000000));
    
    // make it EHR
    // Reg#(Bit#(1)) epoch <- mkReg(0);
    Ehr#(2, Bit#(1)) epoch <- mkEhr(1'b0);
    
    Reg#(Bit#(32)) count <- mkReg(0);
	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);

	FIFO#(KonataId) retired <- mkFIFO;
	FIFO#(KonataId) squashed <- mkFIFO;

    Bool debug = False;
    Reg#(Bool) starting <- mkReg(True);
	rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
		konataTic(lfh);
	endrule

    rule count_up;
        count <= count + 1;
    endrule
		
    rule fetch if (!starting);
        Bit#(32) pc_fetched = pc[2];
        pc[2] <= btb.nap(pc[2]);
        // pc[2] <= pc[2]+4;
        // $display("[Fetch] ", count);
        // Below is the code to support Konata's visualization
		let iid <- fetch1Konata(lfh, fresh_id, 0);
        labelKonataLeft(lfh, iid, $format("0x%x: ", pc_fetched));
        let req = Mem {byte_en : 0,
			   addr : pc_fetched,
			   data : 0};
        toImem.enq(req); 
        f2d.enq(F2D{
            pc: pc_fetched,
            ppc: btb.nap(pc[2]),
            epoch: epoch[1],
            k_id: iid
        });    
        // iid is the unique identifier used by konata, that we will pass around everywhere for each instruction
    endrule

    rule decode if (!starting);
        // TODO
        let from_fetch = f2d.first(); 
        let resp = fromImem.first(); 
        // instr is 32bits
        let instr = resp.data;
        let decodedInst = decodeInst(instr);
        decodeKonata(lfh, from_fetch.k_id);
        labelKonataLeft(lfh, from_fetch.k_id, $format("DASM(%x)", instr));  // inserts the DASM id into the intermediate file
        if (debug) $display("[Decode] ", fshow(decodedInst));
        let rs1_idx = getInstFields(instr).rs1;
        let rs2_idx = getInstFields(instr).rs2;
        let rd_idx = getInstFields(instr).rd;
        // do you need to check if it's valid or uses rs1, rs2?
        // can I assume that if it doesn't use rs1/rs2, it's set to 0 ? 
        // read-after-write hazard
        
        let rs1_stall = (rs1_idx == 0 ? False : scoreboard.search(rs1_idx));
		let rs2_stall = (rs2_idx == 0 ? False : scoreboard.search(rs2_idx));
        //write-after-write hazard
        let rd_stall = (rd_idx == 0 ? False : scoreboard.search(rd_idx));
        if (debug) $display("[Decode] rd-stall ", rd_stall, " ", rd_idx);
        if (debug) $display("[Decode] rs1-stall ", rs1_stall, " ", rs1_idx);
        if (debug) $display("[Decode] rs2-stall ", rs2_stall, " ", rs2_idx);
        if (!decodedInst.valid_rs1)
            rs1_stall = False;
        if (!decodedInst.valid_rs2)
            rs2_stall = False;
        if (!decodedInst.valid_rd)
            rd_stall = False;

        // reading now is fine, because hazard is reset at write, both write and reset 
        // finishs after one cycle, and when read, the data is written
        let rs1 = (rs1_idx == 0 ? 0 : rf[rs1_idx][1]);
		let rs2 = (rs2_idx == 0 ? 0 : rf[rs2_idx][1]);

        // anyway the insn is not valid, even if should be stalled, doesn't matter
        if(!rs1_stall && !rs2_stall && !rd_stall) begin
            f2d.deq(); 
            fromImem.deq();
            d2e.enq(D2E{
                dinst: decodedInst,
                pc: from_fetch.pc,
                ppc: from_fetch.ppc,
                epoch: from_fetch.epoch,
                rv1: rs1,
                rv2: rs2,
                k_id: from_fetch.k_id
            });
            
            // register scoreboard
            if(rd_idx != 0 && decodedInst.valid_rd) begin
                scoreboard.insert(rd_idx);
                if (debug) $display("[Decode] register-rd-stall ", rd_idx);
                
            end
        end

        // To add a decode event in Konata you will likely do something like:
        //  let from_fetch = f2d.first();
   	    //	decodeKonata(lfh, from_fetch.k_id);
        //  labelKonataLeft(lfh,from_fetch.k_id, $format("Any information you would like to put in the left pane in Konata, attached to the current instruction"));
    endrule

    rule execute if (!starting);
        // TODO
       
        let from_decode = d2e.first(); d2e.deq(); 
        let dInst = from_decode.dinst;
        let rv1 = from_decode.rv1;
        let rv2 = from_decode.rv2;

        if (debug) $display("[Execute] ", fshow(dInst));
		executeKonata(lfh, from_decode.k_id);
        if (epoch[0] == from_decode.epoch) begin
            let imm = getImmediate(dInst);
            Bool mmio = False;
            let data = execALU32(dInst.inst, rv1, rv2, imm, from_decode.pc);
            let isUnsigned = 0;
            let funct3 = getInstFields(dInst.inst).funct3;
            let size = funct3[1:0];
            let addr = rv1 + imm;
            Bit#(2) offset = addr[1:0];
            if (isMemoryInst(dInst)) begin
                // Technical details for load byte/halfword/word
                let shift_amount = {offset, 3'b0};
                let byte_en = 0;
                case (size) matches
                2'b00: byte_en = 4'b0001 << offset;
                2'b01: byte_en = 4'b0011 << offset;
                2'b10: byte_en = 4'b1111 << offset;
                endcase
                data = rv2 << shift_amount;
                addr = {addr[31:2], 2'b0};
                isUnsigned = funct3[2];
                let type_mem = (dInst.inst[5] == 1) ? byte_en : 0;
                let req = Mem {byte_en : type_mem,
                        addr : addr,
                        data : data};
                if (isMMIO(addr)) begin 
                    if (debug) $display("[Execute] MMIO", fshow(req));
                    toMMIO.enq(req);
                    labelKonataLeft(lfh, from_decode.k_id, $format(" (MMIO)", fshow(req)));
                    mmio = True;
                end else begin 
                    labelKonataLeft(lfh, from_decode.k_id, $format(" (MEM)", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                    labelKonataLeft(lfh, from_decode.k_id, $format(" (CTRL)"));
                    data = from_decode.pc + 4;
            end else begin 
                labelKonataLeft(lfh, from_decode.k_id, $format(" (ALU)"));
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, from_decode.pc);
            let nextPc = controlResult.nextPC;
            // potentially conflict writes
            let mem_business = MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio};
            
            // redirect
            if (from_decode.ppc != nextPc) begin
                epoch[0] <= 1-epoch[0];
                pc[1] <= nextPc;
                btb.update(from_decode.pc, nextPc, controlResult.taken);
            end

            e2w.enq(E2W{
                mem_business: mem_business,
                data: data,
                dinst: dInst,
                k_id: from_decode.k_id
            });

        end 
        else begin
            // epoch doesn't match
            squashed.enq(from_decode.k_id);
            // // register scoreboard
            let rd_idx = getInstFields(dInst.inst).rd;
            if(rd_idx != 0) begin
                scoreboard.remove1(rd_idx);
                if (debug) $display("[Execute] remvoe dependency", rd_idx);
            end
        end

    	// Execute is also the place where we advise you to kill mispredicted instructions
    	// (instead of Decode + Execute like in the class)
    	// When you kill (or squash) an instruction, you should register an event for Konata:
       
        // redirect


    endrule

    rule writeback if (!starting);
        // TODO
        let from_execute = e2w.first(); e2w.deq();
        let mem_business = from_execute.mem_business;
        let dInst = from_execute.dinst;
        writebackKonata(lfh, from_execute.k_id);
        retired.enq(from_execute.k_id);
        let data = from_execute.data;
        let fields = getInstFields(dInst.inst);
        if (isMemoryInst(dInst)) begin // (* // write_val *)
            let resp = ?;
            if (mem_business.mmio) begin 
              resp = fromMMIO.first();
              fromMMIO.deq();
            end else begin 
                if (!isStoreInsn(dInst))begin 
                    resp = fromDmem.first();
                    fromDmem.deq();
                    let mem_data = resp.data;
                    mem_data = mem_data >> {mem_business.offset ,3'b0};
                    case ({pack(mem_business.isUnsigned), mem_business.size}) matches
                      3'b000 : data = signExtend(mem_data[7:0]);
                      3'b001 : data = signExtend(mem_data[15:0]);
                      3'b100 : data = zeroExtend(mem_data[7:0]);
                      3'b101 : data = zeroExtend(mem_data[15:0]);
                      3'b010 : data = mem_data;
                    endcase
                end
            end
        end
        if(debug) $display("[Writeback]", fshow(dInst));
            if (!dInst.legal) begin
          if (debug) $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(dInst));
                // TODO: make this pc[2]
          pc[0] <= 0;	// Fault
          end
        if (dInst.valid_rd) begin
                let rd_idx = fields.rd;
                if (rd_idx != 0) begin 
                    rf[rd_idx][0] <= data; 
                    scoreboard.remove0(rd_idx);
                    if (debug) $display("[Writeback] remvoe dependency", rd_idx);
                end
        end


        // Similarly, to register an execute event for an instruction:
	   	//	writebackKonata(lfh,k_id);


	   	// In writeback is also the moment where an instruction retires (there are no more stages)
	   	// Konata requires us to register the event as well using the following: 
		// retired.enq(k_id);
	endrule
		

	// ADMINISTRATION:

    rule administrative_konata_commit;
		    retired.deq();
		    let f = retired.first();
		    commitKonata(lfh, f, commit_id);
	endrule
		
	rule administrative_konata_flush;
		    squashed.deq();
		    let f = squashed.first();
		    squashKonata(lfh, f);
	endrule
		
    method ActionValue#(Mem) getIReq();
		toImem.deq();
		return toImem.first();
    endmethod
    method Action getIResp(Mem a);
    	fromImem.enq(a);
    endmethod
    // in one cycle, getDReq should happend after getDResp because execute happens after writeback
    method ActionValue#(Mem) getDReq();
		toDmem.deq();
		return toDmem.first();
    endmethod
    // in one cycle, getDResp should happend first because writeback happens first
    method Action getDResp(Mem a);
		fromDmem.enq(a);
    endmethod
    method ActionValue#(Mem) getMMIOReq();
		toMMIO.deq();
		return toMMIO.first();
    endmethod
    method Action getMMIOResp(Mem a);
		fromMMIO.enq(a);
    endmethod
endmodule
