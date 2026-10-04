# stm32-mcu Frame Design

STM32F103 兼容 MCU 的 mpc-frame 用户设计封装。

## 接口

| 信号 | 方向 | 说明 |
|---|---|---|
| `clock` | in | 时钟 |
| `reset` | in | 复位（高有效） |
| `io_in[65:0]` | in | 从 FrameTop 读取 IO |
| `io_out[65:0]` | out | 驱动到 FrameTop 的 IO |
| `io_oe[65:0]` | out | IO 输出使能 |

## IO 映射

| payload 位 | 用途 | 方向 |
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
| `[65:55]` | 保留 | — |

## 外设

- GPIOA: 16-pin GPIO（CRL/CRH/IDR/ODR/BSRR/BRR）
- USART1: UART（TX/RX，9600bps）
- SPI1: SPI master（CPOL/CPHA 可配置）
- TIM2: 16-bit 定时器
- NVIC: 中断控制器
- Flash: 256KB
- SRAM: 64KB

## 测试

```sh
# 独立单元测试
iverilog -g2012 -o Stm32McuTb.vvp \
  rtl/Stm32Mcu.sv rtl/*.v tests/Stm32McuTb.sv \
  && vvp Stm32McuTb.vvp

# FrameTop 集成测试
python3 ../../../../mpc-frame/scripts/design_registry.py design-build \
  --design design.json \
  --output-dir build \
  --kind frame \
  --registry ../../../../mpc-frame/designs/registry.json
```
