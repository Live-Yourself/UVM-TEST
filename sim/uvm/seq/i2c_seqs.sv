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
  rand int unsigned rounds;
  rand int unsigned illegal_pct;

  constraint c_burst {
    burst_len == 5;
    start_reg inside {[8'h00:8'hF0]};
    rounds inside {[1:10]};
    illegal_pct inside {[0:100]};
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
    int rnum;
    int ipct;
    int rr;
    bit [7:0] reg_lo;
    bit [7:0] reg_hi;
    int unsigned eff_burst_len;
    int unsigned eff_rounds;
    int unsigned eff_illegal_pct;
    bit do_illegal;

    clp = uvm_cmdline_processor::get_inst();
    reg_lo = 8'h00;
    reg_hi = 8'hF0;

    if (!randomize())
      `uvm_fatal("SEQ", "randomize burst seq failed")

    // Must set after randomize(); otherwise burst_len may be uninitialized.
    eff_burst_len = burst_len;
    eff_rounds = rounds;
    eff_illegal_pct = illegal_pct;

    if (clp.get_arg_value("+BURST_LEN=", arg_val)) begin
      blen = arg_val.atoi();
      if (blen >= 1 && blen <= 16)
        eff_burst_len = blen;
    end

    if (clp.get_arg_value("+RAND_ROUNDS=", arg_val)) begin
      rnum = arg_val.atoi();
      if (rnum >= 1 && rnum <= 64)
        eff_rounds = rnum;
    end

    if (clp.get_arg_value("+ILLEGAL_PCT=", arg_val)) begin
      ipct = arg_val.atoi();
      if (ipct < 0)
        ipct = 0;
      if (ipct > 100)
        ipct = 100;
      eff_illegal_pct = ipct;
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

    for (rr = 0; rr < eff_rounds; rr++) begin
      if (!std::randomize(start_reg) with { start_reg inside {[reg_lo:reg_hi]}; })
        `uvm_fatal("SEQ", "randomize start_reg failed")

      do_illegal = ($urandom_range(0, 99) < eff_illegal_pct);

      wr = i2c_item::type_id::create($sformatf("wr_%0d", rr));
      start_item(wr);
      if (!wr.randomize() with {
        op == I2C_WRITE;
        dev_addr == (do_illegal ? 7'h55 : 7'h42);
        reg_addr == start_reg;
        wdata.size() == (do_illegal ? 1 : eff_burst_len);
      }) begin
        `uvm_fatal("SEQ", "randomize write item failed")
      end
      finish_item(wr);

      rd = i2c_item::type_id::create($sformatf("rd_%0d", rr));
      start_item(rd);
      if (!rd.randomize() with {
        op == I2C_READ;
        dev_addr == (do_illegal ? 7'h55 : 7'h42);
        reg_addr == start_reg;
        wdata.size() == 0;
        rd_len == (do_illegal ? 1 : eff_burst_len);
      }) begin
        `uvm_fatal("SEQ", "randomize read item failed")
      end
      finish_item(rd);
    end
  endtask
endclass

class i2c_cov_closure_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_cov_closure_seq)

  function new(string name = "i2c_cov_closure_seq");
    super.new(name);
  endfunction

  virtual task body();
    i2c_item wr;
    i2c_item rd;
    i2c_item ill_wr;
    i2c_item ill_rd;
    int i;
    int j;
    int k;
    int unsigned lens[3];
    bit [7:0] base_addr[3];

    // 3x3 matrix: addr(low/mid/high) x len(1/3/8)
    lens[0] = 1;
    lens[1] = 3;
    lens[2] = 8;
    base_addr[0] = 8'h10; // LOW
    base_addr[1] = 8'h50; // MID
    base_addr[2] = 8'hD0; // HIGH

    for (i = 0; i < 3; i++) begin
      for (j = 0; j < 3; j++) begin
        wr = i2c_item::type_id::create($sformatf("wr_%0d_%0d", i, j));
        start_item(wr);
        wr.op       = I2C_WRITE;
        wr.dev_addr = 7'h42;
        wr.reg_addr = base_addr[i] + j;
        wr.rd_len   = 0;
        wr.wdata    = new[lens[j]];
        for (k = 0; k < lens[j]; k++)
          wr.wdata[k] = ((base_addr[i] + j + k) ^ 8'hA5);
        finish_item(wr);

        rd = i2c_item::type_id::create($sformatf("rd_%0d_%0d", i, j));
        start_item(rd);
        rd.op       = I2C_READ;
        rd.dev_addr = 7'h42;
        rd.reg_addr = base_addr[i] + j;
        rd.wdata    = new[0];
        rd.rd_len   = lens[j];
        finish_item(rd);
      end
    end

    // Illegal write/read to guarantee illegal buckets and NACK path
    for (i = 0; i < 2; i++) begin
      ill_wr = i2c_item::type_id::create($sformatf("ill_wr_%0d", i));
      start_item(ill_wr);
      ill_wr.op       = I2C_WRITE;
      ill_wr.dev_addr = 7'h55;
      ill_wr.reg_addr = (i == 0) ? 8'h22 : 8'hC8;
      ill_wr.rd_len   = 0;
      ill_wr.wdata    = new[1];
      ill_wr.wdata[0] = 8'h3C;
      finish_item(ill_wr);

      ill_rd = i2c_item::type_id::create($sformatf("ill_rd_%0d", i));
      start_item(ill_rd);
      ill_rd.op       = I2C_READ;
      ill_rd.dev_addr = 7'h55;
      ill_rd.reg_addr = (i == 0) ? 8'h24 : 8'hCC;
      ill_rd.wdata    = new[0];
      ill_rd.rd_len   = 1;
      finish_item(ill_rd);
    end
  endtask
endclass
