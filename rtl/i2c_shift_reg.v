// 8-bit shift register for I2C RX/TX
// - MSB-first shifting
// - Load for TX data

module i2c_shift_reg (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       shift_en,
    input  wire       shift_in,
    input  wire       load_en,
    input  wire [7:0] load_data,
    output wire       shift_out,
    output wire [7:0] data_out
);
    reg [7:0] shreg;

    always @(negedge rst_n or posedge clk) begin
        if (!rst_n) begin
            shreg <= 8'h00;
        end else if (load_en) begin
            shreg <= load_data;
        end else if (shift_en) begin
            shreg <= {shreg[6:0], shift_in};
        end
    end

    assign shift_out = shreg[7];
    assign data_out  = shreg;
endmodule
