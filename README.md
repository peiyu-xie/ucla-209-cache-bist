# ucla-209-cache-bist

Fully associative cache with CAM tag comparison and an LFSR/MISR BIST engine, taped out in 180nm CMOS. EC ENGR 209, UCLA. Hand-written RTL and testbenches only.

## Contents

```
flow/mmmc_ori.tcl
rtl/BIST_Controller.sv
rtl/Cache.sv
rtl/Cache_BIST_Top.sv
rtl/Cache_BIST_Top_tb.sv
rtl/Cache_tb.sv
rtl/Chip.sv
rtl/Chip_post_sim_tb.sv
rtl/Chip_tb.sv
rtl/P2S.sv
rtl/S2P.sv
rtl/TPG.sv
rtl/TPG_tb.sv
rtl/bidirectional_P2S_S2P.sv
rtl/bidirectional_P2S_S2P_tb.sv
```

## Not included

- Chip_ckt.v (Innovus post-layout netlist -- instantiates TSMC BWP7T standard cells; PDK-derived)
- TSMC180nm Setup and Layout Tutorial.pdf, UCLA-32-Pin-Pad-Frame_2026.pdf, TapeoutChecklist_2026.pdf, 209Info_2026.pdf and the other course PDFs (foundry NDA / instructor material)
- rtl.zip (duplicate of rtl/)

---

Author: Pei-yu Xie
