set view_name 0302

set PROJECT i2c_slave_top
set design_top i2c_slave_top
#---------------------------------------------------------

# fs8001 script formality script
# ---------------------------------------------------------
set verification_clock_gate_mode any
set verification_clock_gate_hold_mode any
set synopsys_auto_setup true
set hdlin_unresolved_modules black_box

#set_svf "../../../np2f0015_dc_work_20220418/syn/netlist/syn_svf_0418.svf"
set_svf ../svf/syn_20260228.svf
# set_svf ../../syn/netlist/syn_1120.svf

# read_db { /opt/PDK/SMIC/SMIC55/LCMO_LL_1.2_2.5/stdcell/SCC55NLL_HD_RVT_V2p0b/synopsys/1.2v/scc55nll_hd_rvt_ss_v1p08_125c_ccs.db \
#          /opt/PDK/SMIC/SMIC55/LCMO_LL_1.2_2.5/stdcell/SCC55NLL_HD_HVT_V2p1a/liberty/1.2v/scc55nll_hd_hvt_ss_v1p08_125c_ccs.db \
#          /opt/PDK/SMIC/SMIC55/LCMO_LL_1.2_2.5/stdcell/SCC55NLL_HD_ECO_HVT_V1p1a/liberty/1.2v//scc55nll_hd_eco_hvt_ss_v1p08_125c_ccs.db \
#          /home/guanza/NP2B6002/syn/NP2B6002_dig_top_syn_241128/syn/lib/efuse/S55NLLEFUSE_PIPO4KB_F2_C_V1.4_ss_V1p08_125C.db \
#          /home/guanza/NP2B6002/syn/NP2B6002_dig_top_syn_241128/syn/lib/sram/db/S55NLLGDPH_W640_B12_M4_ss_1.08_125.db \
#          /home/guanza/NP2B6002/syn/NP2B6002_dig_top_syn_241128/syn/lib/sram/db/S55NLLGDPH_W640_B48_M4_ss_1.08_125.db \
#          /home/guanza/NP2B6002/syn/NP2B6002_dig_top_syn_241128/syn/lib/sram/db/S55NLLGSPH_W256_B32_M4_ss_1.08_125.db \
   
#     }

read_db {
	/opt/PDK/SMIC/SMIC18/std_cell/arm_7t_rvt/db/sc7_logic018ll_base_rvt_tt_typ_max_1p80v_25c.db 
	}

# read RTL source
# ---------------------------------------------------------
#read_verilog -05 -r ../../syn/cnst/filelist.f
#read_verilog -05 -r ./filelist.f

#read_verilog -09 -r ../../../np2f0015_dc_work_20220629/syn/script/np2f0015_filelist.f
read_verilog -09 -r ../script/filelist.f

# define top module name in RTL file
#set_top r:/WORK/dsi_fs8001_top
#set_top r:/WORK/np2f0015_dig_top
set_top r:/WORK/i2c_slave_top

#set_constant r:/WORK/adder/P2D_SCAN_EN 0
#set_constant r:/WORK/adder/P2D_SCAN_MODE 0

# read ate netlist
# ---------------------------------------------------------
#read_verilog -i {../../syn/netlist/dsi_fs8001_top_syn.vg }

#read_verilog -i {../../../np2f0015_dc_work_20220629/syn/netlist/np2f0015_dig_top_syn_0629.vg }
read_verilog -i { ../../syn/netlist/i2c_slave_top_syn.vg }

#set_top i:/WORK/dsi_fs8001_top
#set_top i:/WORK/np2f0015_dig_top
set_top i:/WORK/i2c_slave_top

#set_constant i:/WORK/adder/P2D_SCAN_EN 0
#set_constant i:/WORK/adder/P2D_SCAN_MODE 0


# Compare
# ---------------------------------------------------------

match

set verification_failing_point_limit 0

verify

#match report
# ---------------------------------------------------------
if {![file exist ../report/${view_name}/rtl2syn_rpt ]} { \
  file mkdir ../report/${view_name}/rtl2syn_rpt \
}

report_failing_points >                   ../report/${view_name}/rtl2syn_rpt/rpt_failing_points

report_unmatched_points >                 ../report/${view_name}/rtl2syn_rpt/rpt_unmatched_points
report_unmatched_points -datapath >>      ../report/${view_name}/rtl2syn_rpt/rpt_unmatched_points
report_unmatched_points -status unread >> ../report/${view_name}/rtl2syn_rpt/rpt_unmatched_points
#report_unmatched_points -point_type all
quit
