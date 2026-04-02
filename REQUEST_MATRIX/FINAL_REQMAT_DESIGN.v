//request matrix
module request_matrix (input [4:0] rc0,rc1,rc2,rc3,rc4, output [24:0]reqMat);
  assign reqMat[4:0] = rc0; // row 1
  assign reqMat[9:5] = rc1; // row 2
  assign reqMat[14:10] = rc2;// row 3
  assign reqMat[19:15] = rc3;// row 4
  assign reqMat[24:20] = rc4;//row 5
endmodule
