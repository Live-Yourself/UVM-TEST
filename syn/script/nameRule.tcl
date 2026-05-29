#*******************************************************************
#  RTL to GDSII Script Database
#  Copyright(c) 2018-2019 Nephotonics.inc, All rights reserved
#*******************************************************************
#
# FILENAME:	nameRule.tcl
#
# DESCRIPTION:
#
# 	Change name of netlist cell	
#
# VERSION:
#
# 	V-2003.6
#
# REVISION:
#
# 	Date		Mod.by		Change 
#       ===============================================
#       June. 10,2019   David Zhao       Initial version
#
#--------------------------------------------------------------------

# ------------------------------------------------------
# Define naming rule
# ------------------------------------------------------

# Define top naming rule
# ----------------------

	define_name_rules asic_top_rules -reset

        define_name_rules verilog \
                -allow [list a-z 0-9 _] \
                -first_restrict [list 0-9 _] \
                -type net

        define_name_rules verilog \
                -reserved [list always and assign begin \
                buf bufif0 bufif1 case casex casez cmos \
                deassign default defparam disable edge \
                else end endattribute endcase endfunction \
                endmodule endprimitive endspecify endtable \
                endtask event for force forever fork function \
                highz0 highz1 if initial inout input integer \
                join large macromodule medium module nand \
                negedge nmos nor not notif0 notif1 or output \
                parameter pmos posedge primitive pull0 \
                pull1 pullup pulldown reg rcmos reg release \
                repeat rnmos rpmos rtran rtranif0 rtranif1 \
                scalared small specify specparam strength \
                strong0 strong1 supply0 supply1 table task \
                time tran tranif0 tranif1 tri tri0 tri1 \
                trinand trior trireg use vectored wait wand \
                weak0 weak1 while wire wor xor xnor] \
                -target_bus_naming_style {%s[%d]}

#	define_name_rules asic_top_rules -max_length 32 -type port

# Define core naming rule
# -----------------------

	define_name_rules asic_core_rules -reset

	define_name_rules asic_core_rules -max_length 255

# Change name
# -----------

	change_names -hierarchy -rules verilog

	change_names -hierarchy -rules asic_core_rules

	change_names -rules asic_top_rules

#--------------------------------------------------------------------
# Set design write-out options
#--------------------------------------------------------------------

        set verilogout_no_tri true
