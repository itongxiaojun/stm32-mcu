# ========================================================================
# FES32 physical implementation on ICS55 (55nm) with OpenROAD.
#
# Input : the gate-level netlist from syn/run_ics55_synth.sh
# Output: syn/pnr/Fes32SynthTop.def (+ timing/area reports)
#
# Run with:
#   PDK_DIR=... MACRO_DIR=... NETLIST=... OUT_DIR=... \
#     openroad -no_init -exit syn/fes32_pnr.tcl
#
# STAGE selects how far to run, for debugging:
#   floorplan | place | cts | route (default)
# ========================================================================

set repo    [file normalize [file dirname [info script]]/..]
set pdk     $::env(PDK_DIR)
set macro   $::env(MACRO_DIR)
set netlist $::env(NETLIST)
set out     $::env(OUT_DIR)
set stage   [expr {[info exists ::env(STAGE)] ? $::env(STAGE) : "route"}]

set pdkroot  $pdk/extracted
set pdkver   $pdkroot/icsprout55-pdk-1.10.102

# Use the "_ecos" LEF variants throughout. They are the ones intended for the
# open-source EDA ecosystem and differ from the plain LEFs in two ways that
# matter here:
#   - routing layer OFFSET is 0.1 0.1 instead of 0 0, which puts the MET1
#     tracks at x = 0.1, 0.3, 0.5, ... and so over the narrow MET1 cell pins
#     (e.g. AO222X4H7L/C1 spans x 0.225-0.375). With OFFSET 0 0 the tracks sit
#     at 0.2, 0.4, ... and miss those pins entirely, which is what made
#     TritonRoute report DRT-0073 "No access point" for the large-drive cells.
#   - CAPACITANCE / EDGECAPACITANCE are present, so wire RC comes from the LEF
#     instead of the resizer warning that capacitance is 0.
set tech_lef $pdkver/prtech/techLEF/N551P6M_ecos.lef
set std_dir  $pdkver/IP/STD_cell/ics55_LLSC_H7C_V1p10C100
set io_lef   $pdkver/IP/IO/ICsprout_55LLULP1233_IO_251013/lef/ICSIOA_N55_3P3_1P6M1TM_ecos.lef
set sram_lef $macro/lef/ics55_ecos_sram_1024x80_m4.lef

set lib_h7cl $pdkroot/liberty/ics55_LLSC_H7CL_typ_tt_1p2_25_nldm.lib
set lib_h7cr $pdkroot/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib
set lib_sram $macro/lib/ics55_ecos_sram_1024x80_m4_tt1p2v25cctyp.lib

file mkdir $out

foreach f [list $tech_lef $io_lef $sram_lef $lib_h7cl $lib_h7cr $lib_sram $netlist \
                $std_dir/ics55_LLSC_H7CL/lef/ics55_LLSC_H7CL_ecos.lef \
                $std_dir/ics55_LLSC_H7CR/lef/ics55_LLSC_H7CR_ecos.lef] {
    if {![file exists $f]} { puts "ERROR: missing input: $f"; exit 1 }
}

# ---------------------------------------------------------------- libraries
puts "=== reading LEF ==="
read_lef $tech_lef
read_lef $io_lef
read_lef $sram_lef
read_lef $std_dir/ics55_LLSC_H7CL/lef/ics55_LLSC_H7CL_ecos.lef
read_lef $std_dir/ics55_LLSC_H7CR/lef/ics55_LLSC_H7CR_ecos.lef

puts "=== reading Liberty ==="
read_liberty $lib_h7cl
read_liberty $lib_h7cr
read_liberty $lib_sram

puts "=== reading netlist ==="
read_verilog $netlist
link_design Fes32SynthTop

# ------------------------------------------------------------------- timing
set clk_period_ns 10.0
create_clock -name clock -period $clk_period_ns [get_ports clock]
# The _ecos tech LEF carries per-layer RC, so let set_wire_rc take it from the
# LEF rather than inventing values.
set_wire_rc -signal -layer MET2
set_wire_rc -clock  -layer MET3

puts "=== post-link area ==="
report_design_area

# --------------------------------------------------------------- floorplan
puts "=== floorplan ==="
# Utilization is kept below the usual 45-50%: the two SRAM macros take ~34%
# of the core and each brings 80-bit D/Q/WEB buses (240 nets per macro) whose
# pins all land on one side, so 45% congested global routing (GRT-0116).
initialize_floorplan -utilization 40 -aspect_ratio 1.0 -core_space 5 -site core7
make_tracks

# Use MET2-MET5 for signal routing and MET3-MET5 for the clock; MET1 is left
# for standard-cell pins.
set_routing_layers -signal MET2-MET5 -clock MET3-MET5

# Place the two SRAM macros along the left edge. They are 370.615 x 155.535 um
# each, so they dominate the core and must not be left for the placer to
# scatter.
#
# NOTE: setting the location through the OpenDB Tcl API does not work here -
# `$inst setPlacementStatus FIXED` (and odb::dbInst_setPlacementStatus) both
# leave the status at NONE with no error, so the placer keeps treating the
# macros as unplaced and the rows are never cut. The `place_macro` command
# from the mpl module does update the status.
puts "=== macro placement ==="
set block [ord::get_db_block]
set dbu   [$block getDbUnitsPerMicron]
set core  [$block getCoreArea]
puts [format "core: %.1f %.1f -> %.1f %.1f um" \
        [expr {[$core xMin]/double($dbu)}] [expr {[$core yMin]/double($dbu)}] \
        [expr {[$core xMax]/double($dbu)}] [expr {[$core yMax]/double($dbu)}]]
# Flush against the core's left edge: leaving a 2 um sliver there produces
# unusable rows that the detailed placer cannot legalise into.
set mx [expr {[$core xMin]/double($dbu)}]
set my [expr {([$core yMin] + 2*$dbu)/double($dbu)}]
# Gap between the two macros: the macro OBS covers MET1-MET3 over almost the
# whole footprint (only 0.18 um pin-escape notches) and MET4 is a power-stripe
# grid, so MET5 is the only layer that can cross a macro. Leaving a channel
# between them gives horizontal routing somewhere to go.
set macro_gap 20.0
set placed 0
foreach inst [$block getInsts] {
    set master [$inst getMaster]
    if {[$master isBlock]} {
        set h [expr {[$master getHeight]/double($dbu)}]
        place_macro -macro_name [$inst getName] -location "$mx $my"
        puts [format "  placed %s at %.2f,%.2f status=%s" \
                [$inst getName] $mx $my [$inst getPlacementStatus]]
        set my [expr {$my + $h + $macro_gap}]
        incr placed
    }
}
puts "  macros placed: $placed"

# Remove the standard-cell rows that the macros cover; without this the
# detailed placer reports DPL-0033 "Overlap check failed" against the macros.
puts "=== cutting rows around macros ==="
set rows_before [llength [$block getRows]]
cut_rows -halo_width_x 0.6 -halo_width_y 0.6
set rows_after [llength [$block getRows]]
puts "  rows: $rows_before -> $rows_after"
foreach inst [$block getInsts] {
    if {[[$inst getMaster] isBlock]} {
        puts "  macro [$inst getName] status=[$inst getPlacementStatus] origin=[$inst getOrigin]"
    }
}

# 200 boundary pins: horizontal on MET3, vertical on MET2
place_pins -hor_layers MET3 -ver_layers MET2

if {$stage eq "floorplan"} { puts "=== stopped at floorplan ==="; exit 0 }

# --------------------------------------------------------------- placement
puts "=== global placement ==="
global_placement -density 0.65

puts "=== detailed placement ==="
detailed_placement
optimize_mirroring
check_placement

report_design_area

if {$stage eq "place"} { puts "=== stopped at place ==="; exit 0 }

# --------------------------------------------------------------------- CTS
puts "=== clock tree synthesis ==="
clock_tree_synthesis \
    -root_buf BUFX1P4H7L \
    -buf_list {BUFX1P4H7L BUFX1P4H7R BUFX1H7L BUFX1H7R} \
    -sink_clustering_enable

detailed_placement
check_placement

if {$stage eq "cts"} {
    puts "=== writing placed DEF (floorplan + placement + CTS) ==="
    write_def $out/Fes32SynthTop_placed.def
    puts "=== stopped at cts ==="
    exit 0
}

# ----------------------------------------------------------------- routing
puts "=== global route ==="
# The macros block MET1-MET3 over their footprint, so this design is routing
# resource limited around the macro pin escapes. -allow_congestion lets GRT
# finish and hand a guide file to the detailed router instead of aborting with
# GRT-0116; any remaining violations are reported in the DRC file.
global_route -congestion_iterations 60 \
             -congestion_report_file $out/congestion.rpt \
             -guide_file $out/route.guide \
             -allow_congestion

puts "=== detailed route ==="
# Some large-drive H7L cells (AO222X4H7L, AOI21BX3H7L, MUX2X3H7L ...) have very
# narrow MET1 pin shapes (0.09 um wide) and TritonRoute reported DRT-0073
# "No access point" for them at the default access-point count. Allowing a
# single access point lets those pins route.
detailed_route -output_drc $out/route_drc.rpt \
               -bottom_routing_layer MET1 \
               -top_routing_layer MET5 \
               -min_access_points 1 \
               -droute_end_iter 20 \
               -verbose 1

puts "=== reports ==="
report_design_area
set powered_nets [llength [get_nets -hierarchical *]]
puts "nets: $powered_nets"

puts "=== writing DEF ==="
write_def $out/Fes32SynthTop.def

puts "=== done ==="
