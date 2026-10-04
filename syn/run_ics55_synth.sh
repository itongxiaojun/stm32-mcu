#!/usr/bin/env bash
# ========================================================================
# FES32 synthesis on the ICS55 (55nm) standard-cell library.
#
# Reuses the vendor flow at $R2G (default /opt/tools/r2g_synth):
#   yosys/scripts/yosys_synthesis.tcl  (slang front-end -> dfflibmap -> ABC)
# with the same ICS55 H7CL/H7CR libraries and tie cells.
#
# Memories are built from the ICS55 SRAM macro ics55_ecos_sram_1024x80_m4
# (see $SRAM below), not inferred flip-flops.
#
# Usage:  bash syn/run_ics55_synth.sh
# Output: syn/build/  (netlist + timing/area reports)
# ========================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
R2G="${R2G:-/opt/tools/r2g_synth}"
OUT="${OUT:-$REPO/syn/build}"
SRAM="${SRAM:-$REPO/syn/sram_macro/ics55_ecos_sram_1024x80_m4}"

if [ ! -d "$R2G/lib_ics55" ]; then
    echo "error: ICS55 library directory not found: $R2G/lib_ics55" >&2
    echo "       set R2G=/path/to/r2g_synth" >&2
    exit 1
fi

if [ ! -f "$SRAM/verilog/ics55_ecos_sram_1024x80_m4_stub.v" ]; then
    echo "error: ICS55 SRAM macro not found at $SRAM" >&2
    echo "       fetch it with:" >&2
    echo "         mkdir -p \"\$(dirname \"$SRAM\")\" && cd \"\$(dirname \"$SRAM\")\"" >&2
    echo "         curl -sSL -o sram.tar.gz https://github.com/openecos-projects/ics55_ecos_sram/releases/download/sram-v1-973408625b3c141338238f13f18dbc59fdcef5b4f06904011cc6955c71928d05/ics55_ecos_sram_1024x80_m4.tar.gz" >&2
    echo "         tar xzf sram.tar.gz && rm sram.tar.gz" >&2
    echo "       or point SRAM=/path/to/ics55_ecos_sram_1024x80_m4 at an existing copy" >&2
    exit 1
fi

mkdir -p "$OUT"

# Materialise the filelist with absolute paths for this checkout.
sed -e "s|\$REPO|$REPO|g" -e "s|\$SRAM|$SRAM|g" \
    "$REPO/syn/fes32_synth.f.in" > "$OUT/fes32_synth.f"

export TOP_NAME="Fes32SynthTop"
export CLK_FREQ_MHZ="${CLK_FREQ_MHZ:-100}"
export FILELIST="$OUT/fes32_synth.f"

export RESULT_DIR="$OUT"
export NETLIST_FILE="$OUT/${TOP_NAME}_synth.v"
export TIMING_CELL_STAT_RPT="$OUT/timing_cell_stat.rpt"
export TIMING_CELL_COUNT_RPT="$OUT/timing_cell_count.rpt"
export GENERIC_STAT_JSON="$OUT/generic_stat.json"
export SYNTH_STAT_JSON="$OUT/synth_stat.json"
export SYNTH_CHECK_RPT="$OUT/synth_check.rpt"

export KEEP_HIERARCHY="false"
export CELL_DONT_USE=""
export CELL_TIE_LOW="TIELOH7R"
export CELL_TIE_LOW_PORT="Z"
export CELL_TIE_HIGH="TIEHIH7R"
export CELL_TIE_HIGH_PORT="Z"

export LIB_STDCELL="$R2G/lib_ics55/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib $R2G/lib_ics55/ics55_LLSC_H7CR_ss_rcworst_1p08_125_nldm.lib"
export LIB_ALL="$LIB_STDCELL"

echo "=== FES32 ICS55 synthesis ==="
echo "repo       : $REPO"
echo "top        : $TOP_NAME"
echo "clock      : ${CLK_FREQ_MHZ} MHz"
echo "output     : $OUT"
echo "yosys      : $(command -v yosys)"
echo "filelist   :"
sed 's/^/  /' "$OUT/fes32_synth.f"
echo

yosys "$R2G/yosys/scripts/yosys_synthesis.tcl" 2>&1 | tee "$OUT/synth.log"
