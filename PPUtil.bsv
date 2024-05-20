import MemTypes::*;
import FIFO::*;
import SpecialFIFOs::*;
import CacheTypes::*;
import Vector::*;

typedef Bit#(7) DirIdxWidth;

typedef 2 NUM_CORES;

function Bool myPartition(Addr addr, Bit#(2) nth_node);
    return addr[7:7] == nth_node[0];
endfunction 

function Bool check_all_invalid(ChState chs);
    Bool ans = True;
    for (Integer i = 0; i < 2; i = i + 1) begin
        if (chs.state[i] != I)
            ans = False;
    end
    return ans;
endfunction

function DirIdxWidth getDirectoryIdx(Addr addr, Bit#(2) nth_node);
        // 12:6 7 bits for the cache index 
        // originally 9:2 now the last 2 bits are to different the nodes
        // probably split L2 in this fashion as well.
        // if (myPartition(addr, nth_node)) begin
        //     $display("ERROR: not my parition");
        // end
        return addr[6:0];
endfunction    


typedef Bit#(19) CacheTag;

function CacheTag getTag(Addr addr);
    return addr[25:7];
endfunction

// function Maybe#(ChState) getDirectoryState(Addr req, Bit#(2) nth_node, Vector#(1024, Reg#(CacheTag)) childTag, Vector#(1024, Reg#(ChState)) childState);
//     let idx = getDirectoryIdx(req, nth_node);
//     if (idx matches tagged Valid .i) begin
//         if ( childTag[i] == getTag(req))
//             return tagged Valid childState[i];
//         else
//             return tagged Invalid;
//     end
//     else 
//         return tagged Invalid;
// endfunction

typedef enum { Ready, Blocked} PPState deriving(Bits, Eq);

function Bool calWaitForOtherCores(CoreID core, CacheMemReq m, ChState chs);
    Bool need_to_wait = False;
    // function
    // assert(m.state > I);
    // if (m.state > I)
    //     $display("Error: invalid state m.state > I");
    if (chs.state[core] == m.state) begin
        // the requesting core already have the rights
        // assert(0);
        //$display("Error: core %d already have the rights", core);
    end
    else if (m.state == M && chs.state[core] < M) begin 
        for (Integer i = 0; i < valueOf(NUM_CORES); i = i + 1) begin
            Bit#(2) m_id = fromInteger(i);
            // want M, then everyone else should be in I
            if(m_id != core && ( 
                chs.state[m_id] > I
            )) begin
                // $display("core %d need to wait for core %d because want M, and m_id has ", core, m_id, fshow(chs.state[m_id]));
                need_to_wait = True;
            end 
        end
    end 
    else if (m.state == S && chs.state[core] < S) begin
        for (Integer i = 0; i < valueOf(NUM_CORES); i = i + 1) begin
            Bit#(2) m_id = fromInteger(i);
            // larger than my destination state
            if(m_id != core && 
                chs.state[m_id]==M
            ) begin
                // $display("core %d need to wait for core %d because I want S, and m_id has ", core, m_id, fshow(chs.state[m_id]));
                need_to_wait = True;
            end 
        end
    end 
    return need_to_wait;
endfunction