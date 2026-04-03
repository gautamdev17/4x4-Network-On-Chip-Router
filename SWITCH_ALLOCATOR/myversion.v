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
  input logic reqMat [4:0][4:0],
  input  logic clk,
  input  logic rst,
  output logic [2:0] selsignal [4:0], //select winners for each direction
  output logic [4:0] fifo_pop //winner inputs are popped
);
  logic [2:0] rrbptr [4:0];
  integer i,j,k;
  logic f;

  always_ff @(posedge clk) begin
    if (rst) begin // reset all
      for (i=0; i<5; i=i+1) begin
        rrbptr[i]<=3'b0;
        selsignal[i]<=3'b111;//no winner in that direction(output)
      end
      fifo_pop <= 5'b0;
    end else begin
      //initialize everythign again for nxt clock
      for (i=0; i<5; i=i+1) begin
        selsignal[i] <= 3'b111;//default->no winner
      end
      fifo_pop <= 5'b0;

      for (i=0; i<5; i=i+1) begin// go into each direction(outputport) // take each column each time
        f = 1'b0;
        k = 0;
        // run from rrb to a full circle
        for (j = int'(rrbptr[i]); k < 5; j = (j==4) ? 0 : j+1) begin // go into that column, pick the rows
          k = k + 1;
          if (reqMat[j][i] == 1'b1 && !f) begin
            selsignal[i] <= logic'(j);//winner for output i
            rrbptr[i] <= (j == 4) ? 3'b0 : j+1;
            fifo_pop[j] <= 1'b1;//pop the winner input port.the losers have to wait next clk cyckle and they dont get a chance to be popped now
            f = 1'b1; // break, stop running into that port and go to next
          end
        end
      end
    end
  end
endmodule
