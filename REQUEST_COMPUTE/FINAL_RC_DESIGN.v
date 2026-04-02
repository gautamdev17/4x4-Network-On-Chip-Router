//building route compute after fifo
// data_out of fifo--->rc unit for that fifo--->send one hot encoded dest address to req matrix
`timescale 1ns/1ps
module rc #(parameter DATA_WIDTH = 32) (input [DATA_WIDTH-1:0] head_flit,input [1:0] curr_x,curr_y,output reg [4:0] out_dir);
  //curr_x,curr_y ---> router x and y coordinates
  //in header flit from fifo, out one-hot direction
  //msb bits of the header flits specify the destination address
  // address is 4 bit, in 4x4 router mesh.
  // 2 bits for x coordinate 2 bits for y coordinate
  // to uniquely identify 16 routers, you need 4 bits,(2^4=16)
  wire [1:0] dest_x = head_flit[DATA_WIDTH-1:DATA_WIDTH-2];
  wire [1:0] dest_y = head_flit[DATA_WIDTH-3:DATA_WIDTH-4];
    //XY routing rule: fix x first
  //out_dir--->one hot bit mapping: N = [4] S = [3] E = [2] W = [1] L = [0]
  always @* begin
    if(dest_x>curr_x)  // east
      out_dir = 5'b00100;
    else if (dest_x<curr_x) // west
      out_dir = 5'b00010;
    else if(dest_y>curr_y) // north
	  out_dir = 5'b10000;
    else if (dest_y<curr_y)//south
      out_dir = 5'b01000;
    else
      out_dir = 5'b00001;
  end
endmodule
