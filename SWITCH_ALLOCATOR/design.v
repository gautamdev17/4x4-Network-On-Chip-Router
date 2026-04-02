/*first define inputs outputs
input is the reqmat
output is the sel signal
set all ptrs to i0
req mat is unrolled per column, but in my code i have already rolled out the columns
start from ptr per column and if 1 detected give that the grant and set ptr = granted input + 1
send grants as 3bit binary encoded values since it saves up space and send as sel signal*/

module switch_allocator(input [24:0]reqmat,input clk,output reg [14:0]selsignal,output reg [4:0]fifo_pop);
  //use 15 bit for SEL SIGNAL represent each winner of an output port in 3 bits
  reg [14:0] rrbptr;
  initial rrbptr = 0;
  integer i, j, k;
  always @(posedge clk) begin
    //reset some stuff
    selsignal <= 0;
    fifo_pop <= 0;
    for(i=0;i<5;i=i+1) begin
      k = 0;
      for(j=rrbptr[(i+1)*3-1:i*3];k!=5;j=(j==4)?0:j+1) begin : IN_LOOP
        k = k + 1;
        if(reqmat[i*5+j]==1'b1) begin
          selsignal[(i+1)*3-1:i*3] <= j[2:0];
          rrbptr[(i+1)*3-1:i*3] <= (j==4)?0:j+1;
          fifo_pop[i] <= 1'b1;
          disable IN_LOOP;
        end
      end
    end
  end
endmodule
//this is the change
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
