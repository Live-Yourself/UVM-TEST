#********************************************************************
#   RTL to GDSII Script Database
#   Copyright(c) 2018-2019 Nephotonics.inc, All rights reserved
#********************************************************************
#   FileName  rpt.tcl
#   Description: 
#       Report design
#   Version
#       V-2014.08
#   Revision:
#       Date          Mod.By           Change made
#       ===================================================
#       June. 10,2019   David Zhao       Initial version
#********************************************************************



#####################################################
# do some report
#####################################################

set summary_dir   "$rptPath/summary"
set analysis_dir  "$rptPath/analysis"
set debug_dir     "$rptPath/debug"
set config_dir    "$rptPath/config"

file mkdir $summary_dir
file mkdir $analysis_dir
file mkdir $debug_dir
file mkdir $config_dir

# Summary_dir
check_design -multiple_designs   > $summary_dir/check_design_${view_name}.rpt

check_timing                     > $summary_dir/check_timing_${view_name}.rpt

report_qor                       > $summary_dir/qor_${view_name}.rpt

report_constraint -all_violators -nosplit \
								 -max_delay \
								 -multiport_net \
								 -max_fanout \
								 -max_capacitance \
                                 > $summary_dir/constraint_${view_name}.rpt

report_timing \
     -attribute \
     -capacitance \
     -delay min \
     -enable_preset_clear_arcs \
     -input_pins \
     -slack_lesser_than 0 \
     -max_paths 5 \
     -nets \
     -nworst 2\
     -path full_clock \
     -transition > $summary_dir/timing_violate_${view_name}.rpt 

# analysis_dir
report_timing -delay max -max_paths 100 -nosplit -path full_clock_expanded -nets -transition_time -input_pins \
                                 > $analysis_dir/timing_max_${view_name}.rpt

report_timing -delay min -max_paths 100 -nosplit -path full_clock_expanded -nets -transition_time -input_pins \
                                 > $analysis_dir/timing_min_${view_name}.rpt

report_area -hierarchy -physical -designware > $analysis_dir/area_${view_name}.rpt

report_power -nosplit            > $analysis_dir/power_${view_name}.rpt

report_constraint -all_violators -verbose \
								 -max_delay \
								 -multiport_net \
								 -max_fanout \
								 -max_capacitance \
                                 > $analysis_dir/constraint_${view_name}.rpt

set_zero_interconnect_delay_mode true
report_timing -delay max -path full_clock_expanded -max_paths 10 -nets -transition_time -input_pins -nosplit \
                                 > $analysis_dir/zero_interconnect_timing_${view_name}.rpt

report_qor                       > $analysis_dir/zero_interconnect_qor_${view_name}.rpt
set_zero_interconnect_delay_mode false

# dubug_dir
report_net_fanout -threshold 32 > $debug_dir/high_fanout_nets_${view_name}.rpt

report_clock_gating -multi_stage -verbose -gated -ungated \
                                 > $debug_dir/clock_gating_${view_name}.rpt

query_objects -truncate 0 [all_registers -level_sensitive ] \
                                 > $debug_dir/latches_${view_name}.rpt

report_clock_tree -summary -settings -structure \
                                 > $debug_dir/clock_tree_${view_name}.rpt

report_port -verbose -nosplit    > $debug_dir/port_${view_name}.rpt

report_hierarchy                 > $debug_dir/hierarchy_${view_name}.rpt

report_resources -hierarchy      > $debug_dir/resources_${view_name}.rpt

# config_dir
report_design                    > $config_dir/design_${view_name}.rpt

report_clocks -attributes -skew  > $config_dir/clocks_${view_name}.rpt

report_compile_options           > $config_dir/compile_options_${view_name}.rpt

report_isolate_ports -nosplit    > $config_dir/isolate_ports_${view_name}.rpt

# Write Verilog

current_design $topDesign

change_name -rule verilog -h 
define_name_rule gcore -restrict "\\\[\]"
define_name_rule gcore -remove_internal_net_bus
report_name_rule gcore
change_name -rule gcore  -h 

sh sync

write -f ddc -h -output ../db/changename_${view_name}.ddc

write     -f verilog -h -output ../netlist/${topDesign}_syn.vg

write_sdc -nosplit -version 1.9 ../netlist/${topDesign}.sdc

write -h -f ddc -o ../db/${topDesign}_${view_name}.ddc

set_svf -off
