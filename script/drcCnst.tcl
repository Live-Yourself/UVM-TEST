# Basic DRC constraints

set_max_fanout 10 [current_design]
set_max_transition 0.5 [current_design]
set_max_capacitance 0.2 [current_design]

# Buffer tree constraints for high-fanout drivers
# Apply fanout limit to reg_addr flop drivers
set reg_addr_drv_pins [get_pins -hier {u_fsm/reg_addr_reg_*/Q}]
if {[sizeof_collection $reg_addr_drv_pins] > 0} {
	set_max_fanout 8 $reg_addr_drv_pins
}

# Regfile internal decode drivers (apply modest fanout limit to encourage buffering)
set regfile_drv_pins [get_pins -hier {u_regfile/*/Y}]
if {[sizeof_collection $regfile_drv_pins] > 0} {
	set_max_fanout 12 $regfile_drv_pins
}
