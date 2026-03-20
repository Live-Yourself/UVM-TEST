class i2c_base_test extends uvm_test;
  `uvm_component_utils(i2c_base_test)

  i2c_env env;
  i2c_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_cmdline_processor clp;
    string arg_val;
    super.build_phase(phase);
    env = i2c_env::type_id::create("env", this);
    cfg = i2c_cfg::type_id::create("cfg");

    clp = uvm_cmdline_processor::get_inst();
    if (clp.get_arg_value("+SCB_SRC=", arg_val)) begin
      if ((arg_val == "MON") || (arg_val == "mon"))
        cfg.use_monitor_primary = 1'b1;
      else if ((arg_val == "DRV") || (arg_val == "drv"))
        cfg.use_monitor_primary = 1'b0;
    end

    if (clp.get_arg_value("+SCB_COMPARE=", arg_val))
      cfg.enable_mon_drv_compare = (arg_val.atoi() != 0);

    `uvm_info("CFG", $sformatf("scoreboard primary=%s compare=%0d", cfg.use_monitor_primary ? "MON" : "DRV", cfg.enable_mon_drv_compare), UVM_LOW)

    uvm_config_db#(i2c_cfg)::set(this, "env", "cfg", cfg);
    uvm_config_db#(i2c_cfg)::set(this, "env.scb", "cfg", cfg);
    uvm_config_db#(i2c_cfg)::set(this, "env.agent*", "cfg", cfg);
  endfunction
endclass

class i2c_smoke_test extends i2c_base_test;
  `uvm_component_utils(i2c_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i2c_smoke_seq seq;
    phase.raise_objection(this);
    seq = i2c_smoke_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #1000ns;
    phase.drop_objection(this);
  endtask
endclass

class i2c_illegal_addr_test extends i2c_base_test;
  `uvm_component_utils(i2c_illegal_addr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i2c_illegal_addr_seq seq;
    phase.raise_objection(this);
    seq = i2c_illegal_addr_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #1000ns;
    phase.drop_objection(this);
  endtask
endclass

class i2c_illegal_read_test extends i2c_base_test;
  `uvm_component_utils(i2c_illegal_read_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i2c_illegal_read_seq seq;
    phase.raise_objection(this);
    seq = i2c_illegal_read_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #1000ns;
    phase.drop_objection(this);
  endtask
endclass

class i2c_stretch_test extends i2c_base_test;
  `uvm_component_utils(i2c_stretch_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.scl_low_extra = 300;
  endfunction

  task run_phase(uvm_phase phase);
    i2c_clock_stretch_seq seq;
    phase.raise_objection(this);
    seq = i2c_clock_stretch_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #1000ns;
    phase.drop_objection(this);
  endtask
endclass

class i2c_rand_burst_test extends i2c_base_test;
  `uvm_component_utils(i2c_rand_burst_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i2c_rand_burst_seq seq;
    phase.raise_objection(this);
    seq = i2c_rand_burst_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #2000ns;
    phase.drop_objection(this);
  endtask
endclass

class i2c_cov_closure_test extends i2c_base_test;
  `uvm_component_utils(i2c_cov_closure_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i2c_cov_closure_seq seq;
    phase.raise_objection(this);
    seq = i2c_cov_closure_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000ns;
    phase.drop_objection(this);
  endtask
endclass


