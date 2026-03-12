// Top-level I2C slave with register file
// - Open-drain SDA output control
// - Uses FSM + shift register + reg file

module i2c_slave_top #(
    parameter [6:0] DEV_ADDR = 7'h42
) (
    input  wire clk,
    input  wire rst_n,
    input  wire scl,
    input  wire sda_in,
    output wire sda_oe
);
    wire scl_sync;
    wire sda_sync;

    reg  scl_d;
    reg  sda_d;
    wire scl_rise;
    wire scl_fall;
    wire start_cond;
    wire stop_cond;

    wire        rx_shift_en;
    wire        tx_shift_en;
    wire        tx_load_en;
    wire [7:0]  tx_load_data;
    wire        ack_drive;
    wire        tx_drive_en;
    wire        reg_we;
    wire [7:0]  reg_waddr;
    wire [7:0]  reg_wdata;
    wire [7:0]  reg_addr;

    wire [7:0]  reg_addr_w;
    wire [7:0]  reg_addr_r;

    wire [7:0]  reg_rdata;
    wire [7:0]  shift_data;
    wire        shift_out;

    scl_sda_filter u_filter (
        .clk      (clk),
        .rst_n    (rst_n),
        .scl_in   (scl),
        .sda_in   (sda_in),
        .scl_sync (scl_sync),
        .sda_sync (sda_sync)
    );

    always @(negedge rst_n or posedge clk) begin
        if (!rst_n) begin
            scl_d <= 1'b1;
            sda_d <= 1'b1;
        end else begin
            scl_d <= scl_sync;
            sda_d <= sda_sync;
        end
    end

    assign scl_rise   =  scl_sync & ~scl_d;
    assign scl_fall   = ~scl_sync &  scl_d;
    assign start_cond = (sda_d == 1'b1) && (sda_sync == 1'b0) && (scl_sync == 1'b1) && (scl_d == 1'b1);
    assign stop_cond  = (sda_d == 1'b0) && (sda_sync == 1'b1) && (scl_sync == 1'b1) && (scl_d == 1'b1);

    i2c_rx_fsm u_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_cond  (start_cond),
        .stop_cond   (stop_cond),
        .scl_sync    (scl_sync),
        .scl_rise    (scl_rise),
        .scl_fall    (scl_fall),
        .sda_sync    (sda_sync),
        .rx_byte     (shift_data),
        .reg_rdata   (reg_rdata),
        .dev_addr    (DEV_ADDR),
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

    i2c_shift_reg u_shreg (
        .clk       (clk),
        .rst_n     (rst_n),
        .shift_en  (rx_shift_en | tx_shift_en),
        .shift_in  (rx_shift_en ? sda_sync : 1'b1),
        .load_en   (tx_load_en),
        .load_data (tx_load_data),
        .shift_out (shift_out),
        .data_out  (shift_data)
    );

    assign reg_addr_w = reg_waddr;
    assign reg_addr_r = reg_addr;

    reg_file u_regfile (
        .clk   (clk),
        .rst_n (rst_n),
        .we    (reg_we),
        .waddr (reg_addr_w),
        .wdata (reg_wdata),
        .raddr (reg_addr_r),
        .rdata (reg_rdata)
    );

    // Open-drain: drive low only
    assign sda_oe = ack_drive | (tx_drive_en & ~shift_out);
endmodule
