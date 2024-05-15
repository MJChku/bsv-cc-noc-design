// Types used in L1 interface
    import Vector :: * ;
    typedef struct { 
        Bit#(1) write; 
        Bit#(26) addr; 
        Bit#(512) data; 
    } MainMemReq deriving (Eq, FShow, Bits, Bounded);
    
    typedef struct { 
        Bit#(4) word_byte; 
        Bit#(32) addr; 
        Bit#(32) data; 
    } CacheReq deriving (Eq, FShow, Bits, Bounded);
    
    typedef Bit#(512) MainMemResp;
    
    typedef MainMemReq OutterMemReq;
    typedef MainMemResp OutterMemResp;
    
    
    typedef Bit#(32) Word;
    
    // (Curiosity Question: CacheReq address doesn't actually need to be 32 bits. Why?)
    
    // Helper types for implementation (L1 cache):
    // typedef enum {
    //     I,
    //     S,
    //     M
    // } LineState deriving (Eq, Bits, FShow);
    
    typedef enum {
        Invalid,
        Clean,
        Dirty
    } LineState deriving (Eq, Bits, FShow);
    
    // You should also define a type for LineTag, LineIndex. Calculate the appropriate number of bits for your design.
    // typedef ??????? LineTag
    // typedef ??????? LineIndex
    // You may also want to define a type for WordOffset, since multiple Words can live in a line.
    
    // It has 128 cache lines, each line is 512-bits long, made up of 32 bit words.
    // 128 = 2^7, so we need 7 bits for the index.
    // 512/32 = 16, so we need 4 bits for the word offset.
    // 2 bit for the bytes into word (since 4 bytes in a word)
    // the remaining 19 bits are for the tag. 
    // 512 bit is 64 byte so 6 bits for the byte offset
    typedef Bit#(19) LineTag;
    typedef Bit#(7) LineIndex;
    typedef Bit#(4) WordOffset;
    
    // You can translate between Vector#(16, Word) and Bit#(512) using the pack/unpack builtin functions.
    // typedef Vector#(16, Word) LineData  (optional)
    typedef Vector#(16, Word) LineData;
    typedef LineData CacheLine;
    typedef Bit#(512) LineDataL2;
    
    // Optional: You may find it helpful to make a function to parse an address into its parts.
    // e.g.,
    typedef struct {
        LineTag tag;
        LineIndex index;
        WordOffset offset;
    } ParsedAddress deriving (Bits, Eq);
    
    function ParsedAddress parseAddress(Bit#(32) address);
        return ParsedAddress{
            tag : address[31: 13],
            index : address[12: 6],
            offset : address[5: 2]
        };
    endfunction
    
    typedef Bit#(18) LineTagL2;
    typedef Bit#(8) LineIndexL2;
    
    typedef struct {
        LineTagL2 tag;
        LineIndexL2 index;
    } ParsedAddressL2 deriving (Bits, Eq);
    
    // tag bit is 26-8 = 18 bits because 256 cache lines
    function ParsedAddressL2 parseAddressL2(Bit#(26) address);
        return ParsedAddressL2{
            tag : address[25: 8],
            index : address[7: 0]
        };
    endfunction
    
    // and define whatever other types you may find helpful.
    
    // Helper types for implementation (L2 cache):