`uvm_analysis_imp_decl(_drv)
`uvm_analysis_imp_decl(_mon)

class i2c_scoreboard extends uvm_component;
  `uvm_component_utils(i2c_scoreboard)

  uvm_analysis_imp_drv#(i2c_item, i2c_scoreboard) imp_drv;
  uvm_analysis_imp_mon#(i2c_item, i2c_scoreboard) imp_mon;
  i2c_cfg cfg;

  byte unsigned model_mem [byte unsigned];
  real func_cov_pct;
  int unsigned txn_cnt;
  int unsigned read_cmp_cnt;
  int unsigned read_mismatch_txn_cnt;
  bit hit_addr_low;
  bit hit_addr_mid;
  bit hit_addr_high;
  bit hit_legal_wr;
  bit hit_legal_rd;
  bit hit_illegal_wr;
  bit hit_illegal_rd;
  bit hit_len_single;
  bit hit_len_short;
  bit hit_len_burst;
  bit hit_illegal_read;
  bit hit_ack_all;
  bit hit_ack_nack;
  bit hit_rd_cmp_match;

  // Driver-vs-monitor consistency telemetry
  string drv_sig_q[$];
  string mon_sig_q[$];
  int unsigned cmp_pair_cnt;
  int unsigned cmp_mismatch_cnt;

  // Requirement-driven functional coverage model:
  // 1) transaction legality/op path
  // 2) address region
  // 3) length class
  // 4) ACK quality
  // 5) read compare result quality
  covergroup cg_i2c_func with function sample(
    bit [1:0]   txn_kind_i,
    bit [1:0]   addr_bucket_i,
    bit [1:0]   len_bucket_i,
    bit [1:0]   ack_kind_i,
    bit [1:0]   rd_cmp_i
  );
    option.per_instance = 1;

    // 0:legal_wr, 1:legal_rd, 2:illegal_wr, 3:illegal_rd
    cp_txn_kind : coverpoint txn_kind_i {
      bins legal_wr   = {0};
      bins legal_rd   = {1};
      bins illegal_wr = {2};
      bins illegal_rd = {3};
    }

    cp_addr_bucket : coverpoint addr_bucket_i {
      bins low  = {0};
      bins mid  = {1};
      bins high = {2};
    }

    // 0:none, 1:single, 2:short(2..4), 3:burst(>=5)
    cp_len_bucket : coverpoint len_bucket_i {
      ignore_bins none = {0};
      bins single = {1};
      bins short  = {2};
      bins burst  = {3};
    }

    // 0:none, 1:all_ack, 2:has_nack
    cp_ack_kind : coverpoint ack_kind_i {
      ignore_bins none = {0};
      bins all_ack  = {1};
      bins has_nack = {2};
    }

    // 0:not_applicable(write/illegal), 1:all_match, 2:has_mismatch
    cp_rd_cmp : coverpoint rd_cmp_i {
      bins na           = {0};
      bins all_match    = {1};
      ignore_bins has_mismatch = {2};
    }

    cx_txn_addr : cross cp_txn_kind, cp_addr_bucket;
    cx_txn_len : cross cp_txn_kind, cp_len_bucket {
      ignore_bins illegal_none =
        (binsof(cp_txn_kind.illegal_wr) || binsof(cp_txn_kind.illegal_rd)) &&
        binsof(cp_len_bucket.none);
    }
    cx_legal_rd_cmp : cross cp_txn_kind, cp_rd_cmp {
      ignore_bins non_read_path =
        (binsof(cp_txn_kind.legal_wr) || binsof(cp_txn_kind.illegal_wr) || binsof(cp_txn_kind.illegal_rd)) &&
        (binsof(cp_rd_cmp.all_match) || binsof(cp_rd_cmp.has_mismatch));
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_drv = new("imp_drv", this);
    imp_mon = new("imp_mon", this);
    cg_i2c_func = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(i2c_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = i2c_cfg::type_id::create("cfg");
      `uvm_warning("NOCFG", "scoreboard cfg not set, use default")
    end
  endfunction

  function string tr_sig(i2c_item tr);
    int unsigned n;
    bit is_read_i;
    is_read_i = (tr.op == I2C_READ);
    n = is_read_i ? ((tr.rd_len != 0) ? tr.rd_len : tr.rdata.size()) : tr.wdata.size();
    return $sformatf("op=%0d dev=0x%02h reg=0x%02h len=%0d", tr.op, tr.dev_addr, tr.reg_addr, n);
  endfunction

  function void try_compare_streams();
    string d;
    string m;
    while ((drv_sig_q.size() > 0) && (mon_sig_q.size() > 0)) begin
      d = drv_sig_q.pop_front();
      m = mon_sig_q.pop_front();
      cmp_pair_cnt++;
      if (d != m) begin
        cmp_mismatch_cnt++;
        if (cfg.enable_mon_drv_compare)
          `uvm_warning("SCB_CMP", $sformatf("drv/mon mismatch drv={%s} mon={%s}", d, m))
      end
    end
  endfunction

  function void write_drv(i2c_item tr);
    drv_sig_q.push_back(tr_sig(tr));
    try_compare_streams();
    if (!cfg.use_monitor_primary)
      process_tr(tr, "DRV");
  endfunction

  function void write_mon(i2c_item tr);
    mon_sig_q.push_back(tr_sig(tr));
    try_compare_streams();
    if (cfg.use_monitor_primary)
      process_tr(tr, "MON");
  endfunction

  function void process_tr(i2c_item tr, string src);
    int i;
    bit is_read_i;
    bit legal_i;
    bit [1:0] txn_kind_i;
    bit [1:0] addr_bucket_i;
    bit [1:0] len_bucket_i;
    bit [1:0] ack_kind_i;
    bit [1:0] rd_cmp_i;
    int unsigned tr_len;
    byte unsigned exp;
    int unsigned n;
    bit mismatch_any;

    txn_cnt++;

    is_read_i = (tr.op == I2C_READ);
    legal_i = (tr.dev_addr == 7'h42);
    if (legal_i && !is_read_i)
      txn_kind_i = 2'd0;
    else if (legal_i && is_read_i)
      txn_kind_i = 2'd1;
    else if (!legal_i && !is_read_i)
      txn_kind_i = 2'd2;
    else
      txn_kind_i = 2'd3;

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

    rd_cmp_i = 2'd0;
    mismatch_any = 1'b0;

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

    case (txn_kind_i)
      2'd0: hit_legal_wr = 1'b1;
      2'd1: hit_legal_rd = 1'b1;
      2'd2: hit_illegal_wr = 1'b1;
      2'd3: hit_illegal_rd = 1'b1;
      default: ;
    endcase

    case (ack_kind_i)
      2'd1: hit_ack_all = 1'b1;
      2'd2: hit_ack_nack = 1'b1;
      default: ;
    endcase

    if (is_read_i && !legal_i)
      hit_illegal_read = 1'b1;

    if (tr.op == I2C_WRITE && tr.dev_addr == 7'h42) begin
      for (i = 0; i < tr.wdata.size(); i++) begin
        model_mem[tr.reg_addr + i] = tr.wdata[i];
      end
      `uvm_info("SCB", $sformatf("[%s] Model update reg=0x%02h data0=0x%02h", src, tr.reg_addr, tr.wdata[0]), UVM_MEDIUM)
    end

    if (tr.op == I2C_READ && tr.dev_addr == 7'h42) begin
      if (tr.rdata.size() == 0) begin
        `uvm_error("SCB", $sformatf("[%s] READ transaction has empty rdata", src))
        return;
      end

      n = tr.rdata.size();
      if (tr.rd_len != 0 && tr.rd_len != n)
        `uvm_warning("SCB", $sformatf("[%s] READ length mismatch req=%0d got=%0d", src, tr.rd_len, n))

      for (i = 0; i < n; i++) begin
        if (!model_mem.exists(tr.reg_addr + i)) begin
          exp = 8'h00;
        end else begin
          exp = model_mem[tr.reg_addr + i];
        end

        if (tr.rdata[i] !== exp)
          begin
            mismatch_any = 1'b1;
            `uvm_error("SCB", $sformatf("[%s] READ mismatch reg=0x%02h exp=0x%02h got=0x%02h", src, tr.reg_addr + i, exp, tr.rdata[i]))
          end
        else
          `uvm_info("SCB", $sformatf("[%s] READ match reg=0x%02h data=0x%02h", src, tr.reg_addr + i, tr.rdata[i]), UVM_MEDIUM)
      end

      read_cmp_cnt++;
      if (mismatch_any) begin
        rd_cmp_i = 2'd2;
        read_mismatch_txn_cnt++;
      end else begin
        rd_cmp_i = 2'd1;
        hit_rd_cmp_match = 1'b1;
      end
    end

    cg_i2c_func.sample(txn_kind_i, addr_bucket_i, len_bucket_i, ack_kind_i, rd_cmp_i);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    func_cov_pct = cg_i2c_func.get_inst_coverage();
    if (txn_cnt == 0)
      `uvm_error("SCB_FCOV", "no transactions reached scoreboard, functional coverage is invalid")
    `uvm_info("SCB_FCOV", $sformatf("functional_coverage=%0.2f%% samples=%0d", func_cov_pct, txn_cnt), UVM_LOW)
    `uvm_info("SCB_FCOV", $sformatf("read_compare_txn=%0d read_mismatch_txn=%0d", read_cmp_cnt, read_mismatch_txn_cnt), UVM_LOW)
    `uvm_info("SCB_CMP", $sformatf("primary=%s drv_q=%0d mon_q=%0d pairs=%0d mismatches=%0d compare_en=%0d", cfg.use_monitor_primary ? "MON" : "DRV", drv_sig_q.size(), mon_sig_q.size(), cmp_pair_cnt, cmp_mismatch_cnt, cfg.enable_mon_drv_compare), UVM_LOW)
    `uvm_info("SCB_BUCKET", $sformatf("addr_low=%0d addr_mid=%0d addr_high=%0d len_single=%0d len_short=%0d len_burst=%0d illegal_read=%0d", hit_addr_low, hit_addr_mid, hit_addr_high, hit_len_single, hit_len_short, hit_len_burst, hit_illegal_read), UVM_LOW)
    `uvm_info("SCB_BUCKET2", $sformatf("legal_wr=%0d legal_rd=%0d illegal_wr=%0d illegal_rd=%0d ack_all=%0d ack_nack=%0d rd_match=%0d", hit_legal_wr, hit_legal_rd, hit_illegal_wr, hit_illegal_rd, hit_ack_all, hit_ack_nack, hit_rd_cmp_match), UVM_LOW)
  endfunction
endclass
