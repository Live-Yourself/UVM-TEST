#********************************************************************
#   RTL to GDSII Script Database
#   Copyright(c) 2018-2019 Nephotonics.inc, All rights reserved
#********************************************************************
#   FileName  setupLib.tcl
#   Description: 
#       Set library
#   Version
#       V-2014.08
#   Revision:
#       Date          Mod.By           Change made
#       ===================================================
#       June. 10,2019   David Zhao       Initial version
#       March. 02,2026  Copilot          Update for typical target + OCs
#********************************************************************

# set search path
#----------------------------------------

set STDCELL_LIBDIR ../lib/arm_7t_rvt/db

set search_path  [list $STDCELL_LIBDIR ]

#set synthetic_library dw_foundation.sldb

#/* define db  ( fst or tpl  or slw ) */
#----------------------------------------

# set STDCELL_LIBNAME_FAST ff_typ_min_1p98v_m40c
set STDCELL_LIBRARY_FAST [format "%s%s"  $STDCELL_LIBDIR /sc7_logic018ll_base_rvt_ff_typ_min_1p98v_m40c.db]

set STDCELL_LIBNAME_FAST sc7_logic018ll_base_rvt_ff_typ_min_1p98v_m40c

set STDCELL_LIBRARY_TYPICAL [format "%s%s"  $STDCELL_LIBDIR /sc7_logic018ll_base_rvt_tt_typ_max_1p80v_25c.db]
set STDCELL_LIBNAME_TYPICAL sc7_logic018ll_base_rvt_tt_typ_max_1p80v_25c

set STDCELL_LIBRARY_SLOW [format "%s%s"  $STDCELL_LIBDIR /sc7_logic018ll_base_rvt_ss_typ_max_1p62v_125c.db]
# set STDCELL_LIBNAME_SLOW ss_typ_max_1p62v_125c
set STDCELL_LIBNAME_SLOW sc7_logic018ll_base_rvt_ss_typ_max_1p62v_125c

# Use typical as target for synthesis
set STDCELL_LIBRARY $STDCELL_LIBRARY_TYPICAL
set STDCELL_LIBNAME $STDCELL_LIBNAME_TYPICAL

#set EFUSE_LIBRARY_FAST [format "%s%s"  $EFUSE_LIBDIR /S0153GEFUSE_PIPO512B_V0.2.1_ff_V1p98_-40C_201312SP57.db]
#set EFUSE_LIBNAME_FAST S0153GEFUSE_PIPO512B_V0.2.1_ff_V1p98_-40C

#set EFUSE_LIBRARY_TYPICAL [format "%s%s"  $EFUSE_LIBDIR /S0153GEFUSE_PIPO512B_V0.2.1_tt_V1p8_25C_201312SP57.db]
#set EFUSE_LIBNAME_TYPICAL S0153GEFUSE_PIPO512B_V0.2.1_tt_V1p8_25C

#set EFUSE_LIBRARY_SLOW [format "%s%s"  $EFUSE_LIBDIR /S0153GEFUSE_PIPO512B_V0.2.1_ss_V1p62_125C_201312SP57.db]
#set EFUSE_LIBNAME_SLOW S0153GEFUSE_PIPO512B_V0.2.1_ss_V1p62_125C

#set EFUSE_LIBRARY $EFUSE_LIBRARY_SLOW
#set EFUSE_LIBNAME $EFUSE_LIBNAME_SLOW


set target_library  [list $STDCELL_LIBRARY ]


# set link library
#----------------------------

set link_library [list "*" $target_library ]

# Min/Max library for timing
set_min_library $STDCELL_LIBRARY_SLOW -min_version $STDCELL_LIBRARY_FAST

#set_dont_use [find cell [format "%s%s"   $STDCELL_LIBNAME  "/*"   ]]
