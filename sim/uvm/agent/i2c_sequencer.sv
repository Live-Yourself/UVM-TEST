class i2c_sequencer extends uvm_sequencer#(i2c_item);
  `uvm_component_utils(i2c_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
