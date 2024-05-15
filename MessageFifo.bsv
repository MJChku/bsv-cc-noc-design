import CacheTypes::*;
import FIFO::*;
import FIFOF::*;

// TODO: implement message FIFO

module mkMessageFifo(MessageFifo#(n));

    FIFOF#(CacheMemMessage) req_fifo <- mkSizedFIFOF(valueOf(n));
    FIFOF#(CacheMemMessage) resp_fifo <- mkSizedFIFOF(valueOf(n));

    method Action enq_resp( CacheMemResp d );
        resp_fifo.enq(tagged Resp d);
    endmethod

    method Action enq_req( CacheMemReq d );
        req_fifo.enq(tagged Req d);
    endmethod

    method Bool hasResp;
        return resp_fifo.notEmpty;
    endmethod
    method Bool hasReq;
        return req_fifo.notEmpty;
    endmethod

    method Bool notEmpty;
        return resp_fifo.notEmpty || req_fifo.notEmpty;
    endmethod 
    method CacheMemMessage first;
        if (resp_fifo.notEmpty)
            return resp_fifo.first;
        else
            return req_fifo.first;
    endmethod

    method Action deq;
        if(resp_fifo.notEmpty) begin
            resp_fifo.deq;
        end
        else begin
            req_fifo.deq;
        end
    endmethod

endmodule
