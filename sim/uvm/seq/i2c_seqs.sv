class i2c_base_seq extends uvm_sequence#(i2c_item);
  `uvm_object_utils(i2c_base_seq)

  function new(string name = "i2c_base_seq");
    super.new(name);
  endfunction
endclass

class i2c_smoke_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_smoke_seq)

  function new(string name = "i2c_smoke_seq");
    super.new(name);
  endfunction

  virtual task body();
    i2c_item wr;
    i2c_item rd;

    wr = i2c_item::type_id::create("wr");
    start_item(wr);
    wr.op       = I2C_WRITE;
    wr.dev_addr = 7'h42;
    wr.reg_addr = 8'h10;
    wr.wdata    = new[1];
    wr.wdata[0] = 8'hA5;
    finish_item(wr);

    rd = i2c_item::type_id::create("rd");
    start_item(rd);
    rd.op       = I2C_READ;
    rd.dev_addr = 7'h42;
    rd.reg_addr = 8'h10;
    finish_item(rd);
  endtask
endclass

class i2c_illegal_addr_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_illegal_addr_seq)

  function new(string name = "i2c_illegal_addr_seq");
    super.new(name);
  endfunction

  virtual task body();
    i2c_item tr;
    tr = i2c_item::type_id::create("tr");
    start_item(tr);
    tr.op       = I2C_WRITE;
    tr.dev_addr = 7'h55;
    tr.reg_addr = 8'h20;
    tr.wdata    = new[1];
    tr.wdata[0] = 8'h3C;
    finish_item(tr);
  endtask
endclass

class i2c_clock_stretch_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_clock_stretch_seq)

  function new(string name = "i2c_clock_stretch_seq");
    super.new(name);
  endfunction

  virtual task body();
    i2c_item tr;
    tr = i2c_item::type_id::create("tr");
    start_item(tr);
    tr.op       = I2C_WRITE;
    tr.dev_addr = 7'h42;
    tr.reg_addr = 8'h30;
    tr.wdata    = new[1];
    tr.wdata[0] = 8'h5A;
    finish_item(tr);
  endtask
endclass

class i2c_rand_burst_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_rand_burst_seq)

  rand int unsigned burst_len;
  rand bit [7:0] start_reg;

  constraint c_burst {
    burst_len == 5;
    start_reg inside {[8'h00:8'hF0]};
  }

  function new(string name = "i2c_rand_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    i2c_item wr;
    i2c_item rd;

    if (!randomize())
      `uvm_fatal("SEQ", "randomize burst seq failed")

    wr = i2c_item::type_id::create("wr");
    start_item(wr);
    if (!wr.randomize() with {
      op == I2C_WRITE;
      dev_addr == 7'h42;
      reg_addr == start_reg;
      wdata.size() == burst_len;
    }) begin
      `uvm_fatal("SEQ", "randomize write item failed")
    end
    finish_item(wr);

    rd = i2c_item::type_id::create("rd");
    start_item(rd);
    if (!rd.randomize() with {
      op == I2C_READ;
      dev_addr == 7'h42;
      reg_addr == start_reg;
      wdata.size() == 0;
      rd_len == burst_len;
    }) begin
      `uvm_fatal("SEQ", "randomize read item failed")
    end
    finish_item(rd);
  endtask
endclass
