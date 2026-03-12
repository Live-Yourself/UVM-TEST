class i2c_monitor extends uvm_component;
  `uvm_component_utils(i2c_monitor)

  virtual i2c_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    bit sda_prev;
    sda_prev = vif.sda;
    forever begin
      @(vif.sda or vif.scl);
      if (vif.scl === 1'b1) begin
        if (sda_prev === 1'b1 && vif.sda === 1'b0)
          `uvm_info("MON", "START detected", UVM_HIGH)
        if (sda_prev === 1'b0 && vif.sda === 1'b1)
          `uvm_info("MON", "STOP detected", UVM_HIGH)
      end
      sda_prev = vif.sda;
    end
  endtask
endclass
