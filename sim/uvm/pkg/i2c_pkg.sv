package i2c_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "i2c_cfg.sv"
  `include "i2c_item.sv"
  `include "i2c_sequencer.sv"
  `include "i2c_seqs.sv"
  `include "i2c_driver.sv"
  `include "i2c_monitor.sv"
  `include "i2c_agent.sv"
  `include "i2c_scoreboard.sv"
  `include "i2c_env.sv"
  `include "i2c_tests.sv"
endpackage
