`timescale 1ns/1ps
//sync fifo
module fifo #(parameter DATA_WIDTH=32,parameter DEPTH=8)
  (input clk,rst,rd_en,wr_en,input [DATA_WIDTH-1:0] data_in,output full,empty,output reg [DATA_WIDTH-1:0] data_out);
  localparam ADDR_WIDTH = (DEPTH>1)?$clog2(DEPTH):1; //address width
  reg [ADDR_WIDTH-1:0]wr_ptr,rd_ptr; // for pointers // extra bit for checking full condition
  reg [DATA_WIDTH-1:0] mem [DEPTH-1:0]; // write the basic block first * no. of blocks
  /*mem is a DEPTH × DATA_WIDTH matrix:
	•	DEPTH = number of rows (slots).
	•	DATA_WIDTH = width of each row (flit size).

So each mem[i] is one full DATA_WIDTH-bit flit.*/
  assign empty = (rd_ptr == wr_ptr);
  wire [ADDR_WIDTH-1:0] next_wr = (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1; // hardware synthesis of % is hard, so use conditions instead
  assign full = (next_wr == rd_ptr);
  // assign full = ({~wr_ptr[ADDR_WIDTH],wr_ptr[ADDR_WIDTH-1:0]}==rd_ptr); only works for DEPTH = 2^n;
  always@(posedge clk) begin//read
    if(rst) begin
      	rd_ptr<=0;
    	data_out<=0;
    end
    else if(rd_en && !empty) begin
        data_out<=mem[rd_ptr];
      rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
      end
  end
  always@(posedge clk) begin//write
    if(rst) begin
		wr_ptr<=0;
    end
	else if(wr_en && !full) begin
      mem[wr_ptr]<=data_in;
      wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1;
    end
  end
endmodule
