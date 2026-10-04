# FES32 ICS55 synthesis

Gate-level synthesis of FES32 on the **ICS55 (55 nm)** library, using the vendor
flow at `/opt/tools/r2g_synth`. Memories are built from the ICS55 SRAM macro
`ics55_ecos_sram_1024x80_m4`, not inferred flip-flops.

## How to run

```sh
# 1. fetch the SRAM macro (once)
mkdir -p syn/sram_macro && cd syn/sram_macro
curl -sSL -o sram.tar.gz https://github.com/openecos-projects/ics55_ecos_sram/releases/download/sram-v1-973408625b3c141338238f13f18dbc59fdcef5b4f06904011cc6955c71928d05/ics55_ecos_sram_1024x80_m4.tar.gz
tar xzf sram.tar.gz && rm sram.tar.gz
cd ../..

# 2. synthesise
bash syn/run_ics55_synth.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `R2G` | `/opt/tools/r2g_synth` | vendor flow root (must contain `lib_ics55/`) |
| `SRAM` | `syn/sram_macro/ics55_ecos_sram_1024x80_m4` | SRAM macro package |
| `OUT` | `syn/build` | output directory |
| `CLK_FREQ_MHZ` | `100` | target clock for ABC |

The script drives `$R2G/yosys/scripts/yosys_synthesis.tcl` — the same script the
SimpleEdge AiSoC flow uses — with the same libraries and tie cells:

- `lib_ics55/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib`
- `lib_ics55/ics55_LLSC_H7CR_ss_rcworst_1p08_125_nldm.lib`
- tie cells `TIELOH7R` / `TIEHIH7R`

Pipeline: `read_slang` → `proc`/`opt`/`fsm`/`memory_map` → `dfflibmap` → `abc`
→ `hilomap` → `write_verilog`.

## How the SRAM macro is used

`read_slang -F` honours `+define+` lines in the filelist, so
[`fes32_synth.f.in`](fes32_synth.f.in) adds

```
+define+FES32_SRAM_MACRO
```

and `Fes32.sv` switches its memory section:

| `FES32_SRAM_MACRO` | Memory implementation |
|---|---|
| undefined (simulation) | inferred `reg [31:0] ... [0:N-1]` arrays |
| defined (synthesis) | two `Fes32Sram2048x32` macro wrappers |

Defining it only for synthesis means **the simulator path is byte-for-byte
unchanged** — the unit tests, the FrameTop test and the flash boot-vector preload
all keep working, and there is no second copy of the memory logic to maintain.

### `Fes32Sram2048x32`

[`Fes32Sram2048x32.v`](Fes32Sram2048x32.v) wraps one macro into a plain
synchronous SRAM. The macro is 1024 rows × 80 bits; the wrapper packs **two
32-bit words per row** so one macro provides the full 2048-word depth:

```
row  = word_addr[10:1]
half = word_addr[0]        -> 0 selects Q[31:0], 1 selects Q[63:32]
```

Write masking uses the macro's per-bit active-low `WEB`: only the selected half
is unmasked, so a write never disturbs the other word in the row, and byte
granularity comes from `wstrb`. `half_r` is registered alongside the macro's
registered `Q` so the output mux lines up with the row the macro sampled.

> **Why not `memory_libmap`?** The macro's Liberty `memory()` group declares only
> `address_width`/`word_width` plus `memory_read()` on `Q` — there is **no
> `memory_write()` group**. Yosys needs the write-side groups (`memory_write()`
> on `D`/`WEB`/`CEB`/`GWEB`) to infer how to drive the macro, so automatic mapping
> falls back to flip-flops. Explicit instantiation is required.

### Sizing constraint

The wrapper covers **at most 2048 words per memory** (one macro). FES32's own
defaults are the full STM32F103 sizes (65536 flash / 16384 SRAM words), which
exceed that, so synthesis uses [`Fes32SynthTop.sv`](Fes32SynthTop.sv), which
instantiates `Fes32` with

| | simulation default | synthesis |
|---|---:|---:|
| `FLASH_WORDS` | 65536 (256 KB) | 2048 (8 KB) |
| `SRAM_WORDS` | 16384 (64 KB) | 2048 (8 KB) |
| macros | — | 1 flash + 1 SRAM |

A deeper memory needs more macros (or a deeper wrapper). The wrapper is not part
of `designs/fes32/design.json`, so it is never compiled into a simulation.

## Result

Run on `fireflyer@192.168.100.103`, ICS55, 100 MHz target:

| Metric | SRAM macro | (earlier, flop-based) |
|---|---:|---:|
| Cells | **13,251** | 321,444 |
| Flip-flops `DFFQX1H7R` | **2,404** | 100,770 |
| Standard-cell area | **36,527 µm²** | 1,149,001 µm² |
| SRAM macro area | 2 × 57,643.6 = **115,287 µm²** | — |
| Total area | **≈0.152 mm²** | ≈1.149 mm² |
| Netlist | **2.43 MB** | 48.8 MB |
| ABC runtime | **78 s** | 1553 s |
| `check` | 0 problems | 0 problems |

The ~2.4 K remaining flip-flops are the picorv32 pipeline, the GPIO registers and
the memory interface; all 100 K memory flops are gone. Total area drops 7.6×.

## Outputs (`syn/build/`)

| File | Contents |
|---|---|
| `Fes32SynthTop_synth.v` | gate-level netlist, standard cells + 2 SRAM macro instances |
| `synth_stat.json` | final cell/area statistics per module |
| `generic_stat.json` | pre-mapping generic cell statistics |
| `timing_cell_count.rpt` | DFF / latch counts |
| `synth_check.rpt` | Yosys `check` result (0 problems) |
| `fes32_synth.f` | materialised filelist actually used |
| `synth.log` | full flow log |

`syn/build/` and `syn/sram_macro/` are git-ignored — regenerate with the script.

## PDK: standard cells, IO and tech LEF

Synthesis only needs Liberty, which the vendor flow already carries in
`$R2G/lib_ics55/`. A physical flow additionally needs LEF, which comes from the
PDK release:

```sh
bash syn/fetch_ics55_pdk.sh          # -> syn/pdk/icsprout55-pdk-v1.10.102/extracted
```

`fetch_ics55_pdk.sh` uses `gh-proxy.com` first and falls back to direct
github.com. That matters here: cloning the PDK repository fails with
`fetch-pack: unexpected disconnect / early EOF`, and direct release downloads
stall at a measured ~4 KB/s with SSL `unexpected eof` drops, against ~950 KB/s
through the mirror.

Release `v1.10.102` provides:

| Item | Path (under `extracted/`) |
|---|---|
| Tech LEF | `icsprout55-pdk-1.10.102/prtech/techLEF/N551P6M.lef` |
| Std-cell LEF | `icsprout55-pdk-1.10.102/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_{H7CL,H7CR,H7CH}/lef/*.lef` |
| IO LEF | `icsprout55-pdk-1.10.102/IP/IO/ICsprout_55LLULP1233_IO_251013/lef/ICSIOA_N55_3P3_1P6M1TM.lef` |
| Liberty | `liberty/`, 3 cell families x 7 corners |
| GDS | `gds/` |

The SRAM macro's LEF comes from the separate macro package (see above), not from
the PDK.

> The PDK's `ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib` differs from the copy
> in `$R2G/lib_ics55/` by 10 lines only: the release adds
> `clock_gating_integrated_cell` attributes for the ICG cells. Cell count (747)
> and all timing/area data are identical, so synthesis results are unaffected.

## Note on the netlist

The netlist top is `Fes32SynthTop`, which carries the 2048-word memory
configuration. The macro instances appear as `ics55_ecos_sram_1024x80_m4` cells;
a physical flow must supply that macro's LEF (and the standard-cell LEF) to place
them.
