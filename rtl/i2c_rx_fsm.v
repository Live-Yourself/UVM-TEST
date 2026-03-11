// I2C slave receive/transmit FSM
// - Handles address, register pointer, write and read transactions
// - Generates ACK and TX control

module i2c_rx_fsm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start_cond,
    input  wire       stop_cond,
    input  wire       scl_sync,
    input  wire       scl_rise,
    input  wire       scl_fall,
    input  wire       sda_sync,
    input  wire [7:0] rx_byte,
    input  wire [7:0] reg_rdata,
    input  wire [6:0] dev_addr,

    output reg        rx_shift_en,
    output reg        tx_shift_en,
    output reg        tx_load_en,
    output reg [7:0]  tx_load_data,

    output reg        ack_drive,
    output reg        tx_drive_en,

    output reg        reg_we,
    output reg [7:0]  reg_waddr,
    output reg [7:0]  reg_wdata,
    output reg [7:0]  reg_addr
);
    localparam ST_IDLE      = 4'd0;
    localparam ST_ADDR      = 4'd1;
    localparam ST_ADDR_ACK  = 4'd2;
    localparam ST_REG       = 4'd3;
    localparam ST_REG_ACK   = 4'd4;
    localparam ST_WRITE     = 4'd5;
    localparam ST_WRITE_ACK = 4'd6;
    localparam ST_READ      = 4'd7;
    localparam ST_READ_ACK  = 4'd8;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg       rw_dir;      // 0: write, 1: read
    reg       addr_match;

    reg	[1:0] write_cnt;
    reg       ack_drive_r;
    wire      data_phase;

    wire [7:0] addr_byte;
    wire [7:0] rx_byte_new;

    assign addr_byte = {rx_byte[6:0], sda_sync};
    assign rx_byte_new = {rx_byte[6:0], sda_sync};
    assign data_phase = (state == ST_ADDR) | (state == ST_REG) | (state == ST_WRITE);

    always @(negedge rst_n or posedge clk) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            bit_cnt      <= 3'd0;
            rw_dir       <= 1'b0;
            addr_match   <= 1'b0;
            reg_addr     <= 8'h00;
            reg_we       <= 1'b0;
	    reg_waddr    <= 8'h00;
            reg_wdata    <= 8'h00;
            tx_load_data <= 8'h00;

            ack_drive_r  <= 1'b0;
        end else begin
            reg_we <= 1'b0;

            if (stop_cond) begin
                ack_drive_r <= 1'b0;
            end else if (start_cond) begin
                ack_drive_r <= 1'b0;
            end else if (scl_fall) begin
                case (state)
                    ST_ADDR_ACK:  ack_drive_r <= addr_match;
                    ST_REG_ACK:   ack_drive_r <= 1'b1;
                    ST_WRITE_ACK: ack_drive_r <= 1'b1;
                    default:      ack_drive_r <= 1'b0;
                endcase
            end

            if (stop_cond) begin
                state <= ST_IDLE;
            end else if (start_cond) begin
                state   <= ST_ADDR;
                bit_cnt <= 3'd0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        if (start_cond) begin
                            state   <= ST_ADDR;
                            bit_cnt <= 3'd0;
                        end
                    end

                    ST_ADDR: begin
                        if (scl_rise) begin
                            bit_cnt <= bit_cnt + 3'd1;
                            if (bit_cnt == 3'd7) begin
                                addr_match <= (addr_byte[7:1] == dev_addr);
                                rw_dir     <= addr_byte[0];
                                state      <= ST_ADDR_ACK;
                                bit_cnt    <= 3'd0;
                            end
                        end
                    end

                    ST_ADDR_ACK: begin
                        if (scl_rise) begin
                            if (addr_match) begin
                                if (rw_dir) begin
                                    state        <= ST_READ;
                                    bit_cnt      <= 3'd0;
                                    tx_load_data <= reg_rdata;
                                end else begin
                                    state   <= ST_REG;
                                    bit_cnt <= 3'd0;
                                end
                            end else begin
                                state <= ST_IDLE;
                            end
                        end
                    end

                    ST_REG: begin
                        if (scl_rise) begin
                            bit_cnt <= bit_cnt + 3'd1;
                            if (bit_cnt == 3'd7) begin
                               reg_addr <= rx_byte_new;
                               state    <= ST_REG_ACK;
                               bit_cnt    <= 3'd0;
                            end
                        end
                    end

                    ST_REG_ACK: begin
                        if (scl_rise) begin
                            state   <= ST_WRITE;
                            bit_cnt <= 3'd0;
                        end
                    end

                    ST_WRITE: begin
                        if (scl_rise) begin
                            bit_cnt <= bit_cnt + 3'd1;
                            if (bit_cnt == 3'd7) begin
				reg_waddr <= reg_addr;
                                reg_wdata <= rx_byte_new;
                                reg_we    <= 1'b1;
                                state     <= ST_WRITE_ACK;
                                bit_cnt    <= 3'd0;
			    end
                        end
                    end

                    ST_WRITE_ACK: begin
                        if (scl_rise) begin
                            reg_addr  <= reg_addr + 8'd1;
                            state   <= ST_WRITE;
                            bit_cnt <= 3'd0;
                        end
                    end

                    ST_READ: begin
                        if (scl_rise) begin
                            bit_cnt <= bit_cnt + 3'd1;
                            if (bit_cnt == 3'd7) begin
                                reg_addr <= reg_addr + 8'd1;
                                state <= ST_READ_ACK;
                            end
                        end
                    end

                    ST_READ_ACK: begin
                        if (scl_rise) begin
                            if (sda_sync == 1'b1) begin
                                state <= ST_IDLE;
                            end else begin
                                tx_load_data <= reg_rdata;
                                state        <= ST_READ;
                                bit_cnt      <= 3'd0;
                            end
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

    always @(*) begin
        rx_shift_en = 1'b0;
        tx_shift_en = 1'b0;
        tx_load_en  = 1'b0;
        ack_drive   = ack_drive_r;
        tx_drive_en = 1'b0;

        case (state)
            ST_ADDR: begin
                rx_shift_en = scl_rise & data_phase;
            end
            ST_ADDR_ACK: begin
//                ack_drive = addr_match;
            end
            ST_REG: begin
                rx_shift_en = scl_rise & data_phase;
            end
            ST_REG_ACK: begin
//                ack_drive = 1'b1;
            end
            ST_WRITE: begin
                rx_shift_en = scl_rise & data_phase;
            end 
            ST_WRITE_ACK: begin
//                ack_drive = 1'b1;
            end
            ST_READ: begin
                tx_drive_en = 1'b1;
                tx_shift_en = scl_fall;
            end
            ST_READ_ACK: begin
                tx_drive_en = scl_sync;
            end
            default: begin
            end
        endcase

        if (state == ST_READ && bit_cnt==3'd0 && scl_fall) begin
            tx_load_en = 1'b1;
        end
    end
endmodule
