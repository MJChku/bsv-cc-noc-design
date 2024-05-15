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

    ChState init_ch = newChState();
    Vector#(128, Reg#(ChState)) childState <- replicateM(mkReg(init_ch));
    Vector#(128, Reg#(CacheTag)) childTag <- replicateM(mkRegU);

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
        $display("<processInMsgReqReceiveL2> get resp from L2 %d, my node is %d, cnt %d", m.core, nth_node, count);
        let core = m.core;
        // Maybe#(Bit#(7)) idx_ = tagged Valid 0; //getDirectoryIdx(m.addr, nth_node);
        Maybe#(Bit#(7)) idx_ = getDirectoryIdx(m.addr, nth_node);
        DirIdxWidth idx = 0;
        Maybe#(ChState) maybe_s = ?;
        
        PPReqState req_state = InvalidateOthers;

        if (idx_ matches tagged Valid .i) begin
            idx = i; 
            if ( childTag[i] == getTag(m.addr))
                maybe_s = tagged Valid childState[i];
            else
                maybe_s = tagged Invalid;
        end
        else 
            maybe_s = Invalid;

        if (maybe_s matches tagged Valid .chs) begin
            Bool need_to_wait = calWaitForOtherCores(core, m, chs);
           
            if (need_to_wait==False) begin
                // need to read from L2 cache now
                let resp <- cacheL2.getToProc();
                let chs_copy = chs;
                chs_copy.state[core] = m.state;
                childState[idx] <= chs_copy;
                $display("<processInMsgReqReceiveL2> send out resp %d, my node is %d, cnt %d", m.core, nth_node, count);

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
            $display("<processInMsgReqReceiveL2> No one has the cacheline");
            let resp <- cacheL2.getToProc();
            let chs_copy = newChState();
            chs_copy.state[core] = m.state;
            childState[idx] <= chs_copy;
            childTag[idx] <= getTag(m.addr);
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
        end
        ppReqState <= req_state;

    endrule

    rule processInMsgReqWithOnlyL2Cache if(inMsgQueue.first matches tagged Req .m &&& ppReqState == SendL2 );
        // request to upgrade
        let core = m.core;
        $display("<processInMsgReqWithOnlyL2Cache> send req to L2 %d, my node is %d; cnt %d", m.core, nth_node, count);
        // let idx = getDirectoryIdx(m.addr, nth_node);
        // let maybe_s = getDirectoryState(m.addr, nth_node, childTag, childState);

        Maybe#(ChState) maybe_s = ?;
        // let idx = getDirectoryIdx(m.addr, nth_node);
        // Maybe#(Bit#(7)) idx = tagged Valid 0;
        Maybe#(Bit#(7)) idx = getDirectoryIdx(m.addr, nth_node);

        PPReqState req_state = WaitL2;

        if (idx matches tagged Valid .i) begin
            if ( childTag[i] == getTag(m.addr))
                maybe_s = tagged Valid childState[i];
            else
                maybe_s = tagged Invalid;
        end
        else 
            maybe_s = Invalid;

        if (maybe_s matches tagged Valid .chs) begin
            Bool need_to_wait = calWaitForOtherCores(core, m, chs);
           
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
            $display("<processInMsgReqWithOnlyL2Cache> No one has the cacheline and fetch from L2 %d", nth_node);
            cacheL2.putFromProc(MainMemReq{
                    write: 0,
                    addr: m.addr,
                    data: ?
                });
        end
        ppReqState <= req_state;

    endrule

    rule processInMsgReqAndSendOutMsg if (inMsgQueue.first matches tagged Req .m &&& ppReqState == InvalidateOthers );
        // request to upgrade
        let core = m.core;
        $display("<processInMsgReqAndSendOutMsg> received msg from %d, my node is %d; cnt %d", m.core, nth_node, count);
        // if you received a state update, you must own the directory for this cacheline
        // update the state in the cache
        // let idx_ = getDirectoryIdx(m.addr, nth_node);
        // Maybe#(Bit#(7)) idx_ = tagged Valid 0;
        Maybe#(Bit#(7)) idx_ = getDirectoryIdx(m.addr, nth_node);
        DirIdxWidth idx = 0;
        Maybe#(ChState) maybe_s = ?;
        if (idx_ matches tagged Valid .i) begin
            idx = i; 
            if ( childTag[i] == getTag(m.addr))
                maybe_s = tagged Valid childState[i];
            else
                maybe_s = tagged Invalid;
        end
        else 
            maybe_s = Invalid;

        PPReqState req_state = SendL2;
        if (maybe_s matches tagged Valid .chs) begin
            if (m.state > I) 
                $display("Error: should never happen: m.state > I");
            if ( m.state == M && chs.state[core] < M ) begin
                Bool send_msg_for_dwn_M = False;
                Bit#(2) m_id = 0;
                for (Integer i = 0; i <  valueOf(NUM_CORES); i = i + 1) begin
                    if(fromInteger(i) != core 
                    && chs.state[m_id] > I 
                    && chs.status[m_id] == N) 
                    begin
                        m_id = fromInteger(i);
                        send_msg_for_dwn_M = True;                            
                    end 
                end

                // remember we can only enq once per cycle
                if (send_msg_for_dwn_M == True) begin
                    // enq DwnGrade Req
                    req_state = InvalidateOthers;
                    outMsgQueue.enq_req( 
                        CacheMemReq {
                            fromChild: 0,
                            core: m_id,
                            addr: m.addr, // cacheline
                            state: I
                        }
                    );
                    // request has been sent out
                    let chs_copy = chs;
                    chs_copy.status[m_id] = Y;
                    childState[idx] <= chs_copy;
                end
            end else
            if (m.state == S && chs.state[core] < S) begin
                // read-access
                Bit#(2) m_id = 0;
                Bool send_msg_for_dwn_M = False;
                for (Integer i = 0; i <  valueOf(NUM_CORES); i = i + 1) begin
                    if(fromInteger(i) != core 
                    && chs.state[m_id] == M 
                    && chs.status[m_id] == N) begin
                        m_id = fromInteger(i);
                        send_msg_for_dwn_M = True;
                    end 
                end
                if (send_msg_for_dwn_M == True) begin
                    // request dwn grade the state to S
                    req_state = InvalidateOthers;
                    outMsgQueue.enq_req(
                        CacheMemReq{
                            fromChild: 0,
                            core: m_id,
                            addr: m.addr, // cacheline
                            state: S // to shared state 
                        }
                    );
                    // remember we have sent out the request
                    let chs_copy = chs;    
                    chs_copy.status[m_id] = Y; 
                    childState[idx] <= chs_copy;
                end
            end
        end

        ppReqState <= req_state;
        // else begin
        //     // no one has the cache entry all is Invalid;
        //     // invalid directory entry
        //     // $display("<processInMsgReqAndSendOutMsg> Error: should never happen");
        // end 
    endrule
    /* -------- process InMsgReq End----- */ 

    /* -------- process InMsgResp ------- */
    rule processInMsgResp if (inMsgQueue.first matches tagged Resp .m);
        // downgrade response
        let core = m.core;
        $display("<processInMsgResp> received resp from %d, my node is ", m.core, nth_node);
        // let idx_ = getDirectoryIdx(m.addr, nth_node);
        // Maybe#(Bit#(7)) idx_ = tagged Valid 0;
        Maybe#(Bit#(7)) idx_ = getDirectoryIdx(m.addr, nth_node);
        DirIdxWidth idx = 0;
        Maybe#(ChState) maybe_s = ?;
        if (idx_ matches tagged Valid .i) begin
            idx = i; 
            if ( childTag[i] == getTag(m.addr))
                maybe_s = tagged Valid childState[i];
            else
                maybe_s = tagged Invalid;
        end
        else 
            maybe_s = Invalid;

        if (maybe_s matches tagged Valid .chs) begin
            if (chs.state[core] <= m.state) begin 
                // its not dwngraded
                $display("response not dwngraded");
                inMsgQueue.deq;
            end 
            else if (chs.state[core] == M && m.state < M) begin 
                // downgrade the state to S or I
                let chs_copy = chs;
                chs_copy.state[core] = m.state;
                childState[idx] <= chs_copy;
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
                else
                    dynamicAssert(0==1, "dirty cacheline with no data in the response");
            end 
            else if (chs.state[core] == S && m.state < S) begin
                // downgrade the state to I
                let chs_copy = chs;
                chs_copy.state[core] = m.state;
                childState[idx] <= chs_copy;
                inMsgQueue.deq;
            end 
        end // end of if 
        else begin
            $display("<processInMsgResp> Error: should never happen");
        end
    endrule
    /* -------- process InMsgResp End---- */


endmodule