# Version:1.0 MMMC View Definition File
# Do Not Remove Above Line
# PATH: 

create_library_set -name typical_case -timing {/w/class.1/ee/ee209b/ee209bta/TSMC180PDK/Standard_Cells_and_IO/180_G_Standard_Cell/core_cell_library/core_cell_library/7-track/tcb018gbwp7t_290a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcb018gbwp7t_270a/tcb018gbwp7ttc.lib}
create_library_set -name best_case -timing {/w/class.1/ee/ee209b/ee209bta/TSMC180PDK/Standard_Cells_and_IO/180_G_Standard_Cell/core_cell_library/core_cell_library/7-track/tcb018gbwp7t_290a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcb018gbwp7t_270a/tcb018gbwp7tbc.lib}
create_library_set -name worst_case -timing {/w/class.1/ee/ee209b/ee209bta/TSMC180PDK/Standard_Cells_and_IO/180_G_Standard_Cell/core_cell_library/core_cell_library/7-track/tcb018gbwp7t_290a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcb018gbwp7t_270a/tcb018gbwp7twc.lib}

#create_rc_corner -name wstcap -cap_table "/space/yanz/Genus/MEM_TEST_12112017/N28_5X2Y2R_RCBEST.capTbl" -T 25
#create_rc_corner -name bstcap -cap_table "/space/yanz/Genus/MEM_TEST_12112017/N28_5X2Y2R_RCWORST.capTbl" -T 25

create_rc_corner -name typrc -qx_tech_file "/w/class.1/ee/ee209b/ee209bta/TSMC180PDK/EXTRAS/qrcTechFile" -temperature 25.0 -cap_table /w/class.1/ee/ee209b/ee209bta/TSMC180PDK/Standard_Cells_and_IO/180_G_Standard_Cell/core_cell_library/core_cell_library/7-track/tcb018gbwp7t_290a/TSMCHOME/digital/Back_End/lef/tcb018gbwp7t_270a/techfiles/captable/t018lo_1p6m_typical.captable
create_rc_corner -name wstrc -qx_tech_file "/w/class.1/ee/ee209b/ee209bta/TSMC180PDK/EXTRAS/qrcTechFile" -temperature 125.0 -cap_table /w/class.1/ee/ee209b/ee209bta/TSMC180PDK/Standard_Cells_and_IO/180_G_Standard_Cell/core_cell_library/core_cell_library/7-track/tcb018gbwp7t_290a/TSMCHOME/digital/Back_End/lef/tcb018gbwp7t_270a/techfiles/captable/t018lo_1p6m_typical.captable
create_rc_corner -name bstrc -qx_tech_file "/w/class.1/ee/ee209b/ee209bta/TSMC180PDK/EXTRAS/qrcTechFile" -temperature -40.0 -cap_table /w/class.1/ee/ee209b/ee209bta/TSMC180PDK/Standard_Cells_and_IO/180_G_Standard_Cell/core_cell_library/core_cell_library/7-track/tcb018gbwp7t_290a/TSMCHOME/digital/Back_End/lef/tcb018gbwp7t_270a/techfiles/captable/t018lo_1p6m_typical.captable

create_constraint_mode -name design_one -sdc_files {./Chip.mapped.sdc}

create_delay_corner -name TT -library_set {typical_case} -rc_corner {typrc}
create_delay_corner -name TF -library_set {typical_case} -rc_corner {bstrc}
create_delay_corner -name TS -library_set {typical_case} -rc_corner {wstrc}
create_delay_corner -name FT -library_set {best_case} -rc_corner {typrc}
create_delay_corner -name FF -library_set {best_case} -rc_corner {bstrc}
create_delay_corner -name FS -library_set {best_case} -rc_corner {wstrc}
create_delay_corner -name ST -library_set {worst_case} -rc_corner {typrc}
create_delay_corner -name SF -library_set {worst_case} -rc_corner {bstrc}
create_delay_corner -name SS -library_set {worst_case} -rc_corner {wstrc}

create_analysis_view -name OTT -constraint_mode {design_one} -delay_corner {TT}
create_analysis_view -name OTF -constraint_mode {design_one} -delay_corner {TF}
create_analysis_view -name OTS -constraint_mode {design_one} -delay_corner {TS}
create_analysis_view -name OFT -constraint_mode {design_one} -delay_corner {FT}
create_analysis_view -name OFF -constraint_mode {design_one} -delay_corner {FF}
create_analysis_view -name OFS -constraint_mode {design_one} -delay_corner {FS}
create_analysis_view -name OST -constraint_mode {design_one} -delay_corner {ST}
create_analysis_view -name OSF -constraint_mode {design_one} -delay_corner {SF}
create_analysis_view -name OSS -constraint_mode {design_one} -delay_corner {SS}

set_analysis_view -setup {OTT OTF OTS OFT OFF OFS OST OSF OSS} -hold {OTT OTF OTS OFT OFF OFS OST OSF OSS}


