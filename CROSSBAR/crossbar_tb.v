`timescale 1ns/1ps

module tb_crossbar;
  parameter int DATA_WIDTH = 8;

  logic [2:0]selsignal [4:0];
  logic [DATA_WIDTH-1:0]input_data [4:0];
  wire  [DATA_WIDTH-1:0]final_out  [4:0];
  
  crossbar #(DATA_WIDTH) inst1 (
    selsignal,input_data,final_out
  );
// in sv we can create these task blocks // display-->\n but write no \n
  task print_state(input string str);
    begin
      $display("----- %s at %0t -----", str,$time);
      for(int i=0;i<5;i=i+1) begin
        $write("in%0d=%0h ", i,input_data[i]);
        $write("||");
      end
      for (int i=0;i<5;i=i+1) begin
        if (selsignal[i]==3'b111)
          $write("out%0d->NA",i);
        else
          $write("out%0d->in%0d  ",i,selsignal[i]);
      end
      $write("||");
      for (int i=0;i<5;i=i+1) begin
        $write("out%0d=%0h  ", i, final_out[i]);
        $write("||");
      end
      $display("");
    end
  endtask

  initial begin
    #0;//clearring evrything at first
    for (int i=0;i<5;i=i+1) begin
      input_data[i]='0;
      selsignal[i]=3'b111;
    end
    #2;//giving random inputs to the 5input portsa
    input_data[0] = 8'hA1;
    input_data[1] = 8'hB2;
    input_data[2] = 8'hC3;
    input_data[3] = 8'hD4;
    input_data[4] = 8'hE5;
	//assigning which output gets which input
    selsignal[0] = 3'd0;
    selsignal[1] = 3'd1;
    selsignal[2] = 3'd2;
    selsignal[3] = 3'd3;
    selsignal[4] = 3'd4;
    #1;
    print_state("normalcase,each output gets a unique input");
    #5;
    selsignal[0] = 3'b111;
    selsignal[1] = 3'b111;
    selsignal[2] = 3'd4;
    selsignal[3] = 3'd0;
    selsignal[4] = 3'b111;
    #1;
    print_state("no winner cases");
    #5;

    $finish;
  end

endmodule
