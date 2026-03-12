# IO constraints for i2c_slave_top
# Adjust delays to your board/system timing

# Input delays relative to clk
set_input_delay -clock clk 1.0 [get_ports scl]
set_input_delay -clock clk 1.0 [get_ports sda_in]

# Asynchronous reset: remove timing from rst_n
set_false_path -from [get_ports rst_n]

# Output delay for sda_oe
set_output_delay -clock clk 1.0 [get_ports sda_oe]

# Default drive/load
set_drive 0 [get_ports {scl sda_in rst_n}]
set_load 0.1 [get_ports sda_oe]
