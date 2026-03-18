class i2c_base_test extends uvm_test;
  `uvm_component_utils(i2c_base_test)

  i2c_env env;
  i2c_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = i2c_env::type_id::create("env", this);
    cfg = i2c_cfg::type_id::create("cfg");
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


