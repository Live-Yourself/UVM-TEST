class i2c_cov extends uvm_object;
  `uvm_object_utils(i2c_cov)

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

  // Fine-grained coverage point export (align global cumulative metric with cg_i2c_func points)
  // coverpoints
  bit hit_cp_txn_legal_wr;
  bit hit_cp_txn_legal_rd;
  bit hit_cp_txn_illegal_wr;
  bit hit_cp_txn_illegal_rd;
  bit hit_cp_addr_low;
  bit hit_cp_addr_mid;
  bit hit_cp_addr_high;
  bit hit_cp_len_single;
  bit hit_cp_len_short;
  bit hit_cp_len_burst;
  bit hit_cp_ack_all_ack;
  bit hit_cp_ack_has_nack;
  bit hit_cp_rd_na;
  bit hit_cp_rd_all_match;

  // cross: cp_txn_kind x cp_addr_bucket (4x3)
  bit hit_cx_txn_addr_legal_wr_low;
  bit hit_cx_txn_addr_legal_wr_mid;
  bit hit_cx_txn_addr_legal_wr_high;
  bit hit_cx_txn_addr_legal_rd_low;
  bit hit_cx_txn_addr_legal_rd_mid;
  bit hit_cx_txn_addr_legal_rd_high;
  bit hit_cx_txn_addr_illegal_wr_low;
  bit hit_cx_txn_addr_illegal_wr_mid;
  bit hit_cx_txn_addr_illegal_wr_high;
  bit hit_cx_txn_addr_illegal_rd_low;
  bit hit_cx_txn_addr_illegal_rd_mid;
  bit hit_cx_txn_addr_illegal_rd_high;

  // cross: cp_txn_kind x cp_len_bucket (4x3)
  bit hit_cx_txn_len_legal_wr_single;
  bit hit_cx_txn_len_legal_wr_short;
  bit hit_cx_txn_len_legal_wr_burst;
  bit hit_cx_txn_len_legal_rd_single;
  bit hit_cx_txn_len_legal_rd_short;
  bit hit_cx_txn_len_legal_rd_burst;
  bit hit_cx_txn_len_illegal_wr_single;
  bit hit_cx_txn_len_illegal_wr_short;
  bit hit_cx_txn_len_illegal_wr_burst;
  bit hit_cx_txn_len_illegal_rd_single;
  bit hit_cx_txn_len_illegal_rd_short;
  bit hit_cx_txn_len_illegal_rd_burst;

  // cross: cp_txn_kind x cp_rd_cmp (effective bins after ignore rules)
  bit hit_cx_legal_rd_cmp_legal_wr_na;
  bit hit_cx_legal_rd_cmp_legal_rd_na;
  bit hit_cx_legal_rd_cmp_legal_rd_all_match;
  bit hit_cx_legal_rd_cmp_illegal_wr_na;
  bit hit_cx_legal_rd_cmp_illegal_rd_na;

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

  function new(string name = "i2c_cov");
    super.new(name);
    cg_i2c_func = new();
  endfunction

  function void collect(
    bit [1:0] txn_kind_i,
    bit [1:0] addr_bucket_i,
    bit [1:0] len_bucket_i,
    bit [1:0] ack_kind_i,
    bit [1:0] rd_cmp_i,
    bit       is_read_i,
    bit       legal_i,
    bit       read_compared_i
  );
    txn_cnt++;

    case (addr_bucket_i)
      2'd0: begin hit_addr_low = 1'b1; hit_cp_addr_low = 1'b1; end
      2'd1: begin hit_addr_mid = 1'b1; hit_cp_addr_mid = 1'b1; end
      2'd2: begin hit_addr_high = 1'b1; hit_cp_addr_high = 1'b1; end
      default: ;
    endcase

    case (len_bucket_i)
      2'd1: begin hit_len_single = 1'b1; hit_cp_len_single = 1'b1; end
      2'd2: begin hit_len_short = 1'b1; hit_cp_len_short = 1'b1; end
      2'd3: begin hit_len_burst = 1'b1; hit_cp_len_burst = 1'b1; end
      default: ;
    endcase

    case (txn_kind_i)
      2'd0: begin hit_legal_wr = 1'b1; hit_cp_txn_legal_wr = 1'b1; end
      2'd1: begin hit_legal_rd = 1'b1; hit_cp_txn_legal_rd = 1'b1; end
      2'd2: begin hit_illegal_wr = 1'b1; hit_cp_txn_illegal_wr = 1'b1; end
      2'd3: begin hit_illegal_rd = 1'b1; hit_cp_txn_illegal_rd = 1'b1; end
      default: ;
    endcase

    case (ack_kind_i)
      2'd1: begin hit_ack_all = 1'b1; hit_cp_ack_all_ack = 1'b1; end
      2'd2: begin hit_ack_nack = 1'b1; hit_cp_ack_has_nack = 1'b1; end
      default: ;
    endcase

    // cp_rd_cmp bins (effective: na, all_match)
    if (rd_cmp_i == 2'd0)
      hit_cp_rd_na = 1'b1;
    else if (rd_cmp_i == 2'd1)
      hit_cp_rd_all_match = 1'b1;

    // cx_txn_addr
    case (txn_kind_i)
      2'd0: case (addr_bucket_i)
        2'd0: hit_cx_txn_addr_legal_wr_low = 1'b1;
        2'd1: hit_cx_txn_addr_legal_wr_mid = 1'b1;
        2'd2: hit_cx_txn_addr_legal_wr_high = 1'b1;
        default: ;
      endcase
      2'd1: case (addr_bucket_i)
        2'd0: hit_cx_txn_addr_legal_rd_low = 1'b1;
        2'd1: hit_cx_txn_addr_legal_rd_mid = 1'b1;
        2'd2: hit_cx_txn_addr_legal_rd_high = 1'b1;
        default: ;
      endcase
      2'd2: case (addr_bucket_i)
        2'd0: hit_cx_txn_addr_illegal_wr_low = 1'b1;
        2'd1: hit_cx_txn_addr_illegal_wr_mid = 1'b1;
        2'd2: hit_cx_txn_addr_illegal_wr_high = 1'b1;
        default: ;
      endcase
      2'd3: case (addr_bucket_i)
        2'd0: hit_cx_txn_addr_illegal_rd_low = 1'b1;
        2'd1: hit_cx_txn_addr_illegal_rd_mid = 1'b1;
        2'd2: hit_cx_txn_addr_illegal_rd_high = 1'b1;
        default: ;
      endcase
      default: ;
    endcase

    // cx_txn_len (effective len bins: single/short/burst)
    case (txn_kind_i)
      2'd0: case (len_bucket_i)
        2'd1: hit_cx_txn_len_legal_wr_single = 1'b1;
        2'd2: hit_cx_txn_len_legal_wr_short = 1'b1;
        2'd3: hit_cx_txn_len_legal_wr_burst = 1'b1;
        default: ;
      endcase
      2'd1: case (len_bucket_i)
        2'd1: hit_cx_txn_len_legal_rd_single = 1'b1;
        2'd2: hit_cx_txn_len_legal_rd_short = 1'b1;
        2'd3: hit_cx_txn_len_legal_rd_burst = 1'b1;
        default: ;
      endcase
      2'd2: case (len_bucket_i)
        2'd1: hit_cx_txn_len_illegal_wr_single = 1'b1;
        2'd2: hit_cx_txn_len_illegal_wr_short = 1'b1;
        2'd3: hit_cx_txn_len_illegal_wr_burst = 1'b1;
        default: ;
      endcase
      2'd3: case (len_bucket_i)
        2'd1: hit_cx_txn_len_illegal_rd_single = 1'b1;
        2'd2: hit_cx_txn_len_illegal_rd_short = 1'b1;
        2'd3: hit_cx_txn_len_illegal_rd_burst = 1'b1;
        default: ;
      endcase
      default: ;
    endcase

    // cx_legal_rd_cmp effective bins after ignore rules:
    // legal_wr.na, legal_rd.na, legal_rd.all_match, illegal_wr.na, illegal_rd.na
    case (txn_kind_i)
      2'd0: if (rd_cmp_i == 2'd0) hit_cx_legal_rd_cmp_legal_wr_na = 1'b1;
      2'd1: begin
        if (rd_cmp_i == 2'd0) hit_cx_legal_rd_cmp_legal_rd_na = 1'b1;
        if (rd_cmp_i == 2'd1) hit_cx_legal_rd_cmp_legal_rd_all_match = 1'b1;
      end
      2'd2: if (rd_cmp_i == 2'd0) hit_cx_legal_rd_cmp_illegal_wr_na = 1'b1;
      2'd3: if (rd_cmp_i == 2'd0) hit_cx_legal_rd_cmp_illegal_rd_na = 1'b1;
      default: ;
    endcase

    if (is_read_i && !legal_i)
      hit_illegal_read = 1'b1;

    if (read_compared_i) begin
      read_cmp_cnt++;
      if (rd_cmp_i == 2'd2) begin
        read_mismatch_txn_cnt++;
      end else if (rd_cmp_i == 2'd1) begin
        hit_rd_cmp_match = 1'b1;
      end
    end

    cg_i2c_func.sample(txn_kind_i, addr_bucket_i, len_bucket_i, ack_kind_i, rd_cmp_i);
  endfunction

  function void report();
    func_cov_pct = cg_i2c_func.get_inst_coverage();
    if (txn_cnt == 0)
      `uvm_error("SCB_FCOV", "no transactions reached scoreboard, functional coverage is invalid")
    `uvm_info("SCB_FCOV", $sformatf("functional_coverage=%0.2f%% samples=%0d", func_cov_pct, txn_cnt), UVM_LOW)
    `uvm_info("SCB_FCOV", $sformatf("read_compare_txn=%0d read_mismatch_txn=%0d", read_cmp_cnt, read_mismatch_txn_cnt), UVM_LOW)
    `uvm_info("SCB_BUCKET", $sformatf("addr_low=%0d addr_mid=%0d addr_high=%0d len_single=%0d len_short=%0d len_burst=%0d illegal_read=%0d", hit_addr_low, hit_addr_mid, hit_addr_high, hit_len_single, hit_len_short, hit_len_burst, hit_illegal_read), UVM_LOW)
    `uvm_info("SCB_BUCKET2", $sformatf("legal_wr=%0d legal_rd=%0d illegal_wr=%0d illegal_rd=%0d ack_all=%0d ack_nack=%0d rd_match=%0d", hit_legal_wr, hit_legal_rd, hit_illegal_wr, hit_illegal_rd, hit_ack_all, hit_ack_nack, hit_rd_cmp_match), UVM_LOW)
    `uvm_info("SCB_COVPT", $sformatf("cp_txn_legal_wr=%0d cp_txn_legal_rd=%0d cp_txn_illegal_wr=%0d cp_txn_illegal_rd=%0d cp_addr_low=%0d cp_addr_mid=%0d cp_addr_high=%0d cp_len_single=%0d cp_len_short=%0d cp_len_burst=%0d cp_ack_all_ack=%0d cp_ack_has_nack=%0d cp_rd_na=%0d cp_rd_all_match=%0d cx_txn_addr_legal_wr_low=%0d cx_txn_addr_legal_wr_mid=%0d cx_txn_addr_legal_wr_high=%0d cx_txn_addr_legal_rd_low=%0d cx_txn_addr_legal_rd_mid=%0d cx_txn_addr_legal_rd_high=%0d cx_txn_addr_illegal_wr_low=%0d cx_txn_addr_illegal_wr_mid=%0d cx_txn_addr_illegal_wr_high=%0d cx_txn_addr_illegal_rd_low=%0d cx_txn_addr_illegal_rd_mid=%0d cx_txn_addr_illegal_rd_high=%0d cx_txn_len_legal_wr_single=%0d cx_txn_len_legal_wr_short=%0d cx_txn_len_legal_wr_burst=%0d cx_txn_len_legal_rd_single=%0d cx_txn_len_legal_rd_short=%0d cx_txn_len_legal_rd_burst=%0d cx_txn_len_illegal_wr_single=%0d cx_txn_len_illegal_wr_short=%0d cx_txn_len_illegal_wr_burst=%0d cx_txn_len_illegal_rd_single=%0d cx_txn_len_illegal_rd_short=%0d cx_txn_len_illegal_rd_burst=%0d cx_legal_rd_cmp_legal_wr_na=%0d cx_legal_rd_cmp_legal_rd_na=%0d cx_legal_rd_cmp_legal_rd_all_match=%0d cx_legal_rd_cmp_illegal_wr_na=%0d cx_legal_rd_cmp_illegal_rd_na=%0d",
      hit_cp_txn_legal_wr, hit_cp_txn_legal_rd, hit_cp_txn_illegal_wr, hit_cp_txn_illegal_rd,
      hit_cp_addr_low, hit_cp_addr_mid, hit_cp_addr_high,
      hit_cp_len_single, hit_cp_len_short, hit_cp_len_burst,
      hit_cp_ack_all_ack, hit_cp_ack_has_nack,
      hit_cp_rd_na, hit_cp_rd_all_match,
      hit_cx_txn_addr_legal_wr_low, hit_cx_txn_addr_legal_wr_mid, hit_cx_txn_addr_legal_wr_high,
      hit_cx_txn_addr_legal_rd_low, hit_cx_txn_addr_legal_rd_mid, hit_cx_txn_addr_legal_rd_high,
      hit_cx_txn_addr_illegal_wr_low, hit_cx_txn_addr_illegal_wr_mid, hit_cx_txn_addr_illegal_wr_high,
      hit_cx_txn_addr_illegal_rd_low, hit_cx_txn_addr_illegal_rd_mid, hit_cx_txn_addr_illegal_rd_high,
      hit_cx_txn_len_legal_wr_single, hit_cx_txn_len_legal_wr_short, hit_cx_txn_len_legal_wr_burst,
      hit_cx_txn_len_legal_rd_single, hit_cx_txn_len_legal_rd_short, hit_cx_txn_len_legal_rd_burst,
      hit_cx_txn_len_illegal_wr_single, hit_cx_txn_len_illegal_wr_short, hit_cx_txn_len_illegal_wr_burst,
      hit_cx_txn_len_illegal_rd_single, hit_cx_txn_len_illegal_rd_short, hit_cx_txn_len_illegal_rd_burst,
      hit_cx_legal_rd_cmp_legal_wr_na, hit_cx_legal_rd_cmp_legal_rd_na, hit_cx_legal_rd_cmp_legal_rd_all_match,
      hit_cx_legal_rd_cmp_illegal_wr_na, hit_cx_legal_rd_cmp_illegal_rd_na), UVM_LOW)
  endfunction
endclass
