`timescale 1ns/1ps

module tb_uvm_top;
  import uvm_pkg::*;
  import i2c_pkg::*;

  i2c_if i2c_vif();

  localparam [6:0] DEV_ADDR = 7'h42;

  i2c_slave_top #(
    .DEV_ADDR(DEV_ADDR)
  ) dut (
    .clk      (i2c_vif.clk),
    .rst_n    (i2c_vif.rst_n),
    .scl      (i2c_vif.scl),
    .sda_in   (i2c_vif.sda_in),
    .sda_oe   (i2c_vif.sda_oe_dut)
  );

  initial begin
    i2c_vif.clk = 1'b0;
    forever #10 i2c_vif.clk = ~i2c_vif.clk;
  end

  initial begin
    i2c_vif.rst_n = 1'b0;
    i2c_vif.sda_drv_low = 1'b0;
    i2c_vif.scl = 1'b1;
    #200;
    i2c_vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual i2c_if)::set(null, "uvm_test_top.env.agent*", "vif", i2c_vif);
    run_test();
  end

`ifdef DUMP_FSDB
  initial begin
    string fsdb_name;
    if (!$value$plusargs("FSDB_FILE=%s", fsdb_name))
      fsdb_name = "uvm_default.fsdb";
    $fsdbDumpfile(fsdb_name);
    $fsdbDumpvars(0, tb_uvm_top);
  end
`endif
endmodule
