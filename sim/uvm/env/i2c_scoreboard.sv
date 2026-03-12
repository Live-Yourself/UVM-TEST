class i2c_scoreboard extends uvm_component;
  `uvm_component_utils(i2c_scoreboard)

  uvm_analysis_imp#(i2c_item, i2c_scoreboard) imp;
  byte unsigned model_mem [byte unsigned];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  function void write(i2c_item tr);
    int i;
    byte unsigned exp;
    int unsigned n;

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
endclass
