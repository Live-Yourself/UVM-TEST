`timescale 1ns/1ps
// Unit test for i2c_rx_fsm output drive behavior.

module tc_i2c_rx_fsm;
    reg        clk;
    reg        rst_n;
    reg        start_cond;
    reg        stop_cond;
    reg        scl_sync;
    reg        scl_rise;
    reg        scl_fall;
    reg        sda_sync;
    reg [7:0]  rx_byte;
    reg [7:0]  reg_rdata;
    reg [6:0]  dev_addr;

    wire       rx_shift_en;
    wire       tx_shift_en;
    wire       tx_load_en;
    wire [7:0] tx_load_data;
    wire       ack_drive;
    wire       tx_drive_en;
    wire       reg_we;
    wire [7:0] reg_waddr;
    wire [7:0] reg_wdata;
    wire [7:0] reg_addr;

    i2c_rx_fsm dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_cond  (start_cond),
        .stop_cond   (stop_cond),
        .scl_sync    (scl_sync),
        .scl_rise    (scl_rise),
        .scl_fall    (scl_fall),
        .sda_sync    (sda_sync),
        .rx_byte     (rx_byte),
        .reg_rdata   (reg_rdata),
        .dev_addr    (dev_addr),
        .rx_shift_en (rx_shift_en),
        .tx_shift_en (tx_shift_en),
        .tx_load_en  (tx_load_en),
        .tx_load_data(tx_load_data),
        .ack_drive   (ack_drive),
        .tx_drive_en (tx_drive_en),
        .reg_we      (reg_we),
        .reg_waddr   (reg_waddr),
        .reg_wdata   (reg_wdata),
        .reg_addr    (reg_addr)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        start_cond = 1'b0;
        stop_cond = 1'b0;
        scl_sync = 1'b0;
        scl_rise = 1'b0;
        scl_fall = 1'b0;
        sda_sync = 1'b1;
        rx_byte = 8'h00;
        reg_rdata = 8'h00;
        dev_addr = 7'h42;

        #20;
        rst_n = 1'b1;
        @(posedge clk);

        force dut.state = 4'd8;  // ST_READ_ACK
        scl_sync = 1'b1;
        #1;
        if (tx_drive_en !== 1'b0) begin
            $fatal(1, "slave drives SDA during read ACK/NACK bit");
        end

        release dut.state;
        $display("PASS");
        $finish;
    end
endmodule
