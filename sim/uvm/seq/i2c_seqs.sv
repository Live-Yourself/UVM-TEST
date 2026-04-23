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
    int rr;

    // Dedicated clock-stretch stress:
    // legal WRITE-only traffic, short length, repeated transactions.
    // Avoids overlap with smoke(readback) and illegal tests.
    for (rr = 0; rr < 6; rr++) begin
      tr = i2c_item::type_id::create($sformatf("tr_%0d", rr));
      start_item(tr);
      tr.op       = I2C_WRITE;
      tr.dev_addr = 7'h42;
      tr.reg_addr = 8'h68 + rr; // MID bucket
      tr.wdata    = new[2];     // short length bucket
      tr.wdata[0] = 8'h50 + rr;
      tr.wdata[1] = 8'hA0 + rr;
      finish_item(tr);
    end
  endtask
endclass

class i2c_rand_burst_seq extends i2c_base_seq;
  `uvm_object_utils(i2c_rand_burst_seq)

  rand int unsigned burst_len;
  rand bit [7:0] start_reg;
  rand int unsigned rounds;

  constraint c_burst {
    burst_len == 5;
    start_reg inside {[8'h00:8'hF0]};
    rounds inside {[1:10]};
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
    int rr;
    bit [7:0] reg_lo;
    bit [7:0] reg_hi;
    int unsigned eff_burst_len;
    int unsigned eff_rounds;

    clp = uvm_cmdline_processor::get_inst();
    reg_lo = 8'h00;
    reg_hi = 8'hF0;

    if (!randomize())
      `uvm_fatal("SEQ", "randomize burst seq failed")

    // Must set after randomize(); otherwise burst_len may be uninitialized.
    eff_burst_len = burst_len;
    eff_rounds = rounds;

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

      wr = i2c_item::type_id::create($sformatf("wr_%0d", rr));
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

      rd = i2c_item::type_id::create($sformatf("rd_%0d", rr));
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
    int i;
    int j;
    int k;
    int unsigned lens[2];
    bit [7:0] base_addr[3];

    // Focused legal closure matrix (deterministic):
    // addr(low/mid/high) x len(short/burst).
    // Excludes illegal traffic (covered by dedicated illegal tests)
    // and excludes single-len smoke point to reduce overlap.
    lens[0] = 3;
    lens[1] = 8;
    base_addr[0] = 8'h10; // LOW
    base_addr[1] = 8'h50; // MID
    base_addr[2] = 8'hD0; // HIGH

    for (i = 0; i < 3; i++) begin
      for (j = 0; j < 2; j++) begin
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
  endtask
endclass
