# stm32-mcu 接入 mpc-frame 需求文档

## 1. 背景

`stm32-mcu` 是一个 STM32F103 兼容的 MCU 设计，搭载 picorv32 RISC-V RV32IMC 核心，
包含 GPIOA、USART1、SPI1、TIM2、NVIC、Flash、SRAM 等外设。当前架构存在以下问题：

- 总线协议不一致：`stm32_top.v` 使用 picorv32 原生内存接口，而 `ahb_matrix.v`、
  `flash_ctrl.v`、`sram_ctrl.v` 有 AHB 接口但未实例化
- 外设模块游离：`gpio.v`、`usart.v`、`spi.v`、`timer.v`、`nvic.v` 存在但未被
  `stm32_top` 实例化
- 无 Frame 适配：不符合 mpc-frame 的 `clock/reset/io_in/io_out/io_oe` 用户设计契约
- 测试不完整：`stm32_top_tb.v` 的 10 个测试均为 `$display("PASSED")`，无实际断言

## 2. 目标

将 `stm32-mcu` 作为 mpc-frame 的 **用户设计 slot 1** 接入，使其可通过 `FrameTop`
统一管理，支持多设计共存、设计选择、时钟门控、复位隔离、IO 复用。

## 3. mpc-frame 契约

### 3.1 FrameTop 接口

```systemverilog
module FrameTop #(
  parameter int IO_WIDTH = 73,
  parameter int DESIGN_COUNT = 128,
  parameter int DESIGN_ID_WIDTH = 7
)(
  input  logic               clock,
  input  logic               reset,
  inout  wire [IO_WIDTH-1:0] user_io
);
```

| 分区 | 宽度 | 用途 |
|---|---|---|
| `user_io[6:0]` | 7 bit | design ID（复位期间采样） |
| `user_io[72:7]` | 66 bit | payload IO |

### 3.2 用户设计接口

```systemverilog
module UserDesign #(
  parameter int IO_WIDTH = 66
)(
  input  logic        clock,
  input  logic        reset,
  input  logic [65:0] io_in,
  output logic [65:0] io_out,
  output logic [65:0] io_oe
);
```

- `io_oe[n] = 1`：设计驱动 `io_out[n]` 到 pad
- `io_oe[n] = 0`：释放 pad 为高阻
- 所有 `io_out`/`io_oe` 位必须有确定值

### 3.3 设计选择时序

1. `reset=1` 期间，`user_io[6:0]` 采样 design ID
2. `reset` 释放后，FrameTop 使能选中设计的时钟、释放其复位
3. 运行期间修改 `user_io[6:0]` 无效，需重新复位

## 4. 外设 → IO 映射

### 4.1 信号清单

| 外设 | 信号 | 方向 | 位数 |
|---|---|---|---|
| GPIOA | `pa_in[15:0]` | in | 16 |
| GPIOA | `pa_out[15:0]` | out | 16 |
| GPIOA | `pa_oe[15:0]` | out | 16 |
| USART1 | `uart_rx` | in | 1 |
| USART1 | `uart_tx` | out | 1 |
| SPI1 | `spi_sclk` | out | 1 |
| SPI1 | `spi_mosi` | out | 1 |
| SPI1 | `spi_miso` | in | 1 |
| SPI1 | `spi_cs_n` | out | 1 |
| SWD | `swd_clk` | inout | 1 |
| SWD | `swd_data` | inout | 1 |

**合计：56 bit ≤ 66 bit ✅**

### 4.2 payload 位分配

| payload 位 | 用途 | 方向 | 对应 user_io |
|---|---|---|---|
| `[0]` | UART TX | out | `user_io[7]` |
| `[1]` | UART RX | in | `user_io[8]` |
| `[2]` | SPI SCLK | out | `user_io[9]` |
| `[3]` | SPI MOSI | out | `user_io[10]` |
| `[4]` | SPI MISO | in | `user_io[11]` |
| `[5]` | SPI CS_n | out | `user_io[12]` |
| `[6]` | SWD CLK | inout | `user_io[13]` |
| `[7]` | SWD DATA | inout | `user_io[14]` |
| `[22:7]` | GPIO ODR[15:0] 输出 | out | `user_io[29:14]` |
| `[38:23]` | GPIO OE[15:0] 输出 | out | `user_io[45:30]` |
| `[54:39]` | GPIO IDR[15:0] 输入 | in | `user_io[61:46]` |
| `[65:55]` | 保留 | — | `user_io[72:62]` |

### 4.3 Flash/PSRAM 扩展（IO 复用）

通过分时复用 SPI 引脚接入 Flash/PSRAM，不额外占用 payload bit：

| 信号 | 复用引脚 | 控制 |
|---|---|---|
| Flash SCK | `spi_sclk` (payload[2]) | `flash_en` |
| Flash CS_n | `spi_cs_n` (payload[5]) | `flash_en` |
| Flash MOSI | `spi_mosi` (payload[3]) | `flash_en` |
| Flash MISO | `spi_miso` (payload[4]) | `flash_en` |
| PSRAM SCK | `spi_sclk` (payload[2]) | `psram_en` |
| PSRAM CS_n | `spi_cs_n` (payload[5]) | `psram_en` |
| PSRAM DQ[3:0] | `gpio_pad_o[3:0]` + `gpio_pad_oe[3:0]` | `psram_en` |

## 5. 架构设计

### 5.1 模块层次

```
FrameTop (mpc-frame)
└── FrameDesignSlot1 (自动生成)
    └── Stm32Mcu (新增: rtl/stm32_mcu_frame.sv)
        ├── picorv32 (picorv32 子模块)
        ├── riscv_core (rtl/riscv_core.v)
        ├── gpio (rtl/gpio.v)
        ├── usart (rtl/usart.v)
        ├── spi (rtl/spi.v)
        ├── timer (rtl/timer.v)
        ├── nvic (rtl/nvic.v)
        ├── flash_ctrl (rtl/flash_ctrl.v)
        ├── sram_ctrl (rtl/sram_ctrl.v)
        ├── ahb_matrix (rtl/ahb_matrix.v)
        └── ahb_apb_bridge (rtl/ahb_apb_bridge.v)
```

### 5.2 关键设计决策

| 决策 | 方案 | 理由 |
|---|---|---|
| 时钟 | 单时钟 `clock`，由 FrameTop 门控 | mpc-frame 约束 |
| 复位 | `reset` 高有效，异步 | mpc-frame 约束 |
| 总线 | 保留 picorv32 原生接口，内部桥接 APB | 最小改动 picorv32 |
| GPIO | 复用 `gpio.v` 模块 | 已有完整寄存器集 |
| UART | 复用 `usart.v` 模块 | 已有完整 FSM |
| SPI | 复用 `spi.v` 模块 | 已有 CPOL/CPHA 支持 |
| Timer | 复用 `timer.v` 模块 | 已有 PWM/捕获支持 |
| NVIC | 实例化 `nvic.v`，连接 picorv32 IRQ | 修复当前 top 绕过 NVIC 的问题 |
| Flash/SRAM | 实例化 `flash_ctrl.v`/`sram_ctrl.v` | 替代当前顶层内联逻辑 |

## 6. 实施计划

| 阶段 | 内容 | 优先级 | 验收条件 |
|---|---|---|---|
| 1 | 新建 `Stm32Mcu` 封装，绑定 GPIO/UART/SPI/SWD 到 `io_in/io_out/io_oe` | P0 | `make check DESIGN=designs/stm32-mcu` 通过 |
| 2 | 创建 `design.json` manifest | P0 | `validate-design` 通过 |
| 3 | 实现 SPI Flash 接口（Quad I/O，7 bit） | P1 | `make frame-test TEST=frame` 通过 |
| 4 | 编写 `Stm32McuTb.sv` 独立单元测试 | P1 | 8 个测试项全部通过 |
| 5 | 编写 `FrameStm32McuTb.sv` FrameTop 集成测试 | P1 | contention 检测通过，无 `$fatal` |
| 6 | 实例化 `gpio.v`/`usart.v`/`spi.v`/`timer.v` 替代内联逻辑 | P2 | 功能等价，代码行数减少 30% |
| 7 | 添加 Makefile / CI 目标 | P2 | `make frame-check` / `make frame-test` 可执行 |
| 8 | 实现 PSRAM 接口（IO 复用方案） | P2 | 可访问 PSRAM 地址空间 |
| 9 | 实例化 `nvic.v` 修复中断路由 | P2 | 中断可正确路由到 picorv32 |
| 10 | 补充 Flash/PSRAM 控制器寄存器 | P3 | 完整 STM32 Flash 寄存器集 |

## 7. 风险

| 风险 | 影响 | 缓解措施 |
|---|---|---|
| IO 数量超预算 | 无法接入 FrameTop | 方案 D（释放 SWD）+ IO 复用 |
| 双向 IO 争用 | 仿真 `$fatal` | SWD 的 `io_oe` 设为 0，testbench 不驱动 |
| 复位域不匹配 | 设计无法启动 | `reset = !resetn`，异步取反 |
| picorv32 子模块未初始化 | 综合/仿真失败 | `git submodule update --init` |
| NVIC 未连接 | 中断不工作 | 阶段 9 修复 |
| Flash/PSRAM 时序 | 仿真通过但硬件失败 | 阶段 10 补充控制器寄存器 |
