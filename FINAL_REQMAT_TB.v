`timescale 1ns/1ps
module tb();
  reg [4:0] rc0,rc1,rc2,rc3,rc4;
  wire [24:0]reqMat;
  
  request_matrix inst1(rc0,rc1,rc2,rc3,rc4,reqMat);
  
  initial begin
    $monitor("rc0=%h,rc1=%h,rc2=%h,rc3=%h,rc4=%h,reqMat = %h",rc0,rc1,rc2,rc3,rc4,reqMat);
  end
  
  initial begin
    #0; rc0 = 5'b00010; rc1 = 5'b00001; rc2 = 5'b00010; rc3 = 5'b01000; rc4 = 5'b10000;
    #10; rc0 = 5'b10000; rc1 = 5'b00100; rc2 = 5'b01000; rc3 = 5'b10000; rc4 = 5'b00010;
    #10;
    $finish;
  end
endmodule
