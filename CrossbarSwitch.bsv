import Vector::*;
import Ehr::*;

import Types::*;
import MessageTypes::*;
import SwitchAllocTypes::*;
import RoutingTypes::*;


interface CrossbarPort;
  method Action putFlit(Flit traverseFlit, DirIdx destDirn);
  method ActionValue#(Flit) getFlit; 
endinterface

interface CrossbarSwitch;
  interface Vector#(NumPorts, CrossbarPort) crossbarPorts;
endinterface

(* synthesize *)
module mkCrossbarSwitch(CrossbarSwitch);
  /*
    implement the crossbar

    To define a vector of methods (with NumPorts*2 methods) you can use the following syntax:

  */
  // just use wire ?
  Vector#(NumPorts, Vector#(NumPorts, Ehr#(2, Maybe#(Flit)))) crossbarBuffer <- replicateM(replicateM(mkEhr(tagged Invalid)));

  Vector#(NumPorts, CrossbarPort) crossbarPortsConstruct;
  for (Integer ports=0; ports < valueOf(NumPorts); ports = ports+1) begin
    crossbarPortsConstruct[ports] =
      interface CrossbarPort
        method Action putFlit(Flit traverseFlit, DirIdx destDirn);
          crossbarBuffer[ports][destDirn][0] <= tagged Valid traverseFlit;
          //  body for your method putFlit[ports]
        endmethod
        method ActionValue#(Flit) getFlit;
          Flit ans = Flit{dest: ?, nextDir: null_, flitData:?};
          for (Integer i=0; i < valueOf(NumPorts); i = i+1) begin
            if (crossbarBuffer[i][ports][1] matches tagged Valid .v) begin
              ans = v;
              crossbarBuffer[i][ports][1] <= tagged Invalid;
            end
          end
          return ans;
          //  body for your method getFlit[ports]
        endmethod
      endinterface;
  end
  interface crossbarPorts = crossbarPortsConstruct;

endmodule
