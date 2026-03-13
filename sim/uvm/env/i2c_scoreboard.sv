class i2c_scoreboard extends uvm_component;
  `uvm_component_utils(i2c_scoreboard)

  uvm_analysis_imp#(i2c_item, i2c_scoreboard) imp;
  byte unsigned model_mem [byte unsigned];
  real func_cov_pct;
  int unsigned txn_cnt;
  bit hit_addr_low;
  bit hit_addr_mid;
  bit hit_addr_high;
  bit hit_len_single;
  bit hit_len_short;
  bit hit_len_burst;
  bit hit_illegal_read;

  // Compact and convergent functional coverage model:
  // - sample once per transaction from scoreboard write()
  // - bounded buckets to avoid huge denominator and slow convergence
  covergroup cg_i2c_func with function sample(
    bit         is_read_i,
    bit         legal_i,
    bit [1:0]   addr_bucket_i,
    bit [1:0]   len_bucket_i,
    bit [1:0]   ack_kind_i
  );
    cp_op : coverpoint is_read_i {
      bins write = {0};
      bins read  = {1};
    }

    cp_legal : coverpoint legal_i {
      bins legal   = {1};
      bins illegal = {0};
    }

    cp_addr_bucket : coverpoint addr_bucket_i {
      bins low  = {0};
      bins mid  = {1};
      bins high = {2};
    }

    // 0:none, 1:single, 2:short(2..4), 3:burst(>=5)
    cp_len_bucket : coverpoint len_bucket_i {
      bins none   = {0};
      bins single = {1};
      bins short  = {2};
      bins burst  = {3};
    }

    // 0:none, 1:all_ack, 2:has_nack
    cp_ack_kind : coverpoint ack_kind_i {
      bins none     = {0};
      bins all_ack  = {1};
      bins has_nack = {2};
    }

    cx_op_legal : cross cp_op, cp_legal;
    cx_read_len : cross cp_op, cp_len_bucket {
      ignore_bins write_side = binsof(cp_op.write) &&
                               (binsof(cp_len_bucket.single) || binsof(cp_len_bucket.short) || binsof(cp_len_bucket.burst));
    }
    cx_write_len : cross cp_op, cp_len_bucket {
      ignore_bins read_none = binsof(cp_op.read) && binsof(cp_len_bucket.none);
    }
    cx_op_ack : cross cp_op, cp_ack_kind {
      ignore_bins no_ack_when_rw = (binsof(cp_op.write) || binsof(cp_op.read)) && binsof(cp_ack_kind.none);
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
    cg_i2c_func = new();
  endfunction

  function void write(i2c_item tr);
    int i;
    bit is_read_i;
    bit legal_i;
    bit [1:0] addr_bucket_i;
    bit [1:0] len_bucket_i;
    bit [1:0] ack_kind_i;
    int unsigned tr_len;
    byte unsigned exp;
    int unsigned n;

    txn_cnt++;

    is_read_i = (tr.op == I2C_READ);
    legal_i = (tr.dev_addr == 7'h42);
    if (tr.reg_addr < 8'h40)
      addr_bucket_i = 2'd0;
    else if (tr.reg_addr < 8'hC0)
      addr_bucket_i = 2'd1;
    else
      addr_bucket_i = 2'd2;

    tr_len = is_read_i ? ((tr.rd_len != 0) ? tr.rd_len : tr.rdata.size()) : tr.wdata.size();
    if (tr_len == 0)
      len_bucket_i = 2'd0;
    else if (tr_len == 1)
      len_bucket_i = 2'd1;
    else if (tr_len <= 4)
      len_bucket_i = 2'd2;
    else
      len_bucket_i = 2'd3;

    if (tr.ack_bits.size() == 0) begin
      ack_kind_i = 2'd0;
    end else begin
      ack_kind_i = 2'd1;
      foreach (tr.ack_bits[i]) begin
        if (tr.ack_bits[i] == 1'b0)
          ack_kind_i = 2'd2;
      end
    end
    cg_i2c_func.sample(is_read_i, legal_i, addr_bucket_i, len_bucket_i, ack_kind_i);

    case (addr_bucket_i)
      2'd0: hit_addr_low = 1'b1;
      2'd1: hit_addr_mid = 1'b1;
      2'd2: hit_addr_high = 1'b1;
    endcase

    case (len_bucket_i)
      2'd1: hit_len_single = 1'b1;
      2'd2: hit_len_short = 1'b1;
      2'd3: hit_len_burst = 1'b1;
      default: ;
    endcase

    if (is_read_i && !legal_i)
      hit_illegal_read = 1'b1;

    if (tr.op == I2C_WRITE && tr.dev_addr == 7'h42) begin
      for (i = 0; i < tr.wdata.size(); i++) begin
        model_mem[tr.reg_addr + i] = tr.wdata[i];
      end
      `uvm_info("SCB", $sformatf("Model update reg=0x%02h data0=0x%02h", tr.reg_addr, tr.wdata[0]), UVM_MEDIUM)
    end

    if (tr.op == I2C_READ && tr.dev_addr == 7'h42) begin
      if (tr.rdata.size() == 0) begin
        `uvm_error("SCB", "READ transaction has empty rdata")
        return;
      end

      n = tr.rdata.size();
      if (tr.rd_len != 0 && tr.rd_len != n)
        `uvm_warning("SCB", $sformatf("READ length mismatch req=%0d got=%0d", tr.rd_len, n))

      for (i = 0; i < n; i++) begin
        if (!model_mem.exists(tr.reg_addr + i)) begin
          exp = 8'h00;
        end else begin
          exp = model_mem[tr.reg_addr + i];
        end

        if (tr.rdata[i] !== exp)
          `uvm_error("SCB", $sformatf("READ mismatch reg=0x%02h exp=0x%02h got=0x%02h", tr.reg_addr + i, exp, tr.rdata[i]))
        else
          `uvm_info("SCB", $sformatf("READ match reg=0x%02h data=0x%02h", tr.reg_addr + i, tr.rdata[i]), UVM_MEDIUM)
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    func_cov_pct = cg_i2c_func.get_inst_coverage();
    `uvm_info("SCB_FCOV", $sformatf("functional_coverage=%0.2f%% samples=%0d", func_cov_pct, txn_cnt), UVM_LOW)
    `uvm_info("SCB_BUCKET", $sformatf("addr_low=%0d addr_mid=%0d addr_high=%0d len_single=%0d len_short=%0d len_burst=%0d illegal_read=%0d", hit_addr_low, hit_addr_mid, hit_addr_high, hit_len_single, hit_len_short, hit_len_burst, hit_illegal_read), UVM_LOW)
  endfunction
endclass
