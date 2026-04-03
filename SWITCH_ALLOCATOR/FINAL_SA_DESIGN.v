/*first define inputs outputs
input is the reqmat
output is the sel signal
set all ptrs to i0
req mat is unrolled per column, but in my code i have already rolled out the columns
start from ptr per column and if 1 detected give that the grant and set ptr = granted input + 1
send grants as 3bit binary encoded values since it saves up space and send as sel signal*/


// switched to system verilog since verilog dint allow dynamic slicing
// selsignal for an output port will be given 111 if no winnners are there for that specific direction/output port
`timescale 1ns/1ps

module switch_allocator(
  input [24:0]reqMat,//input i requests output j
  input clk,
  input  rst,
  output reg [24:0] grant //input i wins output j
);
  reg [2:0] rrbptr [4:0];
  reg has_winner [0:4];
  reg [2:0] winner [0:4];
  reg [2:0] next_ptr [0:4];
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
