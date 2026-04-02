`timescale 1ns/1ps

module SA_tb;

  reg  [24:0] reqMat;
  reg         clk, rst;
  wire [14:0] selsignal;
  wire [4:0]  fifo_pop;
  int i; // <-- declare here

  switch_allocator dut (
    .reqMat(reqMat),
    .clk(clk),
    .rst(rst),
    .selsignal(selsignal),
    .fifo_pop(fifo_pop)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    $display(" time     reqMat         sel    pop");
    $monitor("%4t   %07h    %05o   %05b",
             $time, reqMat, selsignal, fifo_pop);
  end

  initial begin
    rst = 1;
    reqMat = 0;
    @(posedge clk); @(posedge clk);
    rst = 0;

    // NO REQUEST
    @(posedge clk) reqMat = 25'h0000000;

    // SINGLE REQUEST FOR ALL 25 POSITIONS
    for (i = 0; i < 25; i = i + 1) begin
      @(posedge clk);
      reqMat = 0;
      reqMat[i] = 1'b1;
    end

    // ROW SWEEP
    @(posedge clk) reqMat = 25'b00000_00000_00000_00000_11111;
    @(posedge clk) reqMat = 25'b00000_00000_00000_11111_00000;
    @(posedge clk) reqMat = 25'b00000_00000_11111_00000_00000;
    @(posedge clk) reqMat = 25'b00000_11111_00000_00000_00000;
    @(posedge clk) reqMat = 25'b11111_00000_00000_00000_00000;

    // COLUMN SWEEP
    @(posedge clk) reqMat = 25'b00001_00001_00001_00001_00001;
    @(posedge clk) reqMat = 25'b00010_00010_00010_00010_00010;
    @(posedge clk) reqMat = 25'b00100_00100_00100_00100_00100;
    @(posedge clk) reqMat = 25'b01000_01000_01000_01000_01000;
    @(posedge clk) reqMat = 25'b10000_10000_10000_10000_10000;

    // RANDOM PATTERNS
    @(posedge clk) reqMat = 25'h24802;
    @(posedge clk) reqMat = 25'h11111;
    @(posedge clk) reqMat = 25'h08241;

    // RANDOM STRESS
    repeat (10) begin
      @(posedge clk);
      reqMat = $urandom;
    end

    @(posedge clk);
    $finish;
  end

endmodule
