`timescale 1ns/1ps

// =============================================================
// MODULE 1: FIFO
// Your original design. One change:
//   - integer i moved to module scope (simulator compatibility)
//   - peek_data wire added (combinational head read for RC)
// =============================================================
module fifo #(parameter DATA_WIDTH = 32, parameter DEPTH = 8)
  (input  clk, rst, rd_en, wr_en,
   input  [DATA_WIDTH-1:0] data_in,
   output full, empty, data_valid,
   output [DATA_WIDTH-1:0] peek_data,
   output reg [DATA_WIDTH-1:0] data_out);

  localparam ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  reg [ADDR_WIDTH:0]   count;
  integer i; // moved to module scope

  assign empty      = (count == 0);
  assign full       = (count == DEPTH);
  assign data_valid = ~empty;
  assign peek_data  = mem[rd_ptr]; // combinational head peek

  always @(posedge clk) begin // write
    if (rst) wr_ptr <= 0;
    else if (wr_en && !full) begin
      mem[wr_ptr] <= data_in;
      wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1;
    end
  end

  always @(posedge clk) begin // read
    if (rst) begin
      rd_ptr   <= 0;
      data_out <= 0;
      for (i = 0; i < DEPTH; i = i + 1) mem[i] <= 0;
    end else if (rd_en && !empty) begin
      data_out <= mem[rd_ptr];
      rd_ptr   <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
    end
  end

  always @(posedge clk) begin // count
    if (rst) count <= 0;
    else case ({wr_en && !full, rd_en && !empty})
      2'b10:   count <= count + 1'b1;
      2'b01:   count <= count - 1'b1;
      default: count <= count;
    endcase
  end
endmodule


// =============================================================
// MODULE 2: ROUTE COMPUTE — your original, zero changes
// =============================================================
module rc #(parameter DATA_WIDTH = 32)
  (input  [DATA_WIDTH-1:0] head_flit,
   input  [1:0] curr_x, curr_y,
   output reg [4:0] out_dir);

  wire [1:0] dest_x = head_flit[DATA_WIDTH-1 : DATA_WIDTH-2];
  wire [1:0] dest_y = head_flit[DATA_WIDTH-3 : DATA_WIDTH-4];

  always @* begin
    if      (dest_x > curr_x) out_dir = 5'b00100; // EAST
    else if (dest_x < curr_x) out_dir = 5'b00010; // WEST
    else if (dest_y > curr_y) out_dir = 5'b10000; // NORTH
    else if (dest_y < curr_y) out_dir = 5'b01000; // SOUTH
    else                      out_dir = 5'b00001; // LOCAL
  end
endmodule


// =============================================================
// MODULE 3: REQUEST MATRIX — your original, zero changes
// =============================================================
module request_matrix
  (input  [4:0]  rc0, rc1, rc2, rc3, rc4,
   output [24:0] reqMat);

  assign reqMat[ 4: 0] = rc0;
  assign reqMat[ 9: 5] = rc1;
  assign reqMat[14:10] = rc2;
  assign reqMat[19:15] = rc3;
  assign reqMat[24:20] = rc4;
endmodule


// =============================================================
// MODULE 4: SWITCH ALLOCATOR — your round-robin idea, fixed
//
// What was wrong in your version:
//   BUG 1: k declared at module scope but reset inside outer
//           loop. When outer loop i=0 finishes scanning 5
//           inputs, k=5. When i=1 starts, k is still 5 so
//           the inner loop condition (k<5) is immediately
//           false — inner loop never runs for i=1,2,3,4.
//           Only the first output port ever gets arbitrated.
//   BUG 2:  Interface was 2D SV logic array (reqMat[4:0][4:0])
//           which doesn't connect directly to your flat 25-bit
//           request_matrix output wire [24:0].
//   BUG 3:  rrbptr stored as 3-bit [2:0] but compared with
//           logic'(j) where j is an integer — implicit cast
//           worked in SV but not portable to plain Verilog.
//
// Fix: use a separate iteration counter per output port.
//   iter[j] counts 0..4 independently for each column j.
//   This is the same round-robin logic you intended, just
//   with the shared-k bug removed.
//
// Interface: flat [24:0] reqMat / grant (matches your modules)
// reqMat[i*5 + j] = input i requests output j
// grant[i*5 + j]  = input i is granted output j
// rrbptr[j] = next input to check first for output port j
// =============================================================
// The while loop issue: in a clocked always block, non-blocking assigns
// inside a while loop all schedule to the end of the time step.
// If the loop runs 3 iterations and the 3rd one writes rrbptr[j],
// that's the value that sticks — even if the 1st iteration found a winner.
// Fix: use a for loop with a found-flag variable to stop updating once
// a winner is selected. Non-blocking assigns from later iterations that
// should be "skipped" still fire, so we restructure to only ever do ONE
// non-blocking assign to rrbptr[j] and ONE to grant[...] per output port.

module switch_allocator
  (input        clk, rst,
   input [24:0] reqMat,
   output reg [24:0] grant);

  reg [2:0] rrbptr [0:4]; // round-robin pointer per output port (values 0-4)

  // Combinational wires to compute winner and new pointer before registering.
  // We resolve the winner purely combinationally, then register the result.
  reg [2:0] winner    [0:4]; // which input wins each output this cycle
  reg       has_winner[0:4]; // was any winner found
  reg [2:0] next_ptr  [0:4]; // what rrbptr should be next cycle

  integer j, step;
  reg [2:0] candidate;

  // Combinational block: pure logic, no registers written here
  always @* begin
    for (j = 0; j < 5; j = j + 1) begin
      has_winner[j] = 1'b0;
      winner[j]     = 3'd0;
      next_ptr[j]   = rrbptr[j]; // default: don't change pointer

      // scan 5 inputs starting from rrbptr[j]
      for (step = 0; step < 5; step = step + 1) begin
        candidate = (rrbptr[j] + step[2:0] > 4) ?
                    (rrbptr[j] + step[2:0] - 5) :
                    (rrbptr[j] + step[2:0]);
        // only set winner if not already found
        if (!has_winner[j] && reqMat[candidate*5 + j]) begin
          has_winner[j] = 1'b1;
          winner[j]     = candidate;
          next_ptr[j]   = (candidate == 4) ? 3'd0 : candidate + 3'd1;
        end
      end
    end
  end

  // Registered block: just captures the combinational results
  always @(posedge clk) begin
    if (rst) begin
      grant <= 25'b0;
      rrbptr[0]<=0; rrbptr[1]<=0; rrbptr[2]<=0;
      rrbptr[3]<=0; rrbptr[4]<=0;
    end else begin
      grant <= 25'b0;
      for (j = 0; j < 5; j = j + 1) begin
        if (has_winner[j]) begin
          grant[winner[j]*5 + j] <= 1'b1;
          rrbptr[j] <= next_ptr[j];
        end
      end
    end
  end
endmodule
module crossbar
  (input  [24:0] grant,
   input  [31:0] peek0, peek1, peek2, peek3, peek4,
   output reg [31:0] out_N, out_S, out_E, out_W, out_L);

  wire [31:0] pk [0:4];
  assign pk[0]=peek0; assign pk[1]=peek1; assign pk[2]=peek2;
  assign pk[3]=peek3; assign pk[4]=peek4;
  integer k;

  always @* begin
    out_N = 32'b0; out_S = 32'b0; out_E = 32'b0;
    out_W = 32'b0; out_L = 32'b0;
    for (k = 0; k < 5; k = k + 1) begin
      if (grant[k*5 + 4]) out_N = pk[k];
      if (grant[k*5 + 3]) out_S = pk[k];
      if (grant[k*5 + 2]) out_E = pk[k];
      if (grant[k*5 + 1]) out_W = pk[k];
      if (grant[k*5 + 0]) out_L = pk[k];
    end
  end
endmodule


// =============================================================
// TOP: ROUTER
// =============================================================
module router #(parameter DATA_WIDTH = 32, parameter DEPTH = 4)
  (input        clk, rst,
   input  [1:0] curr_x, curr_y,
   input  [DATA_WIDTH-1:0] flit_in0, flit_in1, flit_in2, flit_in3, flit_in4,
   input  wr0, wr1, wr2, wr3, wr4,
   output [DATA_WIDTH-1:0] out_N, out_S, out_E, out_W, out_L,
   output full0,  full1,  full2,  full3,  full4,
   output empty0, empty1, empty2, empty3, empty4);

  wire [DATA_WIDTH-1:0] pk0, pk1, pk2, pk3, pk4;
  wire valid0, valid1, valid2, valid3, valid4;
  wire ful0_w,ful1_w,ful2_w,ful3_w,ful4_w;
  wire emp0_w,emp1_w,emp2_w,emp3_w,emp4_w;
  wire [4:0] dir0, dir1, dir2, dir3, dir4;
  wire [24:0] reqMat, grant;

  wire rd_en0 = |grant[ 4: 0];
  wire rd_en1 = |grant[ 9: 5];
  wire rd_en2 = |grant[14:10];
  wire rd_en3 = |grant[19:15];
  wire rd_en4 = |grant[24:20];

  fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(DEPTH)) f0
    (.clk(clk),.rst(rst),.wr_en(wr0),.rd_en(rd_en0),
     .data_in(flit_in0),.peek_data(pk0),.data_out(),
     .full(ful0_w),.empty(emp0_w),.data_valid(valid0));
  fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(DEPTH)) f1
    (.clk(clk),.rst(rst),.wr_en(wr1),.rd_en(rd_en1),
     .data_in(flit_in1),.peek_data(pk1),.data_out(),
     .full(ful1_w),.empty(emp1_w),.data_valid(valid1));
  fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(DEPTH)) f2
    (.clk(clk),.rst(rst),.wr_en(wr2),.rd_en(rd_en2),
     .data_in(flit_in2),.peek_data(pk2),.data_out(),
     .full(ful2_w),.empty(emp2_w),.data_valid(valid2));
  fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(DEPTH)) f3
    (.clk(clk),.rst(rst),.wr_en(wr3),.rd_en(rd_en3),
     .data_in(flit_in3),.peek_data(pk3),.data_out(),
     .full(ful3_w),.empty(emp3_w),.data_valid(valid3));
  fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(DEPTH)) f4
    (.clk(clk),.rst(rst),.wr_en(wr4),.rd_en(rd_en4),
     .data_in(flit_in4),.peek_data(pk4),.data_out(),
     .full(ful4_w),.empty(emp4_w),.data_valid(valid4));

  rc #(.DATA_WIDTH(DATA_WIDTH)) r0 (.head_flit(valid0?pk0:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir0));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r1 (.head_flit(valid1?pk1:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir1));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r2 (.head_flit(valid2?pk2:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir2));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r3 (.head_flit(valid3?pk3:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir3));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r4 (.head_flit(valid4?pk4:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir4));

  wire [4:0] req0 = valid0 ? dir0 : 5'b0;
  wire [4:0] req1 = valid1 ? dir1 : 5'b0;
  wire [4:0] req2 = valid2 ? dir2 : 5'b0;
  wire [4:0] req3 = valid3 ? dir3 : 5'b0;
  wire [4:0] req4 = valid4 ? dir4 : 5'b0;

  request_matrix rm (.rc0(req0),.rc1(req1),.rc2(req2),.rc3(req3),.rc4(req4),.reqMat(reqMat));
  switch_allocator sa (.clk(clk),.rst(rst),.reqMat(reqMat),.grant(grant));
  crossbar cb (.grant(grant),.peek0(pk0),.peek1(pk1),.peek2(pk2),.peek3(pk3),.peek4(pk4),
               .out_N(out_N),.out_S(out_S),.out_E(out_E),.out_W(out_W),.out_L(out_L));

  assign {full0,full1,full2,full3,full4}      = {ful0_w,ful1_w,ful2_w,ful3_w,ful4_w};
  assign {empty0,empty1,empty2,empty3,empty4} = {emp0_w,emp1_w,emp2_w,emp3_w,emp4_w};
endmodule


// =============================================================
// TESTBENCH
// Flit format: [31:30]=dest_x  [29:28]=dest_y  [27:0]=payload
// Router at curr_x=1, curr_y=1
//
// TEST 1: No contention — all 5 go to different ports
// TEST 2: Contention + round-robin fairness proof
//   I0 and I2 both want EAST repeatedly.
//   Round 1: rrbptr[EAST]=0 → scans from I0 → I0 wins
//            rrbptr[EAST] advances to 1
//   Round 2: rrbptr[EAST]=1 → scans from I1 → I1 empty →
//            I2 wins (next non-empty from pointer=1)
//            rrbptr[EAST] advances to 3
//   This proves I0 does NOT win twice in a row — fair.
// TEST 3: All FIFOs empty → all outputs 0
// =============================================================
module router_tb;
  parameter DW = 32;
  parameter DP =  4;

  reg        clk, rst;
  reg  [1:0] curr_x, curr_y;
  reg  [DW-1:0] f0,f1,f2,f3,f4;
  reg  w0,w1,w2,w3,w4;

  wire [DW-1:0] out_N,out_S,out_E,out_W,out_L;
  wire full0,full1,full2,full3,full4;
  wire empty0,empty1,empty2,empty3,empty4;

  router #(.DATA_WIDTH(DW),.DEPTH(DP)) DUT
    (.clk(clk),.rst(rst),
     .curr_x(curr_x),.curr_y(curr_y),
     .flit_in0(f0),.flit_in1(f1),.flit_in2(f2),.flit_in3(f3),.flit_in4(f4),
     .wr0(w0),.wr1(w1),.wr2(w2),.wr3(w3),.wr4(w4),
     .out_N(out_N),.out_S(out_S),.out_E(out_E),.out_W(out_W),.out_L(out_L),
     .full0(full0),.full1(full1),.full2(full2),.full3(full3),.full4(full4),
     .empty0(empty0),.empty1(empty1),.empty2(empty2),.empty3(empty3),.empty4(empty4));

  initial clk = 0;
  always  #5 clk = ~clk;

  function [31:0] make_flit;
    input [1:0] dx, dy;
    input [27:0] payload;
    begin make_flit = {dx, dy, payload}; end
  endfunction

  task wait_cycles(input integer n);
    integer c;
    begin for (c=0;c<n;c=c+1) @(posedge clk); #1; end
  endtask

  integer pass, fail;

  initial begin
    pass=0; fail=0;
    rst=1; curr_x=2'd1; curr_y=2'd1;
    {f0,f1,f2,f3,f4}=0; {w0,w1,w2,w3,w4}=5'b0;
    wait_cycles(3); rst=0;

    // ═══════════════════════════════════════════════════════
    // TEST 1: No contention
    // ═══════════════════════════════════════════════════════
    $display("\n========================================");
    $display("TEST 1: No Contention");
    $display("  I0 → EAST   dest(2,1) payload=0xAAAAAAA");
    $display("  I1 → LOCAL  dest(1,1) payload=0xBBBBBBB");
    $display("  I2 → NORTH  dest(1,2) payload=0xCCCCCCC");
    $display("  I3 → SOUTH  dest(1,0) payload=0xDDDDDDD");
    $display("  I4 → WEST   dest(0,1) payload=0xEEEEEEE");
    $display("========================================");

    f0=make_flit(2'b10,2'b01,28'hAAAAAAA); // EAST
    f1=make_flit(2'b01,2'b01,28'hBBBBBBB); // LOCAL
    f2=make_flit(2'b01,2'b10,28'hCCCCCCC); // NORTH
    f3=make_flit(2'b01,2'b00,28'hDDDDDDD); // SOUTH
    f4=make_flit(2'b00,2'b01,28'hEEEEEEE); // WEST

    {w0,w1,w2,w3,w4}=5'b11111; wait_cycles(1); // write into FIFOs
    {w0,w1,w2,w3,w4}=5'b00000;
    wait_cycles(1); #1;                         // SA arbitrates → grant → outputs

    $display("\n--- Outputs ---");
    $display("  out_E=%h  expected:%h  %s",out_E,f0,(out_E===f0)?"[PASS]":"[FAIL]");
    $display("  out_L=%h  expected:%h  %s",out_L,f1,(out_L===f1)?"[PASS]":"[FAIL]");
    $display("  out_N=%h  expected:%h  %s",out_N,f2,(out_N===f2)?"[PASS]":"[FAIL]");
    $display("  out_S=%h  expected:%h  %s",out_S,f3,(out_S===f3)?"[PASS]":"[FAIL]");
    $display("  out_W=%h  expected:%h  %s",out_W,f4,(out_W===f4)?"[PASS]":"[FAIL]");

    if(out_E===f0) pass=pass+1; else fail=fail+1;
    if(out_L===f1) pass=pass+1; else fail=fail+1;
    if(out_N===f2) pass=pass+1; else fail=fail+1;
    if(out_S===f3) pass=pass+1; else fail=fail+1;
    if(out_W===f4) pass=pass+1; else fail=fail+1;

    wait_cycles(3);

    // ═══════════════════════════════════════════════════════
    // TEST 2: Contention + Round-Robin fairness
    // I0 and I2 both want EAST in back-to-back cycles.
    // Round 1: rrbptr[E]=0 → starts at I0 → I0 wins → ptr→1
    // Round 2: rrbptr[E]=1 → starts at I1(empty)→I2 wins → ptr→3
    // Proves the pointer advanced and I0 didn't win twice.
    // ═══════════════════════════════════════════════════════
    $display("\n========================================");
    $display("TEST 2: Contention — Round-Robin Fairness");
    $display("  I0 and I2 both want EAST (loaded with 2 flits each)");
    $display("  Round 1: rrbptr[EAST]=0 → I0 should win");
    $display("  Round 2: rrbptr[EAST]=1 → I2 should win (ptr skips I1 which is empty)");
    $display("========================================");

    rst=1; wait_cycles(3); rst=0;

    // Load I0 with flit_A, I2 with flit_B
    f0=make_flit(2'b10,2'b01,28'hAAAAAAA); // I0 → EAST
    f2=make_flit(2'b10,2'b00,28'hCCCCCCC); // I2 → EAST (dest_x=2>1)
    f1=0; f3=0; f4=0;

    // Write both in same cycle
    w0=1; w2=1; w1=0; w3=0; w4=0;
    wait_cycles(1); {w0,w1,w2,w3,w4}=5'b0;

    // Round 1: SA arbitrates → I0 wins (rrbptr[E] was 0 after reset)
    wait_cycles(1); #1;
    $display("\n--- Round 1 (rrbptr[EAST] started at 0) ---");
    $display("  out_E=%h  expected I0:%h  %s",out_E,f0,(out_E===f0)?"[PASS]":"[FAIL]");
    if(out_E===f0) pass=pass+1; else fail=fail+1;

    // Round 2: I0's FIFO gets popped now (rd_en fires at next posedge).
    // SA simultaneously re-arbitrates with rrbptr[E]=1.
    // I1 is empty → skip → I2 wins.
    wait_cycles(1); #1; // cycle1=I0 grant fires; cycle2=I0 FIFO drained; cycle3=I2 wins
    $display("\n--- Round 2 (rrbptr[EAST] now 1, skips empty I1, lands on I2) ---");
    $display("  out_E=%h  expected I2:%h  %s",out_E,f2,(out_E===f2)?"[PASS]":"[FAIL]");
    if(out_E===f2) pass=pass+1; else fail=fail+1;

    wait_cycles(3);

    // ═══════════════════════════════════════════════════════
    // TEST 3: All FIFOs empty
    // ═══════════════════════════════════════════════════════
    $display("\n========================================");
    $display("TEST 3: All FIFOs empty — all outputs must be 0");
    $display("========================================");

    rst=1; wait_cycles(3); rst=0;
    {w0,w1,w2,w3,w4}=5'b0;
    wait_cycles(2); #1;

    $display("  out_E=%h out_N=%h out_S=%h out_W=%h out_L=%h",
             out_E,out_N,out_S,out_W,out_L);
    if(out_E===0&&out_N===0&&out_S===0&&out_W===0&&out_L===0)
      begin $display("  [PASS] All zero"); pass=pass+1; end
    else
      begin $display("  [FAIL] Spurious output"); fail=fail+1; end

    $display("\n========================================");
    $display("RESULTS: %0d passed, %0d failed", pass, fail);
    $display("========================================\n");
    $finish;
  end

  initial begin
    $dumpfile("router_rr.vcd");
    $dumpvars(0, router_tb);
  end
endmodule