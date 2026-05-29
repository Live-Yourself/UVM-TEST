#********************************************************************
#   RTL to GDSII Script Database
#    Copyright(c) 2018-2019 Nephotonics.inc, All rights reserved
#********************************************************************
#   FileName  compileOpt.tcl
#   Description: 
#       Set compile Option
#   Version
#       V-2014.08
#   Revision:
#       Date          Mod.By           Change made
#       ===================================================
#       March. 14,2020   NEO Lin       Initial version
#********************************************************************



#         VERILOG RULES: VERILOG OUT                   
# ------------------------------------------------------------

set verilogout_show_unconnected_pins "true"
set verilogout_no_tri "true"
set verilogout_single_bit "false"


#                    Compile Options                     
# ------------------------------------------------------------

#/* we want to force it to use MUXes */
# ------------------------------------------------------------

#set hdlin_dont_infer_mux_for_resource_sharing "false"
set  hdlin_infer_mux true

#               MISCELLANIOUS STUFF                     
# ------------------------------------------------------------

set compile_no_new_cells_at_top_level false
set compile_instance_name_prefix "u"
set gen_max_ports_on_symbol_side 0
set bus_naming_style {%s[%d]}

#when use negedge,add inverter on clock and use posedge dff
# ------------------------------------------------------------

set compile_automatic_clock_phase_inference none

current_design $topDesign

#
uniquify

set compile_seqmap_propagate_constants true
#set_boundary_optimization [find design "*"]

set_fix_multiple_port_nets -all -feedthroughs -outputs -buffer_constants 

#set_flatten true -effort medium -minimize single_output -design [find design "*"]
set_structure true -timing true -design [find design "*"]

check_design
set_max_area 0