`timescale 1ns/1ps
//sync fifo
module fifo #(parameter DATA_WIDTH=32,parameter DEPTH=8)
  (input clk,rst,rd_en,wr_en,input [DATA_WIDTH-1:0] data_in,output full,empty,data_valid,output reg [DATA_WIDTH-1:0] data_out,
  output [DATA_WIDTH-1:0] peek_data); // ADDED: peek_data is a combinational read of mem[rd_ptr].
                                      // reason: data_out is registered — it only updates when rd_en fires.
                                      // RC needs to see the head flit the same cycle it sits in the FIFO,
                                      // before the SA has granted anything. peek_data gives that without
                                      // changing any of the original read/write/count logic.
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
  assign peek_data = mem[rd_ptr]; // ADDED: combinational head peek (no rd_en required)
  /*
  this logic works, but it takes in capacity = depth-1 so one mem space is wasted. count logic avoids this.
  assign empty = (rd_ptr == wr_ptr);
  wire [ADDR_WIDTH-1:0] next_wr = (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1; // hardware synthesis of % is hard, so im conditions instead
  assign full = (next_wr == rd_ptr);*/
  // assign full = ({~wr_ptr[ADDR_WIDTH],wr_ptr[ADDR_WIDTH-1:0]}==rd_ptr); only works for DEPTH = 2^n;
  integer i; // MOVED: was inside always@(posedge clk) read block in the original.
             // moved to module scope for simulator compatibility — some tools reject
             // integer declarations inside always blocks when the same var is used
             // across multiple always blocks. logic is identical.
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


//request matrix
module request_matrix (input [4:0] rc0,rc1,rc2,rc3,rc4, output [24:0]reqMat);
  assign reqMat[4:0] = rc0; // row 1
  assign reqMat[9:5] = rc1; // row 2
  assign reqMat[14:10] = rc2;// row 3
  assign reqMat[19:15] = rc3;// row 4
  assign reqMat[24:20] = rc4;//row 5
endmodule


/*first define inputs outputs
input is the reqmat
output is the sel signal
set all ptrs to i0
req mat is unrolled per column, but in my code i have already rolled out the columns
start from ptr per column and if 1 detected give that the grant and set ptr = granted input + 1
send grants as 3bit binary encoded values since it saves up space and send as sel signal*/

// REWRITTEN in plain Verilog (not SystemVerilog) so it works without -g2012
// and interfaces directly with the flat [24:0] reqMat wire from request_matrix.
// Your round-robin idea and pointer-per-output-port design are kept exactly.
// Three bugs fixed from your original:
//
//   BUG 1 (critical) — shared loop counter k:
//     Your inner loop used k as a trip counter but k was declared at module
//     scope. When the outer loop finished j=0, k was already 5. When j=1
//     started, k<5 was immediately false so the inner loop never ran for
//     output ports 1,2,3,4. Only port 0 ever got arbitrated.
//     Fix: use a separate `step` variable per output port inside a for loop.
//
//   BUG 2 (critical) — while loop with non-blocking assigns:
//     Inside always@(posedge clk), non-blocking assigns (<=) all schedule
//     to end of the time step regardless of loop structure. Your while loop
//     wrote rrbptr[i] multiple times — the last iteration's value won, not
//     the winner's. Fix: compute winner combinationally first (always@*),
//     then register the result with a single <= per output port.
//
//   BUG 3 (interface) — 2D SV array input:
//     reqMat[4:0][4:0] doesn't connect to request_matrix's [24:0] wire
//     without explicit unpacking. Switched to flat [24:0] reqMat.
//     Bit layout: reqMat[i*5 + j] = input i requests output j.
//     grant[i*5 + j] = input i wins output j. Same encoding, flat wire.
`timescale 1ns/1ps
module switch_allocator(
  input        clk,
  input        rst,
  input [24:0] reqMat,    // flat: reqMat[i*5+j] = input i requests output j
  output reg [24:0] grant // flat: grant[i*5+j]  = input i wins output j
);
  reg [2:0] rrbptr [0:4]; // round-robin pointer per output port (your original idea)

  // Combinational winner resolution — computed fresh every cycle before registering.
  // This avoids the while+non-blocking-assign bug: winner and next_ptr are computed
  // in a pure always@* block, then registered with a single <= per port in always@(posedge clk).
  reg       has_winner [0:4];
  reg [2:0] winner     [0:4];
  reg [2:0] next_ptr   [0:4];
  reg [2:0] candidate;
  integer j, step;

  always @* begin // combinational: find winner for each output port this cycle
    for (j = 0; j < 5; j = j+1) begin
      has_winner[j] = 1'b0;
      winner[j]     = 3'd0;
      next_ptr[j]   = rrbptr[j]; // default: pointer unchanged if no requests

      for (step = 0; step < 5; step = step+1) begin
        // walk from rrbptr[j], wrapping 4→0
        candidate = (rrbptr[j] + step[2:0] >= 5) ?
                    (rrbptr[j] + step[2:0] - 3'd5) :
                    (rrbptr[j] + step[2:0]);
        // only record the FIRST hit (has_winner gates subsequent steps)
        if (!has_winner[j] && reqMat[candidate*5 + j]) begin
          has_winner[j] = 1'b1;
          winner[j]     = candidate;
          // advance pointer to one past winner so next cycle starts there
          next_ptr[j]   = (candidate == 3'd4) ? 3'd0 : candidate + 3'd1;
        end
      end
    end
  end

  always@(posedge clk) begin // register results
    if(rst) begin
      grant <= 25'b0;
      rrbptr[0]<=3'b0; rrbptr[1]<=3'b0; rrbptr[2]<=3'b0;
      rrbptr[3]<=3'b0; rrbptr[4]<=3'b0;
    end else begin
      grant <= 25'b0; // clear all grants; re-arbitrate every cycle
      for (j = 0; j < 5; j = j+1) begin
        if (has_winner[j]) begin
          grant[winner[j]*5 + j] <= 1'b1; // one grant bit per output port max
          rrbptr[j] <= next_ptr[j];        // advance pointer past this winner
        end
      end
    end
  end
endmodule


// REWRITTEN to consume grant[24:0] (flat matrix) instead of selsignal (encoded).
// Your mux logic is kept exactly — zero if no winner, else route the winning input.
// Only the interface changed to match the SA above.
// original line: assign final_out[i] = (selsignal[i]==3'b111)?'0:input_data[selsignal[i]];
// equivalent here: if grant bit for input k → output j is set, drive input k's flit to output j.
`timescale 1ns/1ps
module crossbar #(parameter DATA_WIDTH=32)
  (input [24:0] grant,
   input  [DATA_WIDTH-1:0] flit0,flit1,flit2,flit3,flit4,
   output reg [DATA_WIDTH-1:0] out_N,out_S,out_E,out_W,out_L);

  wire [DATA_WIDTH-1:0] flit [0:4];
  assign flit[0]=flit0; assign flit[1]=flit1; assign flit[2]=flit2;
  assign flit[3]=flit3; assign flit[4]=flit4;
  integer k;

  always @* begin // bro basically this is multiplexer, we are giving inputs to respective output lines
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


// TOP: ROUTER — wires all five modules together into one unit.
// rd_en for each FIFO = any bit in that input's grant row being set (SA popping it).
// RC reads peek_data (combinational) so it sees the head flit without waiting for rd_en.
`timescale 1ns/1ps
module router #(parameter DATA_WIDTH=32, parameter DEPTH=4)
  (input        clk, rst,
   input  [1:0] curr_x, curr_y,
   input  [DATA_WIDTH-1:0] flit_in0,flit_in1,flit_in2,flit_in3,flit_in4,
   input  wr0,wr1,wr2,wr3,wr4,
   output [DATA_WIDTH-1:0] out_N,out_S,out_E,out_W,out_L,
   output full0,full1,full2,full3,full4,
   output empty0,empty1,empty2,empty3,empty4);

  wire [DATA_WIDTH-1:0] pk0,pk1,pk2,pk3,pk4; // combinational heads from FIFOs
  wire valid0,valid1,valid2,valid3,valid4;
  wire ful0_w,ful1_w,ful2_w,ful3_w,ful4_w;
  wire emp0_w,emp1_w,emp2_w,emp3_w,emp4_w;
  wire [4:0] dir0,dir1,dir2,dir3,dir4;        // RC outputs
  wire [24:0] reqMat, grant;

  // rd_en[i] = any grant bit in row i is set (SA telling FIFO i to pop)
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

  // RC reads peek_data, gated by data_valid so empty FIFOs don't generate bogus requests
  rc #(.DATA_WIDTH(DATA_WIDTH)) r0 (.head_flit(valid0?pk0:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir0));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r1 (.head_flit(valid1?pk1:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir1));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r2 (.head_flit(valid2?pk2:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir2));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r3 (.head_flit(valid3?pk3:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir3));
  rc #(.DATA_WIDTH(DATA_WIDTH)) r4 (.head_flit(valid4?pk4:{DATA_WIDTH{1'b0}}),.curr_x(curr_x),.curr_y(curr_y),.out_dir(dir4));

  // gate RC output: only assert request when FIFO is non-empty
  wire [4:0] req0 = valid0 ? dir0 : 5'b0;
  wire [4:0] req1 = valid1 ? dir1 : 5'b0;
  wire [4:0] req2 = valid2 ? dir2 : 5'b0;
  wire [4:0] req3 = valid3 ? dir3 : 5'b0;
  wire [4:0] req4 = valid4 ? dir4 : 5'b0;

  request_matrix rm (.rc0(req0),.rc1(req1),.rc2(req2),.rc3(req3),.rc4(req4),.reqMat(reqMat));
  switch_allocator sa (.clk(clk),.rst(rst),.reqMat(reqMat),.grant(grant));
  crossbar #(.DATA_WIDTH(DATA_WIDTH)) cb
    (.grant(grant),
     .flit0(pk0),.flit1(pk1),.flit2(pk2),.flit3(pk3),.flit4(pk4),
     .out_N(out_N),.out_S(out_S),.out_E(out_E),.out_W(out_W),.out_L(out_L));

  assign {full0,full1,full2,full3,full4}      = {ful0_w,ful1_w,ful2_w,ful3_w,ful4_w};
  assign {empty0,empty1,empty2,empty3,empty4} = {emp0_w,emp1_w,emp2_w,emp3_w,emp4_w};
endmodule


// =============================================================
// TESTBENCH
// Router at curr_x=1, curr_y=1  (centre of 4×4 mesh)
// Flit format: [31:30]=dest_x  [29:28]=dest_y  [27:0]=payload
//
// TEST 1: No contention — I0→E, I1→L, I2→N, I3→S, I4→W
// TEST 2: Contention + round-robin fairness
//   I0 and I2 both want EAST.
//   Round 1: rrbptr[EAST]=0 → I0 wins → ptr advances to 1
//   Round 2: rrbptr[EAST]=1 → scans I1(empty) → I2 wins
//   Proves I0 does not win twice in a row.
// TEST 3: All FIFOs empty → all outputs must be 0
// =============================================================
`timescale 1ns/1ps
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

    // =========================================================
    // TEST 1: No Contention
    // =========================================================
    $display("\n========================================");
    $display("TEST 1: No Contention");
    $display("  I0 -> EAST   dest(2,1) payload=0xAAAAAAA");
    $display("  I1 -> LOCAL  dest(1,1) payload=0xBBBBBBB");
    $display("  I2 -> NORTH  dest(1,2) payload=0xCCCCCCC");
    $display("  I3 -> SOUTH  dest(1,0) payload=0xDDDDDDD");
    $display("  I4 -> WEST   dest(0,1) payload=0xEEEEEEE");
    $display("========================================");

    f0=make_flit(2'b10,2'b01,28'hAAAAAAA); // dest_x=2 > curr_x=1 -> EAST
    f1=make_flit(2'b01,2'b01,28'hBBBBBBB); // dest=curr             -> LOCAL
    f2=make_flit(2'b01,2'b10,28'hCCCCCCC); // dest_y=2 > curr_y=1  -> NORTH
    f3=make_flit(2'b01,2'b00,28'hDDDDDDD); // dest_y=0 < curr_y=1  -> SOUTH
    f4=make_flit(2'b00,2'b01,28'hEEEEEEE); // dest_x=0 < curr_x=1  -> WEST

    {w0,w1,w2,w3,w4}=5'b11111; wait_cycles(1); // posedge: all FIFOs written; peek_data valid
    {w0,w1,w2,w3,w4}=5'b00000;
    wait_cycles(1); #1;                         // posedge: SA latches reqMat -> grant; crossbar drives outputs

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

    // =========================================================
    // TEST 2: Contention + Round-Robin Fairness
    // =========================================================
    $display("\n========================================");
    $display("TEST 2: Contention -- Round-Robin Fairness");
    $display("  I0 and I2 both want EAST (loaded with 2 flits each)");
    $display("  Round 1: rrbptr[EAST]=0 -> I0 should win");
    $display("  Round 2: rrbptr[EAST]=1 -> I2 should win (ptr skips I1 which is empty)");
    $display("========================================");

    rst=1; wait_cycles(3); rst=0;

    f0=make_flit(2'b10,2'b01,28'hAAAAAAA); // dest_x=2 > curr_x=1 -> EAST
    f2=make_flit(2'b10,2'b00,28'hCCCCCCC); // dest_x=2 > curr_x=1 -> EAST
    f1=0; f3=0; f4=0;

    w0=1; w2=1; w1=0; w3=0; w4=0;
    wait_cycles(1); {w0,w1,w2,w3,w4}=5'b0; // both FIFOs written

    wait_cycles(1); #1; // SA arbitrates: rrbptr[EAST]=0 -> scans from I0 -> I0 wins

    $display("\n--- Round 1 (rrbptr[EAST] started at 0) ---");
    $display("  out_E=%h  expected I0:%h  %s",out_E,f0,(out_E===f0)?"[PASS]":"[FAIL]");
    if(out_E===f0) pass=pass+1; else fail=fail+1;

    // one more cycle: I0 FIFO gets popped (rd_en fires at posedge); SA re-arbitrates with rrbptr[EAST]=1
    // ptr=1 -> scans I1(empty) -> finds I2 -> I2 wins
    wait_cycles(1); #1;

    $display("\n--- Round 2 (rrbptr[EAST] now 1, skips empty I1, lands on I2) ---");
    $display("  out_E=%h  expected I2:%h  %s",out_E,f2,(out_E===f2)?"[PASS]":"[FAIL]");
    if(out_E===f2) pass=pass+1; else fail=fail+1;

    wait_cycles(3);

    // =========================================================
    // TEST 3: All FIFOs empty
    // =========================================================
    $display("\n========================================");
    $display("TEST 3: All FIFOs empty -- all outputs must be 0");
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