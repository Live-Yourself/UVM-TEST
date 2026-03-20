class i2c_env extends uvm_env;
  `uvm_component_utils(i2c_env)

  i2c_agent      agent;
  i2c_scoreboard scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = i2c_agent::type_id::create("agent", this);
    scb   = i2c_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.drv.ap.connect(scb.imp_drv);
    agent.mon.ap.connect(scb.imp_mon);
  endfunction
endclass
