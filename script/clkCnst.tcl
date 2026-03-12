# Clock constraints for i2c_slave_top
# Assumes current_design is i2c_slave_top

# Main system clock
create_clock -name clk -period 10 [get_ports clk]

# Basic clock quality
set_clock_uncertainty -setup 0.2 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]
set_clock_transition 0.2 [get_clocks clk]

# Prevent optimization from touching the clock network by default
set_dont_touch_network [get_ports clk]
