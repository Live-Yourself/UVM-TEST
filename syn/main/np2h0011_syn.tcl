#********************************************************************
#   RTL to GDSII Script Database
#   Copyright(c) 2018-2019 Nephotonics.inc, All rights reserved
#********************************************************************
#   FileName  pmt3202_top_syn.tcl
#   Description: 
#       main script for PMT3202 syn
#   Version
#       V-2014.09
#   Revision:
#       Date             Mod.By        Change made
#       ===================================================
#       March. 14,2020   NEO Lin       Initial version
#********************************************************************


# define variable for design
#----------------------------------------
set       view_name     20260228
set       topDesign     i2c_slave_top

set       PROJECT       np2h0011
set       NETLIST_DIR    ../netlist
set       COMMON_DIR     ../script
set       rptPath        ../report

set       chkfile       [format "%s%s%s"  "../report/"  $PROJECT "_syn_${view_name}.check"]
set       rptfile       [format "%s%s%s"  "../report/"  $PROJECT "_syn_${view_name}.rpt"]
set       scrfile       [format "%s%s%s"  "../report/"  $PROJECT "_syn_${view_name}.scr"]
set       vgfile        [format "%s%s%s"  "../netlist/" $PROJECT "_syn_${view_name}.vg"]


#/ read in lib & verilog files
#---------------------------------------- 

source    $COMMON_DIR/setupLib.tcl

set_svf ../../fm/svf/syn_${view_name}.svf

suppress_message VER-130
suppress_message VER-936
suppress_message [list UID-401]

set hdlin_auto_save_templates true

sh rm -rf ./work/*

define_design_lib work -path work


analyze -library work -define { SYNTHESIS} -vcs { \
       +incdir+../.. \
       +incdir+../../rtl \
       } -format sverilog $COMMON_DIR/np2h0011_filelist.f

elaborate $topDesign

link



#/ link design
#---------------------------------------- 

current_design $topDesign

#set_operating_conditions -max $STDCELL_LIBNAME_SLOW -min $STDCELL_LIBNAME_FAST

uniquify

check_design > ../report/check_design_${view_name}.rpt 

# write -h -o ./db/read_rtl_${view_name}.ddc



#/ setting constrains
#---------------------------------------- 

source   -v -e   $COMMON_DIR/Constraint/set_dont_touch.tcl

source   -v -e   $COMMON_DIR/Constraint/clkCnst.tcl

source   -v -e    $COMMON_DIR/Constraint/groupPath.tcl

source   -v -e    $COMMON_DIR/Constraint/ioCnst.tcl

source   -v -e    $COMMON_DIR/Constraint/timeExcpt.tcl

source   -v -e    $COMMON_DIR/Constraint/drcCnst.tcl

#source   -v -e    $COMMON_DIR/Constraint/adder.sdc


#/ Compile design
#---------------------------------------- 

source   -v -e   $COMMON_DIR/nameRule.tcl

source   -v -e    $COMMON_DIR/compileOpt.tcl

# Auto hold fixing
set_fix_hold [all_clocks]

check_timing > ../report/check_timing_${view_name}.txt

# clock gating
#------------------------


#compile -map_effort medium
#

#write -f verilog -h -o ../netlist/$PROJECT.h.v


set compile_enable_register_merging false

set_fix_multiple_port_nets -feedthroughs -buffer -all

current_design $topDesign


compile_ultra -no_autoungroup -no_seq_output_inversion -no_boundary_optimization -gate_clock -no_design_rule 
#
#check_timing > 2.txt
#
#
#compile_ultra -no_autoungroup -no_seq_output_inversion -no_boundary_optimization  -gate_clock  -incr  -no_design_rule

#write -f verilog -h -o ../netlist/$PROJECT.h.v

write  -h -output ../db/compile_ultra.ddc

#write -format verilog -hier -out ../mapped/design_net.v

#/ Report Design
#---------------------------------------- 

source    $COMMON_DIR/nameRule.tcl


source    $COMMON_DIR/rpt.tcl

set_svf off


# Exit
#---------------------------------------- 

exit