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

class i2c_illegal_read_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_illegal_read_seq)

  function new(string name = "i2c_illegal_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    i2c_item tr;
    tr = i2c_item::type_id::create("tr");
    start_item(tr);
    tr.op       = I2C_READ;
    tr.dev_addr = 7'h55;
    tr.reg_addr = 8'h20;
    tr.rd_len   = 1;
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
    uvm_cmdline_processor clp;
    string arg_val;
    int blen;
    bit [7:0] reg_lo;
    bit [7:0] reg_hi;
    int unsigned eff_burst_len;

    clp = uvm_cmdline_processor::get_inst();
    reg_lo = 8'h00;
    reg_hi = 8'hF0;

    if (!randomize())
      `uvm_fatal("SEQ", "randomize burst seq failed")

    // Must set after randomize(); otherwise burst_len may be uninitialized.
    eff_burst_len = burst_len;

    if (clp.get_arg_value("+BURST_LEN=", arg_val)) begin
      blen = arg_val.atoi();
      if (blen >= 1 && blen <= 16)
        eff_burst_len = blen;
    end

    if (clp.get_arg_value("+ADDR_BUCKET=", arg_val)) begin
      if ((arg_val == "LOW") || (arg_val == "low")) begin
        reg_lo = 8'h00;
        reg_hi = 8'h3F;
      end else if ((arg_val == "MID") || (arg_val == "mid")) begin
        reg_lo = 8'h40;
        reg_hi = 8'hBF;
      end else if ((arg_val == "HIGH") || (arg_val == "high")) begin
        reg_lo = 8'hC0;
        reg_hi = 8'hF0;
      end
    end

    if (!std::randomize(start_reg) with { start_reg inside {[reg_lo:reg_hi]}; })
      `uvm_fatal("SEQ", "randomize start_reg failed")

    wr = i2c_item::type_id::create("wr");
    start_item(wr);
    if (!wr.randomize() with {
      op == I2C_WRITE;
      dev_addr == 7'h42;
      reg_addr == start_reg;
      wdata.size() == eff_burst_len;
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
      rd_len == eff_burst_len;
    }) begin
      `uvm_fatal("SEQ", "randomize read item failed")
    end
    finish_item(rd);
  endtask
endclass
