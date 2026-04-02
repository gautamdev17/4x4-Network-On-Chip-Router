
`timescale 1ns/1ps
//sync fifo
module fifo #(parameter DATA_WIDTH=32,parameter DEPTH=8)
  (input clk,rst,rd_en,wr_en,input [DATA_WIDTH-1:0] data_in,output full,empty,data_valid,output reg [DATA_WIDTH-1:0] data_out);
  localparam ADDR_WIDTH = (DEPTH>1)?$clog2(DEPTH):1; //address width
  reg [ADDR_WIDTH-1:0]wr_ptr,rd_ptr; // for pointers // extra bit for checking full condition
  reg [DATA_WIDTH-1:0] mem [DEPTH-1:0]; // write the basic block first * no. of blocks
  /*mem is a DEPTH × DATA_WIDTH matrix:
		DEPTH = number of rows (slots).
		DATA_WIDTH = width of each row (flit size).

So each mem[i] is one full DATA_WIDTH-bit flit.*/
  reg [ADDR_WIDTH:0]count;
  assign empty = (count==0);
  assign full = (count==DEPTH);
  assign data_valid = ~empty;
  /*
  this logic works, but it takes in capacity = depth-1 so one mem space is wasted. count logic avoids this.
  assign empty = (rd_ptr == wr_ptr);
  wire [ADDR_WIDTH-1:0] next_wr = (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1; // hardware synthesis of % is hard, so im conditions instead
  assign full = (next_wr == rd_ptr);*/
  // assign full = ({~wr_ptr[ADDR_WIDTH],wr_ptr[ADDR_WIDTH-1:0]}==rd_ptr); only works for DEPTH = 2^n;
  integer i;
  always@(posedge clk) begin//read
    if(rst) begin
      	rd_ptr<=0;
    	data_out<=0;
    	for(i=0;i<DEPTH;i++)
    		mem[i]<=0;
    end
    else if(rd_en && !empty) begin
        data_out<=mem[rd_ptr];
      	rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
      end
  end

  always@(posedge clk) begin // controlling count
		if(rst)
			count<=0;
		else begin
			case({wr_en&&!full,rd_en&&!empty})
				2'b10: count<=count+1'b1;
				2'b01: count<=count-1'b1;
				default: count <= count;
			endcase
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
