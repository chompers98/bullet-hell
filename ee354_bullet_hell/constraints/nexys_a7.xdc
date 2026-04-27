## Nexys A7 pin assignments for EE354 bullet-hell project.
## Derived from the class-provided A7_nexys7.xdc (Sharath Krishnan) and pared
## down to the signals we actually use. Pin names match the top-level modules
## (top.v for Task 2; vga_test_top.v for Task 1 uses the same inputs/outputs).

# ---- 100 MHz board clock ----
set_property PACKAGE_PIN E3 [get_ports ClkPort]
    set_property IOSTANDARD LVCMOS33 [get_ports ClkPort]
    create_clock -add -name ClkPort -period 10.00 [get_ports ClkPort]

# ---- Buttons ----
# BtnC = center. In vga_test_top it's reset; in top.v it's shoot (BtnCenter,
# SPEC §10.1 L541). Pin mapping is the same in both cases.
set_property PACKAGE_PIN N17 [get_ports BtnC]
    set_property IOSTANDARD LVCMOS33 [get_ports BtnC]
# Directional buttons — used by top.v for player_controller, unused by vga_test_top.
# Vivado will issue "unconnected port" warnings when vga_test_top is the top
# module; those are safe to ignore.
set_property PACKAGE_PIN M18 [get_ports BtnU]
    set_property IOSTANDARD LVCMOS33 [get_ports BtnU]
set_property PACKAGE_PIN P17 [get_ports BtnL]
    set_property IOSTANDARD LVCMOS33 [get_ports BtnL]
set_property PACKAGE_PIN M17 [get_ports BtnR]
    set_property IOSTANDARD LVCMOS33 [get_ports BtnR]
set_property PACKAGE_PIN P18 [get_ports BtnD]
    set_property IOSTANDARD LVCMOS33 [get_ports BtnD]

# ---- Slide switches ----
# SW0 = active-high sync reset for top.v (replaces BtnC-as-reset from Task 2
# original; see SPEC §0 Q3 revision).
set_property PACKAGE_PIN J15 [get_ports SW0]
    set_property IOSTANDARD LVCMOS33 [get_ports SW0]

# ---- VGA R/G/B (4:4:4) ----
set_property PACKAGE_PIN A3 [get_ports {vgaR[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaR[0]}]
set_property PACKAGE_PIN B4 [get_ports {vgaR[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaR[1]}]
set_property PACKAGE_PIN C5 [get_ports {vgaR[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaR[2]}]
set_property PACKAGE_PIN A4 [get_ports {vgaR[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaR[3]}]

set_property PACKAGE_PIN C6 [get_ports {vgaG[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaG[0]}]
set_property PACKAGE_PIN A5 [get_ports {vgaG[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaG[1]}]
set_property PACKAGE_PIN B6 [get_ports {vgaG[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaG[2]}]
set_property PACKAGE_PIN A6 [get_ports {vgaG[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaG[3]}]

set_property PACKAGE_PIN B7 [get_ports {vgaB[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaB[0]}]
set_property PACKAGE_PIN C7 [get_ports {vgaB[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaB[1]}]
set_property PACKAGE_PIN D7 [get_ports {vgaB[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaB[2]}]
set_property PACKAGE_PIN D8 [get_ports {vgaB[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {vgaB[3]}]

set_property PACKAGE_PIN B11 [get_ports hSync]
    set_property IOSTANDARD LVCMOS33 [get_ports hSync]
set_property PACKAGE_PIN B12 [get_ports vSync]
    set_property IOSTANDARD LVCMOS33 [get_ports vSync]

# ---- Disable flash chip-select (recommended when not using QSPI) ----
set_property PACKAGE_PIN L13 [get_ports QuadSpiFlashCS]
    set_property IOSTANDARD LVCMOS33 [get_ports QuadSpiFlashCS]

# ---- Player-lives LEDs (active-high) ----
# Pin map from the Nexys A7 schematic (Digilent ref-manual).
set_property PACKAGE_PIN H17 [get_ports {Ld[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[0]}]
set_property PACKAGE_PIN K15 [get_ports {Ld[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[1]}]
set_property PACKAGE_PIN J13 [get_ports {Ld[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[2]}]
set_property PACKAGE_PIN N14 [get_ports {Ld[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[3]}]
set_property PACKAGE_PIN R18 [get_ports {Ld[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[4]}]
set_property PACKAGE_PIN V17 [get_ports {Ld[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[5]}]
set_property PACKAGE_PIN U17 [get_ports {Ld[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[6]}]
set_property PACKAGE_PIN U16 [get_ports {Ld[7]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[7]}]
set_property PACKAGE_PIN V16 [get_ports {Ld[8]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[8]}]
set_property PACKAGE_PIN T15 [get_ports {Ld[9]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[9]}]
set_property PACKAGE_PIN U14 [get_ports {Ld[10]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[10]}]
set_property PACKAGE_PIN T16 [get_ports {Ld[11]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[11]}]
set_property PACKAGE_PIN V15 [get_ports {Ld[12]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[12]}]
set_property PACKAGE_PIN V14 [get_ports {Ld[13]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[13]}]
set_property PACKAGE_PIN V12 [get_ports {Ld[14]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[14]}]
set_property PACKAGE_PIN V11 [get_ports {Ld[15]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {Ld[15]}]

# ---- Boss-HP 7-segment display (active-low cathodes, active-low anodes) ----
# Pin map from class-provided A7_nexys7.xdc (Sharath Krishnan).
# Bit-to-segment mapping: seg[6:0] = {Ca, Cb, Cc, Cd, Ce, Cf, Cg}.
set_property PACKAGE_PIN T10 [get_ports {seg[6]}]   ;# Ca
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[6]}]
set_property PACKAGE_PIN R10 [get_ports {seg[5]}]   ;# Cb
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[5]}]
set_property PACKAGE_PIN K16 [get_ports {seg[4]}]   ;# Cc
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[4]}]
set_property PACKAGE_PIN K13 [get_ports {seg[3]}]   ;# Cd
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[3]}]
set_property PACKAGE_PIN P15 [get_ports {seg[2]}]   ;# Ce
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[2]}]
set_property PACKAGE_PIN T11 [get_ports {seg[1]}]   ;# Cf
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[1]}]
set_property PACKAGE_PIN L18 [get_ports {seg[0]}]   ;# Cg
    set_property IOSTANDARD LVCMOS33 [get_ports {seg[0]}]
set_property PACKAGE_PIN H15 [get_ports Dp]
    set_property IOSTANDARD LVCMOS33 [get_ports Dp]

# Anodes (active-low one-hot)
set_property PACKAGE_PIN J17 [get_ports {An[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[0]}]
set_property PACKAGE_PIN J18 [get_ports {An[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[1]}]
set_property PACKAGE_PIN T9  [get_ports {An[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[2]}]
set_property PACKAGE_PIN J14 [get_ports {An[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[3]}]
set_property PACKAGE_PIN P14 [get_ports {An[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[4]}]
set_property PACKAGE_PIN T14 [get_ports {An[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[5]}]
set_property PACKAGE_PIN K2  [get_ports {An[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[6]}]
set_property PACKAGE_PIN U13 [get_ports {An[7]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {An[7]}]
