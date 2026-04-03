`timescale 1ns/1ps

// =============================================================
// MODULE 1: FIFO
// Based on FINAL_FIFO_DESIGN.v.
//
// FIX vs original: added combinational peek_data = mem[rd_ptr].
// Reason: the original data_out is registered behind rd_en.
// RC needs to see the head flit BEFORE the SA grants it,
// so a pure combinational peek is required. data_out (registered)
// is kept for compatibility but not used inside the router.
// =============================================================
module fifo #(parameter DATA_WIDTH = 32, parameter DEPTH = 8)
  (input  clk, rst, rd_en, wr_en,
   input  [DATA_WIDTH-1:0] data_in,
   output full, empty, data_valid,
   output [DATA_WIDTH-1:0] peek_data,       // combinational head — NEW
   output reg [DATA_WIDTH-1:0] data_out);   // registered output — original

  localparam ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  reg [ADDR_WIDTH:0]   count;
  integer i;

  assign empty      = (count == 0);
  assign full       = (count == DEPTH);
  assign data_valid = ~empty;
  assign peek_data  = mem[rd_ptr];   // combinational read — no rd_en needed

  // write
  always @(posedge clk) begin
    if (rst) wr_ptr <= 0;
    else if (wr_en && !full) begin
      mem[wr_ptr] <= data_in;
      wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1;
    end
  end

  // read (registered output + pointer advance + mem clear on rst)
  always @(posedge clk) begin
    if (rst) begin
      rd_ptr   <= 0;
      data_out <= 0;
      for (i = 0; i < DEPTH; i = i + 1) mem[i] <= 0;
    end else if (rd_en && !empty) begin
      data_out <= mem[rd_ptr];
      rd_ptr   <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
    end
  end

  // occupancy counter
  always @(posedge clk) begin
    if (rst) count <= 0;
    else case ({wr_en && !full, rd_en && !empty})
      2'b10:   count <= count + 1'b1;
      2'b01:   count <= count - 1'b1;
      default: count <= count;
    endcase
  end
endmodule


// =============================================================
// MODULE 2: ROUTE COMPUTE (RC)
// Unchanged from FINAL_RC_DESIGN.v.
// [31:30]=dest_x  [29:28]=dest_y  (top 4 bits of 32-bit flit)
// out_dir one-hot: [4]=N [3]=S [2]=E [1]=W [0]=L
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
// MODULE 3: REQUEST MATRIX
// Unchanged from FINAL_REQMAT_DESIGN.v.
// reqMat[i*5 +: 5] = rc_i output (i=0..4)
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
// MODULE 4: SWITCH ALLOCATOR (SA)
// Clocked FSM. Each cycle: for each output column j (N/S/E/W/L),
// picks the lowest-index input with reqMat[i*5+j]=1.
// Outputs grant[i*5+j]=1 meaning input i wins output j.
// At most one bit set per column.
// New module — not in original repo.
// =============================================================
module switch_allocator
  (input        clk, rst,
   input [24:0] reqMat,
   output reg [24:0] grant);

  integer j;
  always @(posedge clk) begin
    if (rst) begin
      grant <= 25'b0;
    end else begin
      grant <= 25'b0;
      for (j = 0; j < 5; j = j + 1) begin
        if      (reqMat[0*5 + j]) grant[0*5 + j] <= 1'b1;
        else if (reqMat[1*5 + j]) grant[1*5 + j] <= 1'b1;
        else if (reqMat[2*5 + j]) grant[2*5 + j] <= 1'b1;
        else if (reqMat[3*5 + j]) grant[3*5 + j] <= 1'b1;
        else if (reqMat[4*5 + j]) grant[4*5 + j] <= 1'b1;
      end
    end
  end
endmodule


// =============================================================
// MODULE 5: CROSSBAR
// Combinational. For each output j, finds which input i has
// grant[i*5+j]=1 and drives peek_data[i] to that output.
// New module — not in original repo.
// =============================================================
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
// Wires all five modules together.
// curr_x, curr_y: this router's position in the 4x4 mesh.
// rd_en[i] = any bit in grant row i (SA popping that FIFO).
// RC reads peek_data (combinational) so it sees the head flit
// in the same cycle it was written — no extra cycle needed.
// =============================================================
module router #(parameter DATA_WIDTH = 32, parameter DEPTH = 4)
  (input        clk, rst,
   input  [1:0] curr_x, curr_y,
   input  [DATA_WIDTH-1:0] flit_in0, flit_in1, flit_in2, flit_in3, flit_in4,
   input  wr0, wr1, wr2, wr3, wr4,
   output [DATA_WIDTH-1:0] out_N, out_S, out_E, out_W, out_L,
   output full0,  full1,  full2,  full3,  full4,
   output empty0, empty1, empty2, empty3, empty4);

  // FIFO peek outputs (combinational head)
  wire [DATA_WIDTH-1:0] pk0, pk1, pk2, pk3, pk4;
  wire valid0, valid1, valid2, valid3, valid4;
  wire ful0_w, ful1_w, ful2_w, ful3_w, ful4_w;
  wire emp0_w, emp1_w, emp2_w, emp3_w, emp4_w;

  // RC outputs
  wire [4:0] dir0, dir1, dir2, dir3, dir4;

  // ReqMat + Grant
  wire [24:0] reqMat, grant;

  // rd_en: SA pops a FIFO when any column bit in that row is granted
  wire rd_en0 = |grant[ 4: 0];
  wire rd_en1 = |grant[ 9: 5];
  wire rd_en2 = |grant[14:10];
  wire rd_en3 = |grant[19:15];
  wire rd_en4 = |grant[24:20];

  // FIFOs
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

  // RC: reads peek_data, gated by data_valid
  rc #(.DATA_WIDTH(DATA_WIDTH)) r0 (.head_flit(valid0 ? pk0 : {DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir0));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r1 (.head_flit(valid1 ? pk1 : {DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir1));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r2 (.head_flit(valid2 ? pk2 : {DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir2));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r3 (.head_flit(valid3 ? pk3 : {DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir3));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r4 (.head_flit(valid4 ? pk4 : {DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir4));

  // Gate RC output: only request when FIFO is non-empty
  wire [4:0] req0 = valid0 ? dir0 : 5'b0;
  wire [4:0] req1 = valid1 ? dir1 : 5'b0;
  wire [4:0] req2 = valid2 ? dir2 : 5'b0;
  wire [4:0] req3 = valid3 ? dir3 : 5'b0;
  wire [4:0] req4 = valid4 ? dir4 : 5'b0;

  request_matrix rm (.rc0(req0),.rc1(req1),.rc2(req2),.rc3(req3),.rc4(req4),.reqMat(reqMat));
  switch_allocator sa (.clk(clk),.rst(rst),.reqMat(reqMat),.grant(grant));
  crossbar cb (.grant(grant),.peek0(pk0),.peek1(pk1),.peek2(pk2),.peek3(pk3),.peek4(pk4),
               .out_N(out_N),.out_S(out_S),.out_E(out_E),.out_W(out_W),.out_L(out_L));

  assign {full0,full1,full2,full3,full4}   = {ful0_w,ful1_w,ful2_w,ful3_w,ful4_w};
  assign {empty0,empty1,empty2,empty3,empty4} = {emp0_w,emp1_w,emp2_w,emp3_w,emp4_w};
endmodule


// =============================================================
// TESTBENCH
//
// Router at (curr_x=1, curr_y=1) — centre of 4x4 mesh.
//
// Flit format: [31:30]=dest_x  [29:28]=dest_y  [27:0]=payload
//
// TEST 1 — No Contention:
//   I0 flit → dest(2,1): EAST   payload=0xAAAAAAA
//   I1 flit → dest(1,1): LOCAL  payload=0xBBBBBBB
//   I2 flit → dest(1,2): NORTH  payload=0xCCCCCCC
//   I3 flit → dest(1,0): SOUTH  payload=0xDDDDDDD
//   I4 flit → dest(0,1): WEST   payload=0xEEEEEEE
//   Expected: out_E=I0, out_L=I1, out_N=I2, out_S=I3, out_W=I4
//
// TEST 2 — Contention (I0 and I2 both want EAST):
//   I0: dest(2,1) → EAST
//   I2: dest(2,0) → EAST  (dest_x=2 > curr_x=1)
//   Expected: I0 wins (lower index), out_E=I0 flit.
//             I2 waits, then wins next arbitration round.
//
// TEST 3 — All FIFOs empty:
//   Expected: all outputs = 0.
//
// TIMING (key):
//   posedge N  : wr_en=1 → FIFO writes flit, count++
//   same posedge: peek_data = mem[rd_ptr] combinational → immediately valid
//   RC+ReqMat  : combinational off peek_data → reqMat valid same cycle
//   posedge N+1: SA latches reqMat → grant set
//   crossbar   : combinational off grant+peek → out ports valid right after posedge N+1
// =============================================================
module router_tb;
  parameter DW = 32;
  parameter DP =  4;

  reg        clk, rst;
  reg  [1:0] curr_x, curr_y;
  reg  [DW-1:0] f0, f1, f2, f3, f4;
  reg  w0, w1, w2, w3, w4;

  wire [DW-1:0] out_N, out_S, out_E, out_W, out_L;
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

  // {dest_x[1:0], dest_y[1:0], payload[27:0]}
  function [31:0] make_flit;
    input [1:0] dx, dy;
    input [27:0] payload;
    begin make_flit = {dx, dy, payload}; end
  endfunction

  task wait_cycles(input integer n);
    integer c;
    begin for (c = 0; c < n; c = c+1) @(posedge clk); #1; end
  endtask

  integer pass, fail;

  initial begin
    pass = 0; fail = 0;

    // ── RESET ────────────────────────────────────────────────
    rst = 1; curr_x = 2'd1; curr_y = 2'd1;
    {f0,f1,f2,f3,f4} = 0;
    {w0,w1,w2,w3,w4} = 5'b0;
    wait_cycles(3);   // hold reset for 3 cycles
    rst = 0;

    // ═════════════════════════════════════════════════════════
    // TEST 1: No Contention — all 5 different output ports
    // ═════════════════════════════════════════════════════════
    $display("\n========================================");
    $display("TEST 1: No Contention");
    $display("  I0 → EAST   (dest 2,1)  payload=0xAAAAAAA");
    $display("  I1 → LOCAL  (dest 1,1)  payload=0xBBBBBBB");
    $display("  I2 → NORTH  (dest 1,2)  payload=0xCCCCCCC");
    $display("  I3 → SOUTH  (dest 1,0)  payload=0xDDDDDDD");
    $display("  I4 → WEST   (dest 0,1)  payload=0xEEEEEEE");
    $display("========================================");

    f0 = make_flit(2'b10, 2'b01, 28'hAAAAAAA); // dest_x=2>1 → EAST
    f1 = make_flit(2'b01, 2'b01, 28'hBBBBBBB); // dest=curr   → LOCAL
    f2 = make_flit(2'b01, 2'b10, 28'hCCCCCCC); // dest_y=2>1  → NORTH
    f3 = make_flit(2'b01, 2'b00, 28'hDDDDDDD); // dest_y=0<1  → SOUTH
    f4 = make_flit(2'b00, 2'b01, 28'hEEEEEEE); // dest_x=0<1  → WEST

    // Cycle 1: write all flits into FIFOs
    // peek_data = mem[rd_ptr] becomes valid combinationally after the write posedge
    {w0,w1,w2,w3,w4} = 5'b11111;
    wait_cycles(1);                // posedge: FIFOs written; peek_data & RC/ReqMat resolve
    {w0,w1,w2,w3,w4} = 5'b00000;

    // Cycle 2: SA samples reqMat → grant set; crossbar combinational → outputs valid
    wait_cycles(1);
    #1; // tiny settle time past posedge

    $display("\n--- Outputs (cycle after SA arbitrates) ---");
    $display("  out_E = %h   expected: %h  %s", out_E, f0, (out_E===f0)?"[PASS]":"[FAIL]");
    $display("  out_L = %h   expected: %h  %s", out_L, f1, (out_L===f1)?"[PASS]":"[FAIL]");
    $display("  out_N = %h   expected: %h  %s", out_N, f2, (out_N===f2)?"[PASS]":"[FAIL]");
    $display("  out_S = %h   expected: %h  %s", out_S, f3, (out_S===f3)?"[PASS]":"[FAIL]");
    $display("  out_W = %h   expected: %h  %s", out_W, f4, (out_W===f4)?"[PASS]":"[FAIL]");

    if (out_E===f0) pass=pass+1; else fail=fail+1;
    if (out_L===f1) pass=pass+1; else fail=fail+1;
    if (out_N===f2) pass=pass+1; else fail=fail+1;
    if (out_S===f3) pass=pass+1; else fail=fail+1;
    if (out_W===f4) pass=pass+1; else fail=fail+1;

    wait_cycles(3); // FIFOs drain

    // ═════════════════════════════════════════════════════════
    // TEST 2: Contention — I0 and I2 both want EAST
    // ═════════════════════════════════════════════════════════
    $display("\n========================================");
    $display("TEST 2: Contention — I0 and I2 both want EAST");
    $display("  I0: dest(2,1) → EAST  payload=0xAAAAAAA");
    $display("  I2: dest(2,0) → EAST  payload=0xCCCCCCC");
    $display("  Expected: I0 wins (lower index), I2 waits");
    $display("========================================");

    rst = 1; wait_cycles(3); rst = 0;

    f0 = make_flit(2'b10, 2'b01, 28'hAAAAAAA); // dest_x=2>1 → EAST
    f2 = make_flit(2'b10, 2'b00, 28'hCCCCCCC); // dest_x=2>1 → EAST
    f1 = 32'h0; f3 = 32'h0; f4 = 32'h0;

    w0=1; w2=1; w1=0; w3=0; w4=0;
    wait_cycles(1);            // both FIFOs written
    {w0,w1,w2,w3,w4} = 5'b0;

    wait_cycles(1); #1;        // SA arbitrates; I0 wins

    $display("\n--- Round 1: I0 vs I2 for EAST ---");
    $display("  out_E = %h   expected I0: %h  %s", out_E, f0, (out_E===f0)?"[PASS]":"[FAIL]");
    $display("  out_N = %h   expected 0   %s", out_N, (out_N===0)?"[PASS]":"[FAIL]");
    $display("  out_S = %h   expected 0   %s", out_S, (out_S===0)?"[PASS]":"[FAIL]");
    $display("  out_W = %h   expected 0   %s", out_W, (out_W===0)?"[PASS]":"[FAIL]");
    $display("  out_L = %h   expected 0   %s", out_L, (out_L===0)?"[PASS]":"[FAIL]");

    if (out_E===f0) pass=pass+1; else fail=fail+1;
    if (out_N===0 && out_S===0 && out_W===0 && out_L===0) pass=pass+1; else fail=fail+1;

    // I0's FIFO gets rd_en at the next posedge (grant is registered; rd_en=|grant fires next cycle)
    // After that posedge, I0's FIFO is empty. I2 still has its flit → now wins EAST.
    wait_cycles(2); #1;  // cycle1: rd_en pops I0 FIFO; cycle2: SA sees only I2 → I2 wins

    $display("\n--- Round 2: I2 wins EAST after I0 drains ---");
    $display("  out_E = %h   expected I2: %h  %s", out_E, f2, (out_E===f2)?"[PASS]":"[FAIL]");

    if (out_E===f2) pass=pass+1; else fail=fail+1;

    wait_cycles(2);

    // ═════════════════════════════════════════════════════════
    // TEST 3: All FIFOs empty — no spurious outputs
    // ═════════════════════════════════════════════════════════
    $display("\n========================================");
    $display("TEST 3: All FIFOs empty");
    $display("  Expected: all outputs = 0");
    $display("========================================");

    rst = 1; wait_cycles(3); rst = 0;
    {w0,w1,w2,w3,w4} = 5'b0;
    wait_cycles(2); #1;

    $display("  out_E=%h out_N=%h out_S=%h out_W=%h out_L=%h",
             out_E, out_N, out_S, out_W, out_L);
    if (out_E===0 && out_N===0 && out_S===0 && out_W===0 && out_L===0)
      begin $display("  [PASS] All outputs zero"); pass=pass+1; end
    else
      begin $display("  [FAIL] Spurious output");  fail=fail+1; end

    // ─────────────────────────────────────────────────────────
    $display("\n========================================");
    $display("RESULTS: %0d passed, %0d failed", pass, fail);
    $display("========================================\n");
    $finish;
  end

  initial begin
    $dumpfile("router_sim.vcd");
    $dumpvars(0, router_tb);
  end
endmodule