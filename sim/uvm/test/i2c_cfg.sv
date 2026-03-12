class i2c_cfg extends uvm_object;
  `uvm_object_utils(i2c_cfg)

  int unsigned t_high = 200;
  int unsigned t_low  = 200;
  int unsigned scl_low_extra = 0;

  function new(string name = "i2c_cfg");
    super.new(name);
  endfunction
endclass
