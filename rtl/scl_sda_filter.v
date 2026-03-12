// Simple 2-flop synchronizer for SCL/SDA
// Optional glitch filter can be added later

module scl_sda_filter (
    input  wire clk,
    input  wire rst_n,
    input  wire scl_in,
    input  wire sda_in,
    output wire scl_sync,
    output wire sda_sync
);
    reg [1:0] scl_ff;
    reg [1:0] sda_ff;

    always @(negedge rst_n or posedge clk) begin
        if (!rst_n) begin
            scl_ff <= 2'b11;
            sda_ff <= 2'b11;
        end else begin
            scl_ff <= {scl_ff[0], scl_in};
            sda_ff <= {sda_ff[0], sda_in};
        end
    end

    assign scl_sync = scl_ff[1];
    assign sda_sync = sda_ff[1];
endmodule
