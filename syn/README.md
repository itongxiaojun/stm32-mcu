# FES32 ICS55 synthesis

Gate-level synthesis of FES32 on the **ICS55 (55 nm)** standard-cell library,
using the vendor flow at `/opt/tools/r2g_synth`.

## How to run

```sh
bash syn/run_ics55_synth.sh
```

Environment overrides:

| Variable | Default | Meaning |
|---|---|---|
| `R2G` | `/opt/tools/r2g_synth` | vendor flow root (must contain `lib_ics55/`) |
| `OUT` | `syn/build` | output directory |
| `CLK_FREQ_MHZ` | `100` | target clock for ABC |

The script drives `$R2G/yosys/scripts/yosys_synthesis.tcl`, the same script the
SimpleEdge AiSoC flow uses, with the same libraries and tie cells:

- `lib_ics55/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib`
- `lib_ics55/ics55_LLSC_H7CR_ss_rcworst_1p08_125_nldm.lib`
- tie cells `TIELOH7R` / `TIEHIH7R`

Pipeline: `read_slang` → `proc`/`opt`/`fsm`/`memory_map` → `dfflibmap` → `abc`
→ `hilomap` → `write_verilog`.

## Why `Fes32SynthTop` exists

The synthesis top is [`Fes32SynthTop.sv`](Fes32SynthTop.sv), a thin wrapper that
instantiates `Fes32` with reduced memory:

| | simulation default | synthesis |
|---|---:|---:|
| `FLASH_WORDS` | 65536 (256 KB) | 2048 (8 KB) |
| `SRAM_WORDS` | 16384 (64 KB) | 1024 (4 KB) |
| memory flops | 2,621,440 | 98,304 |

`lib_ics55` ships **standard cells only** — there is no SRAM macro library wired
into the flow, so `memory_map` turns every inferred word into 32 flip-flops. The
simulation defaults would need 2.6 M flops, which is not a realisable cell count.
This is an artefact of the flow setup, not of the design: a real implementation
uses SRAM macros for flash and SRAM.

Reducing the depth keeps the design structurally identical — same ports, same
logic, same control — only the memory depth changes, so high addresses alias
instead of decoding. Nothing in the simulator path changes: `designs/fes32/tests`
and the FrameTop test all run on the full-size defaults.

### SRAM macro status

An ICS55 SRAM macro is available separately:

```
ics55_ecos_sram_1024x80_m4   (1024 x 80, LEF + Liberty + Verilog)
```

It cannot be picked up automatically by Yosys `memory_libmap`, because its
Liberty `memory()` group only declares

```
memory() {
  type : ram;
  address_width : 10 ;
  word_width : 80 ;
}
```

with `memory_read()` on the `Q` bus and **no `memory_write()` group**. Yosys needs
the write-side groups (`memory_write()` on `D`/`WEB`/`CEB`/`GWEB`) to infer how to
drive the macro, so the memories still fall back to flip-flops. Using the macro
requires instantiating it explicitly in the RTL.

## Result

Run on `fireflyer@192.168.100.103`, ICS55, 100 MHz target:

| Metric | Value |
|---|---:|
| Cells | 321,444 |
| Flip-flops (`DFFQX1H7R`) | 100,770 |
| Area | 1,149,001 µm² (≈1.15 mm²) |
| Netlist | `syn/build/Fes32SynthTop_synth.v`, 48.8 MB |
| `check` | 0 problems |
| ABC runtime | 1553 s |

Roughly 100 K of the 100,770 flip-flops are the two memories; the remaining
~2.5 K are the picorv32 pipeline, the GPIO registers and the memory interface.

## Outputs (`syn/build/`)

| File | Contents |
|---|---|
| `Fes32SynthTop_synth.v` | gate-level netlist (standard cells only) |
| `synth_stat.json` | final cell/area statistics per module |
| `generic_stat.json` | pre-mapping generic cell statistics |
| `timing_cell_count.rpt` | DFF / latch counts |
| `synth_check.rpt` | Yosys `check` result (0 problems) |
| `synth.log` | full flow log |

`syn/build/` is git-ignored — regenerate with the script.
