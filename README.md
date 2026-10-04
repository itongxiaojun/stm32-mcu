# FES32 — STM32-Compatible MCU on IIC-OSIC-TOOLS

![CI](https://github.com/redoop/stm32-mcu/workflows/CI/badge.svg)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
![CPU](https://img.shields.io/badge/CPU-picorv32%20RV32IMC-FF3F34)
![PDK](https://img.shields.io/badge/PDK-SkyWater%20130nm-4CC9F0)
![Tools](https://img.shields.io/badge/EDA-Yosys%20%7C%20LibreLane%20%7C%20Magic-green)

> A fully synthesizable, verifiable STM32-compatible microcontroller
> built with open-source EDA tools inside the [IIC-OSIC-TOOLS](https://github.com/iic-jku/iic-osic-tools) container.
> Developed using **Test-Driven Development (TDD)** methodology.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Verification Results](#verification-results)
- [Project Structure](#project-structure)
- [License](#license)

## Overview

This project implements an STM32F103-compatible microcontroller using open-source
EDA tools. The design targets the [mpc-frame](https://github.com/iic-jku/mpc-frame)
platform for multi-design chip integration via `FrameTop`.

**Project name: `FES32`** (Faireye Semi 32-bit MCU family). The RTL top module is
`Fes32` and the design package lives in [`designs/fes32/`](designs/fes32/).

> **Note:** the repository slug is still `stm32-mcu` (pending rename to `fes32`),
> so the clone URL and CI badge above still point at the old slug. Project, RTL
> module and design package are all `FES32` / `Fes32` / `fes32`.

> `STM32` and `STM32F103` are trademarks of STMicroelectronics. References to them
> in this repository are **descriptive statements of interface compatibility** only.
> This project is an independent implementation and is not affiliated with,
> sponsored by, or endorsed by STMicroelectronics.

### Key Features

- **Open-Source CPU**: picorv32 RISC-V RV32IMC core (ISC license)
- **Open-Source EDA**: Yosys (synthesis), LibreLane (P&R), Magic (GDS2)
- **Open-Source PDK**: SkyWater 130nm CMOS (`sky130_fd_sc_hd`)
- **TDD Verification**: Icarus Verilog simulation — 10/10 tests passing
- **FrameTop Compatible**: 7-bit design ID, 66-bit payload IO interface

## Architecture

### Fes32 — mpc-frame User Design

The `Fes32` module wraps picorv32 + peripherals into the mpc-frame contract:

```
┌──────────────────────────────────────┐
│            Fes32                   │
│                                       │
│  clock  ─────────────────────────────►│
│  reset  ─────────────────────────────►│
│  io_in[65:0]  ◄──────────────────────│
│  io_out[65:0] ───────────────────────►│
│  io_oe[65:0]  ───────────────────────►│
└──────────────────────────────────────┘
         │ picorv32 (via riscv_core)
         ▼
    ┌──────────┐
    │ picorv32 │  RV32IMC
    └──────────┘
```

### IO Mapping (66-bit payload)

| Payload bit | Purpose | Direction |
|---|---|---|
| `[0]` | UART TX | out |
| `[1]` | UART RX | in |
| `[2]` | SPI SCLK | out |
| `[3]` | SPI MOSI | out |
| `[4]` | SPI MISO | in |
| `[5]` | SPI CS_n | out |
| `[6:7]` | SWD CLK/DATA | inout |
| `[23:8]` | GPIO ODR[15:0] | out |
| `[39:24]` | GPIO OE[15:0] | out |
| `[54:39]` | GPIO IDR[15:0] | in |
| `[65:55]` | Reserved | — |

## Quick Start

### Prerequisites

The IIC-OSIC-TOOLS container must be running. If not installed:

```bash
git clone https://github.com/iic-jku/iic-osic-tools.git
cd iic-osic-tools
./install.sh
./start_shell.sh
```

Then clone this repository inside the container:

```bash
cd /foss/designs
git clone --recurse-submodules https://github.com/redoop/stm32-mcu.git
cd stm32-mcu
```

### 1. Unit Simulation (Icarus Verilog)

```bash
# Compile
iverilog -g2012 -o fes32_sim.vvp \
  /foss/picorv32/picorv32.v \
  designs/fes32/rtl/riscv_core.v \
  designs/fes32/rtl/Fes32.sv \
  designs/fes32/tests/Fes32Tb.sv

# Run
vvp fes32_sim.vvp
```

### 2. Synthesis (Yosys)

```bash
yosys -s syn/synth.ys
```

Produces `syn/fes32_synth.v` — the technology-mapped gate-level netlist.

### 3. mpc-frame Integration

```bash
# Validate design manifest
python3 ../mpc-frame/scripts/design_registry.py validate-design \
  --design designs/fes32/design.json

# Build for FrameTop
python3 ../mpc-frame/scripts/design_registry.py design-build \
  --design designs/fes32/design.json \
  --output-dir build/fes32 \
  --kind unit \
  --registry ../mpc-frame/designs/registry.json
```

## Verification Results

All 10 unit tests pass using Icarus Verilog:

| # | Test | Description | Result |
|---|------|-------------|--------|
| 1 | Flash Write/Read | Flash memory access | ✅ PASSED |
| 2 | SRAM Write/Read | SRAM memory access | ✅ PASSED |
| 3 | GPIO ODR Write | GPIO output data register | ✅ PASSED |
| 4 | GPIO Direction | GPIO direction (CRL/CRH) | ✅ PASSED |
| 5 | GPIO ODR Readback | GPIO readback | ✅ PASSED |
| 6 | UART TX OE | USART1 TX output enable | ✅ PASSED |
| 7 | SPI CLK OE | SPI1 clock output enable | ✅ PASSED |
| 8 | SWD High-Z | SWD pins tri-state | ✅ PASSED |
| 9 | GPIO ODR on io_out | GPIO on FrameTop IO | ✅ PASSED |
| 10 | GPIO OE Config | GPIO OE from CRL/CRH | ✅ PASSED |

## Project Structure

```
stm32-mcu/                     # repository slug (pending rename to fes32)
├── README.md                  # This file
├── .gitignore                 # Ignore build artifacts
├── .gitmodules                # Git submodule configuration
├── Makefile                   # Build targets (sim, synth, validate)
├── LICENSE                    # Apache-2.0 license
├── requirements.txt           # cocotb dependencies
├── designs/
│   └── fes32/            # mpc-frame design package
│       ├── design.json        # Manifest (id=1, IO_WIDTH=66)
│       ├── README.md          # Chinese design doc
│       ├── README.en.md       # English design doc
│       ├── rtl/
│       │   ├── Fes32.sv   # Frame adapter (top)
│       │   └── riscv_core.v  # picorv32 wrapper
│       └── tests/
│           └── Fes32Tb.sv # Unit testbench (10 tests)
├── rtl/
│   ├── riscv_core.v          # picorv32 wrapper (shared)
│   └── stm32_top.v           # Legacy top-level (not used by Fes32)
├── syn/
│   └── synth.ys              # Yosys synthesis script
├── pnr/                       # Place & route config (LibreLane)
├── picorv32/                  # picorv32 RISC-V core (git submodule)
└── .github/workflows/ci.yml   # CI: simulation + synthesis
```

## Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| picorv32 | latest | RISC-V CPU core |
| Yosys | 0.67+ | RTL synthesis |
| Icarus Verilog | 11.0+ | Functional simulation |
| LibreLane | latest | Place & route |
| Magic | 8.22+ | GDS2 layout viewer |
| SkyWater PDK | sky130A | 130nm CMOS PDK |
| IIC-OSIC-TOOLS | latest | Container with all EDA tools |

## License

Apache License 2.0 — see [LICENSE](LICENSE)

picorv32 is ISC licensed — see [picorv32/COPYING](picorv32/COPYING)

## Acknowledgments

- **IIC-OSIC-TOOLS** — [JKU Dept. for Integrated Circuits](https://iic.jku.at)
- **picorv32** — Clifford Wolf, OpenCores community
- **Yosys** — Claire Xenia Wolf
- **LibreLane / OpenROAD** — The OpenROAD Project
- **SkyWater PDK** — SkyWater Technology / Google
- **Icarus Verilog** — Stephen Williams
- **Magic** — Tim Edwards
