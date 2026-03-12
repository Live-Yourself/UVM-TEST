interface i2c_if;
  logic clk;
  logic rst_n;

  logic scl;
  logic sda_drv_low;
  logic sda_oe_dut;
  tri1  sda;
  logic sda_in;

  assign sda    = (sda_drv_low || sda_oe_dut) ? 1'b0 : 1'bz;
  assign sda_in = sda;

  task init_bus();
    scl         = 1'b1;
    sda_drv_low = 1'b0;
  endtask
endinterface
