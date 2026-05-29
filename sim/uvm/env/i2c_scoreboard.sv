`uvm_analysis_imp_decl(_drv)
`uvm_analysis_imp_decl(_mon)

class i2c_scoreboard extends uvm_component;
  `uvm_component_utils(i2c_scoreboard)

  uvm_analysis_imp_drv#(i2c_item, i2c_scoreboard) imp_drv;
  uvm_analysis_imp_mon#(i2c_item, i2c_scoreboard) imp_mon;
  i2c_cfg cfg;
  i2c_cov cov;

  byte unsigned model_mem [byte unsigned];

  // Driver-vs-monitor consistency telemetry
  string drv_sig_q[$];
  string mon_sig_q[$];
  int unsigned cmp_pair_cnt;
  int unsigned cmp_mismatch_cnt;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_drv = new("imp_drv", this);
    imp_mon = new("imp_mon", this);
    cov = i2c_cov::type_id::create("cov", this);
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
    bit read_compared_i;

    read_compared_i = 1'b0;

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

    if (tr.op == I2C_WRITE && tr.dev_addr == 7'h42) begin
      for (i = 0; i < tr.wdata.size(); i++) begin
        model_mem[tr.reg_addr + i] = tr.wdata[i];
      end
      `uvm_info("SCB", $sformatf("[%s] Model update reg=0x%02h data0=0x%02h", src, tr.reg_addr, tr.wdata[0]), UVM_MEDIUM)
    end

    if (tr.op == I2C_READ && tr.dev_addr == 7'h42) begin
      if (tr.rdata.size() == 0) begin
        `uvm_error("SCB", $sformatf("[%s] READ transaction has empty rdata", src))
        cov.collect(txn_kind_i, addr_bucket_i, len_bucket_i, ack_kind_i, rd_cmp_i, is_read_i, legal_i, read_compared_i);
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
            `uvm_error("SCB", $sformatf("[%s] READ mismatch reg=0x%02h exp=0x%02h got=0x%02h rd_len=%0d rlen=%0d ack=%p", src, tr.reg_addr + i, exp, tr.rdata[i], tr.rd_len, tr.rdata.size(), tr.ack_bits))
          end
        else
          `uvm_info("SCB", $sformatf("[%s] READ match reg=0x%02h data=0x%02h", src, tr.reg_addr + i, tr.rdata[i]), UVM_MEDIUM)
      end

      read_compared_i = 1'b1;
      if (mismatch_any) begin
        rd_cmp_i = 2'd2;
      end else begin
        rd_cmp_i = 2'd1;
      end
    end

    cov.collect(txn_kind_i, addr_bucket_i, len_bucket_i, ack_kind_i, rd_cmp_i, is_read_i, legal_i, read_compared_i);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    cov.report();
    `uvm_info("SCB_CMP", $sformatf("primary=%s drv_q=%0d mon_q=%0d pairs=%0d mismatches=%0d compare_en=%0d", cfg.use_monitor_primary ? "MON" : "DRV", drv_sig_q.size(), mon_sig_q.size(), cmp_pair_cnt, cmp_mismatch_cnt, cfg.enable_mon_drv_compare), UVM_LOW)
  endfunction
endclass
