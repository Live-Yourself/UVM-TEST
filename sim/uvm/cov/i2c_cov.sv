class i2c_cov extends uvm_component;
	`uvm_component_utils(i2c_cov)

	function new(string name, uvm_component parent);
		super.new(name, parent);
		cg_i2c_func = new();
	endfunction

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
      2'd0: hit_addr_low = 1'b1;
      2'd1: hit_addr_mid = 1'b1;
      2'd2: hit_addr_high = 1'b1;
      default: ;
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
  endfunction

endclass
