`timescale 1ns/1ps
//sync fifo
module fifo #(parameter DATA_WIDTH=32,parameter DEPTH=8) 
  (input clk,rst,rd_en,wr_en,input [DATA_WIDTH-1:0] data_in,output full,empty,output reg [DATA_WIDTH-1:0] data_out);
  localparam ADDR_WIDTH = $clog2(DEPTH); //address width
  reg [ADDR_WIDTH-1:0]wr_ptr,rd_ptr; // for pointers
  reg [DATA_WIDTH-1:0] mem [DEPTH-1:0]; // write the basic block first * no. of blocks
  reg [$clog2(DEPTH+1)-1:0]count;
  /*mem is a DEPTH × DATA_WIDTH matrix:
	•	DEPTH = number of rows (slots).
	•	DATA_WIDTH = width of each row (flit size).

So each mem[i] is one full DATA_WIDTH-bit flit.*/
  assign empty = (count == 0);
  assign full = (count == DEPTH);
  always @(posedge clk) begin
    if(rst) begin// reset condition
      wr_ptr<=0;
      rd_ptr<=0;
      count<=0;
      data_out<=0;
    end
    else begin
      if(rd_en && wr_en) begin // both read and write
        if(empty) begin // handle empty condition, only write happens
          mem[wr_ptr]<=data_in;
          wr_ptr<=(wr_ptr+1'b1)%DEPTH;
          count<=count+1'b1;
        end
        else begin
          data_out<=mem[rd_ptr];
          rd_ptr<=(rd_ptr+1'b1)%DEPTH;
          mem[wr_ptr+1'b1]<=data_in;
          wr_ptr<=(wr_ptr+1'b1)%DEPTH;
        end
      end
      else begin
        if(wr_en && !full) begin//
          mem[wr_ptr]<=data_in;
          wr_ptr<=(wr_ptr+1'b1)%DEPTH;
          count<=count+1'b1;
        end
        else if (rd_en && !empty) begin
          data_out<=mem[rd_ptr];
          rd_ptr<=(rd_ptr+1'b1)%DEPTH;
          count<=count-1'b1;
        end
      end
    end
  end
endmodule
