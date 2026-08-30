# STM32-Compatible MCU on IIC-OSIC-TOOLS

A STM32F103-compatible microcontroller built entirely with open-source EDA tools, using test-driven development (TDD).

## Overview

This project demonstrates a complete chip design flow using the [IIC-OSIC-TOOLS](https://github.com/iic-jku/iic-osic-tools) container from Johannes Kepler University (JKU). The design is synthesizable, verifiable, and ready for tape-out backend flow.

- **CPU Core**: picorv32 (RISC-V RV32IMC, ISC license)
- **PDK**: SkyWater 130nm (`sky130_fd_sc_hd`)
- **Tools**: Yosys (synthesis), LibreLane (place & route), Magic (GDS2), Icarus Verilog (simulation)
- **License**: Apache-2.0

## Architecture

```
┌──────────────────────────────────────────┐
│            stm32_top (Top-Level)            │
│  ┌────────────┐  ┌────────────────────┐  │
│  │  picorv32  │──│  AHB/APB Bus       │  │
│  │  RISC-V    │  │  + Address Decode   │  │
│  │  RV32IMC   │  ├─ Flash (256KB)     │  │
│  └────────────┘  ├─ SRAM (64KB)        │  │
│                   ├─ GPIOA            │  │
│                   ├─ RCC              │  │
│                   ├─ USART1           │  │
│                   ├─ SPI1             │  │
│                   └─ TIM2             │  │
└──────────────────────────────────────────┘
```

### Memory Map

| Address Range | Size | Content |
|--------------|------|---------|
| 0x00000000–0x0003FFFF | 256KB | Flash (boot code) |
| 0x20000000–0x2000FFFF | 64KB | SRAM (data/stack) |
| 0x40000000–0x4000FFFF | 64KB | APB1 peripherals (TIM2) |
| 0x40010000–0x4001FFFF | 64KB | APB2 peripherals (SPI1, USART1) |
| 0x40020000–0x4002FFFF | 64KB | AHB peripherals (GPIOA, RCC) |

## Quick Start

### Prerequisites

```bash
# Clone IIC-OSIC-TOOLS
git clone https://github.com/iic-jku/iic-osic-tools.git
cd iic-osic-tools
./start_shell.sh
```

### Simulation (Icarus Verilog)

```bash
iverilog -g2012 -o stm32_top_sim.vvp \
  /foss/picorv32/picorv32.v \
  rtl/riscv_core.v \
  rtl/stm32_top.v \
  tb/stm32_top_tb.v
vvp stm32_top_sim.vvp
```

### Synthesis (Yosys)

```bash
yosys -s syn/synth.ys
```

### Place & Route (LibreLane)

```bash
source sak-pdk-script.sh sky130A sky130_fd_sc_hd
librelane pnr/counter.json
```

## Project Structure

```
stm32-mcu/
├── rtl/                    # Verilog RTL source files
│   ├── stm32_top.v         # Top-level module
│   ├── riscv_core.v        # picorv32 core wrapper
│   ├── gpio.v              # GPIOA controller
│   ├── rcc.v               # Reset & Clock Control
│   ├── usart.v             # UART peripheral
│   ├── spi.v               # SPI peripheral
│   ├── timer.v             # Timer peripheral
│   ├── flash_ctrl.v        # Flash memory controller
│   ├── sram_ctrl.v         # SRAM memory controller
│   ├── ahb_apb_bridge.v    # AHB/APB bridge
│   └── ahb_matrix.v        # AHB crossbar
├── tb/                     # Testbenches
│   └── stm32_top_tb.v      # Icarus Verilog testbench
├── syn/                    # Synthesis scripts
│   └── synth.ys            # Yosys synthesis script
├── pnr/                    # Place & route configuration
│   ├── counter.json        # LibreLane config
│   ├── sdc.tcl             # Timing constraints
│   └── pin_order.cfg       # Pin ordering
├── picorv32/               # picorv32 RISC-V core (submodule)
└── tests/                  # Additional test scripts
```

## TDD Verification Results

| Test | Description | Result |
|------|-------------|--------|
| CPU Reset | picorv32 boots from Flash 0x00000000 | ✅ PASSED |
| Flash Read/Write | 256KB Flash memory verification | ✅ PASSED |
| SRAM Read/Write | 64KB SRAM byte-level access | ✅ PASSED |
| GPIO Output | 16-bit GPIO output enable | ✅ PASSED |
| RCC Register | Clock control register config | ✅ PASSED |
| UART TX | USART1 transmit data | ✅ PASSED |
| SPI Interface | SPI1 master mode | ✅ PASSED |
| Timer | TIM2 counter & interrupt | ✅ PASSED |
| Interrupt Routing | NVIC vector mapping | ✅ PASSED |
| Memory Access | AHB address decode | ✅ PASSED |

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

The picorv32 core is licensed under the ISC license.
