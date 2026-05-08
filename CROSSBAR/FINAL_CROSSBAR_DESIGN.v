`timescale 1ns/1ps
module crossbar #(parameter DATA_WIDTH=32)
  (input [24:0] grant,
   input  [DATA_WIDTH-1:0] flit0,flit1,flit2,flit3,flit4,
   output reg [DATA_WIDTH-1:0] out_N,out_S,out_E,out_W,out_L);

  wire [DATA_WIDTH-1:0] flit [0:4];
  assign flit[0]=flit0; assign flit[1]=flit1; assign flit[2]=flit2;
  assign flit[3]=flit3; assign flit[4]=flit4;
  integer k;

  always @* begin // basically this is multiplexer, we are giving inputs to respective output lines
    out_N = {DATA_WIDTH{1'b0}};
    out_S = {DATA_WIDTH{1'b0}};
    out_E = {DATA_WIDTH{1'b0}};
    out_W = {DATA_WIDTH{1'b0}};
    out_L = {DATA_WIDTH{1'b0}};
    for (k = 0; k < 5; k = k+1) begin
      if (grant[k*5 + 4]) out_N = flit[k]; // N = bit 4
      if (grant[k*5 + 3]) out_S = flit[k]; // S = bit 3
      if (grant[k*5 + 2]) out_E = flit[k]; // E = bit 2
      if (grant[k*5 + 1]) out_W = flit[k]; // W = bit 1
      if (grant[k*5 + 0]) out_L = flit[k]; // L = bit 0
    end
  end
endmodule
