import PPUtil::*;
import CacheTypes::*;
import Cache512::*;
import Vector::*;
import MemTypes::*;
import Assert::*;

typedef enum {InvalidateOthers, SendL2, WaitL2 } PPReqState deriving (Bits, Eq, FShow);

function ChState newChState();
    ChState chs = ?;
    for (Integer i = 0; i < 4; i = i+1) begin
        chs.state[i] = I;
        chs.status[i] = N;
    end
    return chs;
endfunction 

module mkProtocolProcessor(
    Bit#(2) nth_node, 
    MessageFifo#(6) inMsgQueue,
    MessageFifo#(6) outMsgQueue,
    Cache512 cacheL2, 
    Bit#(32) count,
    Empty ifc);

    // lets do NUM_CORES cores for now
    // the directory in total should keep the states of all L1 caches
    // which is 1(DCache only) * 2^7 * Ncores = 128*Ncores entries
   
    // Vector#(TMul#(128, valueOf(NUM_CORES)), Reg#(ChState)) childState <- replicateM(mkRegU);
    // Vector#(TMul#(128, valueOf(NUM_CORES)), Reg#(CacheTag)) childTag <- replicateM(mkRegU);
    Bool debug = True;
    // Vector#(128, Vector#(2, Reg#(ChState))) childState <- replicateM(replicateM(mkReg(init_ch)));
    // Vector#(128, Vector#(2, Reg#(CacheTag))) childTag <- replicateM(replicateM(mkRegU));
    MSIYN init_msiyn = MSIYN{state: I, status: N};
    Vector#(2, Vector#(128, Reg#(MSIYN))) childState <- replicateM(replicateM(mkReg(init_msiyn)));
    Vector#(2, Vector#(128, Reg#(CacheTag))) childTag <- replicateM(replicateM(mkRegU));

    /* -------- process InMsgReq ------- */     
    Reg#(PPReqState) ppReqState <- mkReg(InvalidateOthers);
    
    // (*descending_urgency="processInMsgReqReceiveL2, processInMsgReqWithOnlyL2Cache, processInMsgReqAndSendOutMsg"*)

    /* every upgrade request will force read L2 */
    // notice the problem here:
    // there are 4 caches, while they are directly indexed into the directory, 
    // what if the 4 caches all have the same index, but different cacheline, 
    // then the directory will be overwritten by other caches. 
    // hence need to store 4 tags, and 4 state for each index, corresponding to different caches; 

    rule processInMsgReqReceiveL2 if(inMsgQueue.first matches tagged Req .m &&& ppReqState == WaitL2);
        // request to upgrade
        if(debug) $display("<CoreId %d processInMsgReqReceiveL2> get resp from L2, cnt %d", nth_node, count);
        let core = m.core;
        
        DirIdxWidth idx = getDirectoryIdx(m.addr, nth_node);
        let tag = getTag(m.addr);
        //compute status on all cores;
        ChState chs = newChState();
        for (Integer i = 0; i < valueOf(NUM_CORES); i = i+1) begin
            if (childTag[i][idx] == tag) begin
                chs.state[i] = childState[i][idx].state;
                chs.status[i] = childState[i][idx].status;
            end
        end
        let all_invalid = check_all_invalid(chs);

        PPReqState req_state = InvalidateOthers;
        if (!all_invalid) begin
            Bool need_to_wait = calWaitForOtherCores(core, m, chs);
           
            if (need_to_wait==False) begin
                // need to read from L2 cache now
                let resp <- cacheL2.getToProc();
    
                childState[core][idx] <= MSIYN{state: m.state, status: N};
                childTag[core][idx] <= tag;
                if(debug) $display("<CoreId %d processInMsgReqReceiveL2> send out resp to Core %d, cnt %d", nth_node, m.core, count);
                inMsgQueue.deq;
                outMsgQueue.enq_resp(
                    CacheMemResp{
                        fromChild: 0,
                        core: core,
                        addr: m.addr, 
                        state: m.state,
                        data: tagged Valid unpack(resp) // cacheline
                    }
                );
            end else begin
                //this should never happen ; at previous stage, we checked we don't need to wait for anything
                req_state = WaitL2;
            end
        end
        else begin
            // No one has the cache
            let resp <- cacheL2.getToProc();
            childState[core][idx] <= MSIYN{state: m.state, status: N};
            childTag[core][idx] <= tag;
            inMsgQueue.deq;
            if(debug) $display("<CoreId %d processInMsgReqReceiveL2> (No one has the cacheline) send out resp to Core %d, cnt %d, state %d addr ", nth_node, m.core, count, m.state,fshow(m.addr));
            outMsgQueue.enq_resp(
                CacheMemResp{
                    fromChild: 0,
                    core: core,
                    addr: m.addr, 
                    state: m.state,
                    data: tagged Valid unpack(resp) // cacheline
                }
            );
        end
        $display("<CoreId %d processInMsgReqReceiveL2> final states ", nth_node, fshow(req_state));
        ppReqState <= req_state;

    endrule

    rule processInMsgReqWithOnlyL2Cache if(inMsgQueue.first matches tagged Req .m &&& ppReqState == SendL2 );
        // request to upgrade
        let core = m.core;
        if(debug) $display("<CoreId %d processInMsgReqWithOnlyL2Cache> send req to L2 %d, cnt %d", nth_node, m.core, count);
        
        DirIdxWidth idx = getDirectoryIdx(m.addr, nth_node);
        let tag = getTag(m.addr);
        //compute status on all cores;
        ChState chs = newChState();
        for (Integer i = 0; i < valueOf(NUM_CORES); i = i+1) begin
            if (childTag[i][idx] == tag) begin
                chs.state[i] = childState[i][idx].state;
                chs.status[i] = childState[i][idx].status;
            end
        end

        let all_invalid = check_all_invalid(chs);

        PPReqState req_state = WaitL2;
        if (!all_invalid) begin
            Bool need_to_wait = calWaitForOtherCores(core, m, chs);
            $display("<CoreId %d >core %d need to wait for other cores? %d old %d, need %d", nth_node, core, need_to_wait, chs.state[core], m.state);
           
            if (need_to_wait == False) begin
                // need to read from L2 cache now
                cacheL2.putFromProc(MainMemReq{
                    write: 0,
                    addr: m.addr,
                    data: ?
                });
            end else
                req_state = SendL2;
        end 
        else begin
            // invalid directory entry
            if(debug) $display("<CoreId %d processInMsgReqWithOnlyL2Cache> No one has the cacheline and fetch from self L2 ", nth_node);
            cacheL2.putFromProc(MainMemReq{
                    write: 0,
                    addr: m.addr,
                    data: ?
                });
        end
        if(debug) $display("<CoreId %d processInMsgReqWithOnlyL2Cache> final states ", nth_node, fshow(req_state));
        ppReqState <= req_state;

    endrule

    rule processInMsgReqAndSendOutMsg if (inMsgQueue.first matches tagged Req .m &&& ppReqState == InvalidateOthers );
        // request to upgrade
        let core = m.core;
        if(debug) $display("<CoreId %d processInMsgReqAndSendOutMsg> received msg, dst state %d cnt %d coreid %d addr", nth_node, m.state, count, m.core, fshow(m.addr));
        // if you received a state update, you must own the directory for this cacheline
        // update the state in the cache
        if (!myPartition(m.addr, nth_node)) begin
            $display("ERROR: not my parition");
        end
        DirIdxWidth idx = getDirectoryIdx(m.addr, nth_node);
        let tag = getTag(m.addr);
        //compute status on all cores;
        ChState chs = newChState();
        for (Integer i = 0; i < valueOf(NUM_CORES); i = i+1) begin
            if (childTag[i][idx] == tag) begin
                chs.state[i] = childState[i][idx].state;
                chs.status[i] = childState[i][idx].status;
            end
        end
        let all_invalid = check_all_invalid(chs);

        PPReqState req_state = SendL2;
        if (!all_invalid) begin
            MSI dest_state = I;
            Bool send_msg_for_dwn_M = False;
            Bit#(2) m_id = 0;
            if ( m.state == M && chs.state[core] < M ) begin
                for (Integer i = 0; i <  valueOf(NUM_CORES); i = i + 1) begin
                    $display("<CoreId %d processInMsgReqAndSendOutMsg> check core %d, state %d, status %d", nth_node, i, chs.state[i], chs.status[i]);
                    Bit#(2) _id = fromInteger(i);
                    if(_id != core 
                    && chs.state[_id] > I 
                    && chs.status[_id] == N) 
                    begin
                        m_id = _id;
                        send_msg_for_dwn_M = True;    
                        dest_state = I;                        
                    end 
                end
            end else
            if (m.state == S && chs.state[core] < S) begin
                // read-access
                for (Integer i = 0; i <  valueOf(NUM_CORES); i = i + 1) begin
                    Bit#(2) _id = fromInteger(i);
                    if(_id != core 
                    && chs.state[_id] == M 
                    && chs.status[_id] == N) begin
                        m_id = _id;
                        send_msg_for_dwn_M = True;
                        dest_state = S;
                    end 
                end
            end
            if (send_msg_for_dwn_M == True) begin
                // request dwn grade the state to S
                $display("<CoreId %d processInMsgReqAndSendOutMsg> send out dwngrade (to %d) req to Core %d, cnt %d", nth_node, dest_state, m_id, count);
                req_state = InvalidateOthers;
                outMsgQueue.enq_req(
                    CacheMemReq{
                        fromChild: 0,
                        core: m_id,
                        addr: m.addr, // cacheline
                        state: dest_state // to shared state 
                    }
                );
                // remember we have sent out the request
                childState[m_id][idx].status <= Y;
            end
        end
        ppReqState <= req_state;
    endrule
    /* -------- process InMsgReq End----- */ 

    /* -------- process InMsgResp ------- */
    rule processInMsgResp if (inMsgQueue.first matches tagged Resp .m);
        // downgrade response
        let core = m.core;
        if(debug) $display("<CoreId %d processInMsgResp> received resp ", nth_node);
        
        if (!myPartition(m.addr, nth_node)) begin
            $display("ERROR: not my parition");
        end
        DirIdxWidth idx = getDirectoryIdx(m.addr, nth_node);
        let tag = getTag(m.addr);
        //compute status on all cores;
        ChState chs = newChState();
        for (Integer i = 0; i < valueOf(NUM_CORES); i = i+1) begin
            if (childTag[i][idx] == tag) begin
                chs.state[i] = childState[i][idx].state;
                chs.status[i] = childState[i][idx].status;
            end
        end
        let all_invalid = check_all_invalid(chs);

        if (!all_invalid) begin
            MSIYN new_msiyn = MSIYN{state: chs.state[core], status: N};
            $display("<CoreId %d processInMsgResp> received resp from Core %d, cnt %d, old %d, new %d", nth_node, core, count, chs.state[core], m.state);
            if (chs.state[core] <= m.state) begin 
                // its not dwngraded
                if(debug) $display("response not dwngraded");
                inMsgQueue.deq;
            end 
            else if (chs.state[core] == M && m.state < M) begin 
                // downgrade the state to S or I
                new_msiyn.state = m.state;
                // childState[core][idx].state <= m.state;

                inMsgQueue.deq;
                // write back dirty data to L2 cache
                if (m.data matches tagged Valid .dirty_data )
                    cacheL2.putFromProc(
                        MainMemReq{
                            write: 1,
                            addr: m.addr,
                            data: pack(dirty_data)
                        }
                    );
                else begin
                    $display("<CoreId %d>Error: dirty cacheline with no data in the response", nth_node);
                end
            end 
            else if (chs.state[core] == S && m.state < S) begin
                // downgrade the state to I
                new_msiyn.state = m.state;
                // childState[core][idx].state <= m.state;
                inMsgQueue.deq;
            end 
            childState[core][idx] <= new_msiyn;
            childTag[core][idx] <= tag;
        end // end of if 
        else begin
            $display("ERROR: <CoreId %d processInMsgResp> received resp from Core %d, cnt %d, old %d, new %d", nth_node, core, count, chs.state[core], m.state);
            // $display("<CoreId %d processInMsgResp> received resp from Core %d, cnt %d, old %d, new %d", nth_node, core, count, chs.state[core], m.state);
            // MSIYN new_msiyn = MSIYN{state: m.state, status: N};
            // childState[core][idx] <= new_msiyn;
            // childTag[core][idx] <= tag;

        end
    endrule
    /* -------- process InMsgResp End---- */


endmodule