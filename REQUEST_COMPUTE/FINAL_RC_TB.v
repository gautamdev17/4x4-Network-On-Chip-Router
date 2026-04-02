`timescale 1ns/1ps

module tb();
  parameter DATA_WIDTH = 32;
  reg [DATA_WIDTH-1:0] head_flit;
  reg [1:0] curr_x,curr_y;
  wire [4:0] out_dir;
  
  rc inst1(
  	head_flit,curr_x,curr_y,out_dir
  );

  initial begin
    $monitor("head_flit = %b;curr_x = %b,curr_y = %b,out_dir=%b",head_flit,curr_x,curr_y,out_dir);
  end
  initial begin
    #0; head_flit = 0; curr_x = 0; curr_y = 0;  // local
    #10; head_flit = {8{4'b1010}}; curr_x = 0; curr_y = 0; // east
    #20; head_flit = {8{4'b0010}}; curr_x = 1; curr_y = 0; // west 
    #30; head_flit = {8{4'b0010}}; curr_x = 0; curr_y = 1; // nprth
    #40; head_flit = {8{4'b0001}}; curr_x = 0; curr_y = 2; // south
  end
endmodule
