typedef enum {I2C_WRITE, I2C_READ} i2c_op_e;

class i2c_item extends uvm_sequence_item;
  `uvm_object_utils(i2c_item)

  rand i2c_op_e       op;
  rand bit [6:0]      dev_addr;
  rand bit [7:0]      reg_addr;
  rand bit [7:0]      wdata[];
  rand int unsigned   rd_len;
       bit [7:0]      rdata[];
       bit            ack_bits[$];

  constraint c_len {
    if (op == I2C_WRITE) wdata.size() inside {[1:16]};
    if (op == I2C_WRITE) rd_len == 0;
    if (op == I2C_READ)  wdata.size() == 0;
    if (op == I2C_READ)  rd_len inside {[1:16]};
  }

  function new(string name = "i2c_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("op=%s dev=0x%02h reg=0x%02h wlen=%0d rd_len=%0d rlen=%0d",
                     (op == I2C_WRITE) ? "WRITE" : "READ",
                     dev_addr, reg_addr, wdata.size(), rd_len, rdata.size());
  endfunction
endclass
