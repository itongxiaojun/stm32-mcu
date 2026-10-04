# FES32 Frame Design

Frame design wrapper for the STM32F103-compatible MCU.

## Interface

| Signal | Direction | Description |
|---|---|---|
| `clock` | in | Clock |
| `reset` | in | Reset (active high) |
| `io_in[65:0]` | in | Read IO from FrameTop |
| `io_out[65:0]` | out | Drive IO to FrameTop |
| `io_oe[65:0]` | out | IO output enable |

## IO Mapping

| Payload bit | Purpose | Direction |
|---|---|---|
| `[0]` | UART TX | out |
| `[1]` | UART RX | in |
| `[2]` | SPI SCLK | out |
| `[3]` | SPI MOSI | out |
| `[4]` | SPI MISO | in |
| `[5]` | SPI CS_n | out |
| `[6:7]` | SWD CLK/DATA | inout |
| `[22:7]` | GPIO ODR[15:0] | out |
| `[38:23]` | GPIO OE[15:0] | out |
| `[54:39]` | GPIO IDR[15:0] | in |
| `[65:55]` | Reserved | — |

## Peripherals

- GPIOA: 16-pin GPIO (CRL/CRH/IDR/ODR/BSRR/BRR)
- USART1: UART (TX/RX, 9600bps)
- SPI1: SPI master (CPOL/CPHA configurable)
- TIM2: 16-bit timer
- NVIC: Interrupt controller
- Flash: 256KB
- SRAM: 64KB

## Tests

```sh
# Unit test
iverilog -g2012 -o Fes32Tb.vvp \
  rtl/Fes32.sv rtl/*.v tests/Fes32Tb.sv \
  && vvp Fes32Tb.vvp

# FrameTop integration test
python3 ../../../../mpc-frame/scripts/design_registry.py design-build \
  --design design.json \
  --output-dir build \
  --kind frame \
  --registry ../../../../mpc-frame/designs/registry.json
```
