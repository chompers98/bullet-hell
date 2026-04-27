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
