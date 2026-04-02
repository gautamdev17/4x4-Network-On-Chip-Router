`timescale 1ns/1ps
module fifo_tb();
  parameter DATA_WIDTH = 4;
  parameter DEPTH      = 4;

  reg clk,rst,rd_en,wr_en;
  reg  [DATA_WIDTH-1:0] data_in;
  wire full,empty,data_valid;
  wire [DATA_WIDTH-1:0] data_out;
  
  fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) inst1 (
    clk,rst,rd_en,wr_en,data_in,
    full,empty,data_valid,data_out
  );
  
  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
      $monitor("t=%0t clk=%b rst=%b wr=%b rd=%b full=%b empty=%b valid=%b din=%h dout=%h",
               $time, clk, rst, wr_en, rd_en, full, empty, data_valid, data_in, data_out);
  end
  
  initial begin
    //reset
    rst    = 1;
    wr_en  = 0;
    rd_en  = 0;
    data_in = 0;
    #20;
    rst = 0;
    // writr a
    wr_en=1; data_in=4'ha;
    #10;

    // read a
    wr_en=0; rd_en=1;  data_in=0;
    #10;

    // fill mem
    rd_en=0; wr_en=1;
    data_in=4'h1; #10;
    data_in=4'h2; #10;
    data_in=4'h3; #10;
    data_in=4'h4; #10;

    // should be ignored
    data_in=4'h5; #10;

    // full read
    wr_en=0; rd_en=1;  data_in=0;
    #50;

    $finish;
  end
endmodule
