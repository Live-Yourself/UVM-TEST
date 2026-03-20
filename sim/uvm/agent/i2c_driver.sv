class i2c_driver extends uvm_driver#(i2c_item);
  `uvm_component_utils(i2c_driver)

  virtual i2c_if vif;
  i2c_cfg cfg;
  uvm_analysis_port#(i2c_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not set")
    if (!uvm_config_db#(i2c_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = i2c_cfg::type_id::create("cfg");
      `uvm_warning("NOCFG", "cfg not set, use default")
    end
  endfunction

  task scl_high();
    vif.scl = 1'b1;
    #(cfg.t_high);
  endtask

  task scl_low();
    vif.scl = 1'b0;
    #(cfg.t_low + cfg.scl_low_extra);
  endtask

  task start_cond();
    vif.sda_drv_low = 1'b0;
    scl_high();
    vif.sda_drv_low = 1'b1;
    #(cfg.t_low/2);
    scl_low();
  endtask

  task stop_cond();
    scl_low();
    vif.sda_drv_low = 1'b1;
    #(cfg.t_low/4);
    scl_high();
    vif.sda_drv_low = 1'b0;
    #(cfg.t_high/4);
  endtask

  task write_bit(bit b);
    scl_low();
    vif.sda_drv_low = ~b;
    #(cfg.t_low/4);
    scl_high();
    scl_low();
  endtask

  task read_bit(output bit b);
    scl_low();
    vif.sda_drv_low = 1'b0;
    #(cfg.t_low/4);
    scl_high();
    b = vif.sda_in;
    scl_low();
  endtask

  task write_byte(input byte unsigned data, output bit ack);
    int i;
    for (i = 7; i >= 0; i--) begin
      write_bit(data[i]);
    end
    read_bit(ack);
    ack = ~ack;
  endtask

  task read_byte(output byte unsigned data, input bit nack_last);
    int i;
    bit b;
    data = 8'h00;
    for (i = 7; i >= 0; i--) begin
      read_bit(b);
      data[i] = b;
    end
    write_bit(nack_last);
  endtask

  task do_write(i2c_item tr);
    bit ack;
    int i;

    start_cond();
    write_byte({tr.dev_addr, 1'b0}, ack);
    tr.ack_bits.push_back(ack);
    write_byte(tr.reg_addr, ack);
    tr.ack_bits.push_back(ack);
    for (i = 0; i < tr.wdata.size(); i++) begin
      write_byte(tr.wdata[i], ack);
      tr.ack_bits.push_back(ack);
    end
    stop_cond();
  endtask

  task do_read(i2c_item tr);
    bit ack;
    byte unsigned d;
    int i;
    int unsigned n;

    n = (tr.rd_len == 0) ? 1 : tr.rd_len;
    tr.rdata = new[n];

    start_cond();
    write_byte({tr.dev_addr, 1'b0}, ack);
    tr.ack_bits.push_back(ack);
    write_byte(tr.reg_addr, ack);
    tr.ack_bits.push_back(ack);

    start_cond();
    write_byte({tr.dev_addr, 1'b1}, ack);
    tr.ack_bits.push_back(ack);
    for (i = 0; i < n; i++) begin
      read_byte(d, (i == n - 1));
      tr.rdata[i] = d;
    end
    stop_cond();
  endtask

  task run_phase(uvm_phase phase);
    i2c_item tr;
    vif.init_bus();

    forever begin
      seq_item_port.get_next_item(tr);
      `uvm_info("DRV", $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)
      case (tr.op)
        I2C_WRITE: do_write(tr);
        I2C_READ : do_read(tr);
      endcase
      ap.write(tr);
      seq_item_port.item_done();
    end
  endtask
endclass
