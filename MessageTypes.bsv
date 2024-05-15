/*
 Message Types
 Author: Hyoukjun Kwon(hyoukjun@gatech.edu)

*/


/********** Native Libraries ************/
import Vector::*;
/******** User-Defined Libraries *********/
import Types::*;
import VirtualChannelTypes::*;
import RoutingTypes::*;
import CacheTypes::*;

/************* Definitions **************/

//1. Sub-definitions for Flit class
  //Message class and Flit types
  typedef Data FlitData;

  // Flit Type
  typedef struct {
    CoreID dest;    
    Direction nextDir; // Used for arbitration
    FlitData  flitData;   // The actual data.
  } Flit deriving (Bits, Eq);

/* Bundles */
// typedef Vector#(NumPorts, Maybe#(Header))   HeaderBundle;
typedef Vector#(NumPorts, Flit)     FlitBundle;

