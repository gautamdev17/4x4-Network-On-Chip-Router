/*first define inputs outputs
input is the reqmat
output is the sel signal
set all ptrs to i0
req mat is unrolled per column, but in my code i have already rolled out the columns
start from ptr per column and if 1 detected give that the grant and set ptr = granted input + 1
send grants as 3bit binary encoded values since it saves up space and send as sel signal*/


// switched to system verilog since verilog didnt allow dynamic slicing
// use dynamic part-select base +: width
`timescale 1ns/1ps

module switch_allocator(
  input  logic [24:0] reqMat,
  input  logic clk,
  input  logic rst,
  output reg [14:0] selsignal, //select winners for each direction
  output reg [4:0] fifo_pop //winnners are popped and next header flit is read for the nxt cycle
// losers arent popped and have to wait the next clock efge
);
  //use 15 bit for SEL SIGNAL represent each winner of an output port in 3 bits
  reg [14:0] rrbptr;
  integer i,j,k,f; // f is flag

  always_ff @(posedge clk) begin
    if (rst) begin
      rrbptr <= 0;
  	  selsignal <= 0;
  	  fifo_pop <= 0;
    end else begin
      selsignal <= 0;
      fifo_pop <= 0;
      for (i=0;i<5;i=i+1) begin //go to each direction
        k=0;f=0;
        // run from rrb to a full circle
        for (j = rrbptr[((i+1)*3-1)-:3];k != 5;j=(j==4)?0:j+1) begin
          k = k + 1;
          if (reqMat[i*5+j]==1'b1 && !f) begin
            // write slices using MSB-first dynamic part-select
            //bro so im doing dynamic slicing here and this is the format in sv
			// base-:width for msb:lsb slicing
            selsignal[((i+1)*3-1)-:3]<=j[2:0];//assign winner to respective direction
            rrbptr[((i+1)*3-1)-:3]<=(j==4)?3'b0:j+1;//rrb ptr will change for nxt cucle
            fifo_pop[i]<=1'b1;//pop the fifo for winners
            f=1; //stop here running the inner loop, winner found
          end
        end
      end
    end
  end
endmodule
/*MY CODE
`timescale 1ns/1ps

module switch_allocator(input [24:0]reqMat,input clk,input rst,output reg [14:0]selsignal,output reg [4:0]fifo_pop);
  //use 15 bit for SEL SIGNAL represent each winner of an output port in 3 bits
  reg [14:0] rrbptr;
  integer i, j, k;
  always @(posedge clk) begin
    if(rst)
      rrbptr<=0;
    else begin
      selsignal <= 0;
      fifo_pop <= 0;
      for(i=0;i<5;i=i+1) begin
        k = 0;
        for(j=rrbptr[(i+1)*3-1:i*3];k!=5;j=(j==4)?0:j+1) begin : IN_LOOP
          k = k + 1;
          if(reqMat[i*5+j]==1'b1) begin
            selsignal[(i+1)*3-1:i*3] <= j[2:0];
            rrbptr[(i+1)*3-1:i*3] <= (j==4)?0:j+1;
            fifo_pop[i] <= 1'b1;
            disable IN_LOOP;
          end
        end
      end
    end
  end
endmodule
*/
/*
for(j=4;j>=0;j=j+1) begin
      for(i=rrbptr[j*3:j*3];i<(rrbptr[j*3-1:(j-1)*3]+3'd5;i=i+1) begin
        if(reqmat[j*3-1-i]==1'b1) begin
          selsignal[j*3-1:(j-1)*3] <= 1'b1;
          rrbptr[j*3-1:(j-1)*3-1] <= rrbptr[j*3-1:(j-1)*3-1] + 1'b1;
        end
      end
    end
  end
*/
