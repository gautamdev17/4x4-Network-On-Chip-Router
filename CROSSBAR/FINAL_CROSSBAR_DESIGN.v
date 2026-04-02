`timescale 1ns/1ps
// bro basically this is multiplexer, we are giving inputs to respective output lines
module crossbar #(parameter DATA_WIDTH=32) (input logic[2:0]selsignal[4:0],input logic [DATA_WIDTH-1:0]input_data[4:0],output logic [DATA_WIDTH-1:0]final_out[4:0]);
  genvar i;
  generate
  for(i=0;i<5;i=i+1)
    assign final_out[i] = (selsignal[i]==3'b111)?'0:input_data[selsignal[i]];
  endgenerate
endmodule
