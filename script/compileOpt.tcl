# Compile options for i2c_slave_top

set verilogout_show_unconnected_pins "true"
set verilogout_no_tri "true"
set verilogout_single_bit "false"

# Allow mux inference (FSM/control needs muxes)
set hdlin_infer_mux true

# Misc
set compile_no_new_cells_at_top_level false
set compile_instance_name_prefix "u"
set gen_max_ports_on_symbol_side 0
set bus_naming_style {%s[%d]}

# Do not auto-infer clock phase
set compile_automatic_clock_phase_inference none

current_design $topDesign

uniquify

set compile_seqmap_propagate_constants true

set_fix_multiple_port_nets -all -feedthroughs -outputs -buffer_constants

set_structure true -timing true -design [find design "*"]

check_design

# No explicit area limit
set_max_area 0
