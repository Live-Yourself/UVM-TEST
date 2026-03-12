// Simple 256x8 register file for I2C slave
// - Synchronous write
// - Asynchronous read

module reg_file (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [7:0]  wdata,
    input  wire [7:0]  raddr,
    output wire [7:0]  rdata
);
    reg [7:0] mem [0:255];
    integer i;

    always @(negedge rst_n or posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 256; i = i + 1) begin
                mem[i] <= 8'h00;
            end
//	    rdata <= 8'h00;
        end else if (we) begin
//            mem[waddr] <= wdata;
//            rdata <= mem[raddr];
//        end else begin
//            rdata <= mem[raddr];
	    mem[waddr] <= wdata;
        end
    end

    assign rdata = mem[raddr];
endmodule
