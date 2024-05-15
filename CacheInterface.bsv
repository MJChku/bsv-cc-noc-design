// SINGLE CORE CACHE INTERFACE WITH NO PPP
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache512::*;
import FIFO::*;
import SpecialFIFOs::*;

interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();
endinterface
