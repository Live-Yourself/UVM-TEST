`timescale 1ns/1ps
// Top-level I2C slave system testbench
// - Covers basic write, read with repeated start
// - Uses simple I2C master bit-banging

module tb_i2c_slave;
    reg  clk;
    reg  rst_n;
    reg  scl;
    reg  sda_drv;    // 0: drive low, 1: release
    wire sda;        // open-drain bus
    wire sda_oe;
    reg  ack;
    reg  [7:0] rdata;


    // Pull-up for open-drain SDA
    pullup (sda);

    // DUT
    i2c_slave_top #(
        .DEV_ADDR(7'h42)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .scl   (scl),
        .sda_in(sda),
        .sda_oe(sda_oe)
    );

    // Open-drain wiring (master + slave)
    assign sda = (sda_drv == 1'b0 || sda_oe) ? 1'b0 : 1'bz;

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // I2C timing parameters
    localparam T_HIGH = 200;
    localparam T_LOW  = 200;

    task i2c_scl_high;
        begin
            scl = 1'b1;
            #(T_HIGH);
        end
    endtask

    task i2c_scl_low;
        begin
            scl = 1'b0;
            #(T_LOW);
        end
    endtask

    task i2c_start;
        begin
            sda_drv = 1'b1;
            i2c_scl_high();
            sda_drv = 1'b0;
            #(T_LOW/2);
            i2c_scl_low();
            $display("[%0t] TB: i2c_start()", $time);
        end
    endtask

    task i2c_stop;
        begin
            i2c_scl_low();
            sda_drv = 1'b0;
            #(T_LOW/4);
            i2c_scl_high();
            sda_drv = 1'b1;
            #(T_LOW/4);
            $display("[%0t] TB: i2c_stop()", $time);
        end
    endtask

    task i2c_write_bit(input b);
        begin
	    i2c_scl_low();
            sda_drv = b ? 1'b1 : 1'b0;
	    #(T_LOW/4);
            i2c_scl_high();
            i2c_scl_low();
        end
    endtask

    task i2c_read_bit(output bit_val);
        begin
	    i2c_scl_low();
            sda_drv = 1'b1; // release
	    #(T_LOW/4);
            i2c_scl_high();
            bit_val = sda;
            i2c_scl_low();
        end
    endtask

    task i2c_write_byte(input [7:0] data, output ack);
        integer i;
        reg ack_bit;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                i2c_write_bit(data[i]);
            end
            i2c_read_bit(ack_bit);
            ack = ~ack_bit; // ACK is low
        end
    endtask

    task i2c_read_byte(output [7:0] data, input ack);
        integer i;
        reg bit_val;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                i2c_read_bit(bit_val);
                data[i] = bit_val;
            end
            i2c_write_bit(~ack); // drive ACK=0, NACK=1
        end
    endtask

    initial begin
        // Init
        scl = 1'b1;
        sda_drv = 1'b1;
        rst_n = 1'b0;
        #(100);
        rst_n = 1'b1;
        #(200);

        // Write: START + addr(W) + reg + data + STOP
        i2c_start();
        i2c_write_byte({7'h42, 1'b0}, ack);
        i2c_write_byte(8'h11, ack);
        i2c_write_byte(8'hA5, ack);
        i2c_write_byte(8'hB4, ack);
        i2c_stop();

        #(1000);

        // Read: START + addr(W) + reg + RESTART + addr(R) + data + NACK + STOP
        i2c_start();
        i2c_write_byte({7'h42, 1'b0}, ack);
        i2c_write_byte(8'h11, ack);
        i2c_start();
        i2c_write_byte({7'h42, 1'b1}, ack);
        i2c_read_byte(rdata, 1'b1);
        i2c_read_byte(rdata, 1'b0);
        i2c_stop();

        #(2000);
        $finish;
    end


`ifdef DUMP_FSDB
	initial begin
		$fsdbDumpfile("tb_i2c_slave.fsdb");
		$fsdbDumpvars(0,tb_i2c_slave);
	end
`endif

endmodule
