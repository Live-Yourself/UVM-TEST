class i2c_monitor extends uvm_component;
  `uvm_component_utils(i2c_monitor)

  virtual i2c_if vif;
  uvm_analysis_port#(i2c_item) ap;

  // Monitor-side statistics (bus-observed)
  int unsigned mon_start_cnt;
  int unsigned mon_stop_cnt;
  int unsigned mon_rstart_cnt;
  int unsigned mon_txn_cnt;
  int unsigned mon_write_cnt;
  int unsigned mon_read_cnt;
  int unsigned mon_legal_cnt;
  int unsigned mon_illegal_cnt;

  // For read segment decode: remember register pointer from previous write segment
  bit          pending_reg_valid;
  bit [7:0]    pending_reg_addr;

  // Frame capture context
  bit          in_frame;
  int unsigned bit_pos;       // 0..8, 8 means ACK bit
  byte unsigned cur_byte;
  byte unsigned byte_q[$];
  bit          ack_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not set")
  endfunction

  function void decode_and_publish();
    i2c_item tr;
    int i;
    int n;
    bit [7:0] addr_rw;

    if (byte_q.size() == 0)
      return;

    tr = i2c_item::type_id::create($sformatf("mon_tr_%0d", mon_txn_cnt));

    addr_rw = byte_q[0];
    tr.dev_addr = addr_rw[7:1];

    tr.ack_bits.delete();
    for (i = 0; i < ack_q.size(); i++)
      tr.ack_bits.push_back(ack_q[i]);

    if (addr_rw[0] == 1'b0) begin
      // WRITE segment: [addr+w][reg][data...]
      tr.op = I2C_WRITE;
      mon_write_cnt++;

      if (byte_q.size() >= 2)
        tr.reg_addr = byte_q[1];
      else
        tr.reg_addr = 8'h00;

      if (byte_q.size() > 2) begin
        n = byte_q.size() - 2;
        tr.wdata = new[n];
        for (i = 0; i < n; i++)
          tr.wdata[i] = byte_q[i + 2];
        tr.rd_len = 0;

        // After write data, internal pointer in DUT auto-increments.
        pending_reg_valid = 1'b1;
        pending_reg_addr  = tr.reg_addr + n[7:0];
      end else begin
        // Register pointer write (often followed by repeated START + read)
        tr.wdata = new[0];
        tr.rd_len = 0;
        pending_reg_valid = 1'b1;
        pending_reg_addr  = tr.reg_addr;
      end
    end else begin
      // READ segment: [addr+r][rdata...]
      tr.op = I2C_READ;
      mon_read_cnt++;

      if (pending_reg_valid)
        tr.reg_addr = pending_reg_addr;
      else
        tr.reg_addr = 8'h00;

      if (byte_q.size() > 1) begin
        n = byte_q.size() - 1;
        tr.rdata = new[n];
        for (i = 0; i < n; i++)
          tr.rdata[i] = byte_q[i + 1];
        tr.rd_len = n[7:0];
      end else begin
        tr.rdata = new[0];
        tr.rd_len = 0;
      end

      // One read segment consumes current pending pointer context.
      pending_reg_valid = 1'b0;
    end

    mon_txn_cnt++;
    if (tr.dev_addr == 7'h42)
      mon_legal_cnt++;
    else
      mon_illegal_cnt++;

    ap.write(tr);
    `uvm_info("MON_TR", $sformatf("bus_txn %s", tr.convert2string()), UVM_MEDIUM)
  endfunction

  task run_phase(uvm_phase phase);
    bit sda_prev;
    bit scl_prev;

    in_frame = 1'b0;
    bit_pos = 0;
    cur_byte = 8'h00;
    pending_reg_valid = 1'b0;

    sda_prev = vif.sda;
    scl_prev = vif.scl;

    forever begin
      @(vif.sda or vif.scl);

      // START/Repeated START detection: SDA 1->0 while SCL high
      if (vif.scl === 1'b1) begin
        if (sda_prev === 1'b1 && vif.sda === 1'b0) begin
          mon_start_cnt++;
          if (in_frame) begin
            mon_rstart_cnt++;
            // End previous segment at repeated START boundary.
            decode_and_publish();
          end
          in_frame = 1'b1;
          bit_pos = 0;
          cur_byte = 8'h00;
          byte_q.delete();
          ack_q.delete();
          `uvm_info("MON", "START detected", UVM_HIGH)
        end

        // STOP detection: SDA 0->1 while SCL high
        if (sda_prev === 1'b0 && vif.sda === 1'b1) begin
          mon_stop_cnt++;
          if (in_frame)
            decode_and_publish();
          in_frame = 1'b0;
          bit_pos = 0;
          cur_byte = 8'h00;
          byte_q.delete();
          ack_q.delete();
          `uvm_info("MON", "STOP detected", UVM_HIGH)
        end
      end

      // Data/ACK sampling on SCL rising edge while in-frame
      if (in_frame && (scl_prev === 1'b0) && (vif.scl === 1'b1)) begin
        if (bit_pos < 8) begin
          cur_byte = {cur_byte[6:0], vif.sda};
          bit_pos = bit_pos + 1;
        end else begin
          byte_q.push_back(cur_byte);
          ack_q.push_back(vif.sda === 1'b0);
          cur_byte = 8'h00;
          bit_pos = 0;
        end
      end

      sda_prev = vif.sda;
      scl_prev = vif.scl;
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MON_STAT",
      $sformatf("start=%0d stop=%0d rstart=%0d txn=%0d write=%0d read=%0d legal=%0d illegal=%0d",
        mon_start_cnt, mon_stop_cnt, mon_rstart_cnt, mon_txn_cnt,
        mon_write_cnt, mon_read_cnt, mon_legal_cnt, mon_illegal_cnt),
      UVM_LOW)
  endfunction
endclass
