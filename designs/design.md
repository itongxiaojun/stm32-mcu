# stm32-mcu 接入 mpc-frame 设计文档

## 1. Stm32Mcu 封装设计

### 1.1 接口定义

```systemverilog
module Stm32Mcu #(
    parameter int IO_WIDTH = 66
)(
    input  logic        clock,
    input  logic        reset,
    input  logic [65:0] io_in,
    output logic [65:0] io_out,
    output logic [65:0] io_oe
);
```

### 1.2 内部信号

```systemverilog
// CPU 总线
wire        mem_valid;
wire        mem_instr;
wire        mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
wire [31:0] mem_rdata;
wire        trap;

// 中断
wire        tim2_irq;
wire        usart1_irq;
wire        spi1_irq;
wire        gpio_irq;
wire        flash_irq;

// 内部复位
logic resetn;
assign resetn = !reset;
```

### 1.3 IO 绑定

```systemverilog
// UART
assign io_out[0]  = uart_tx;
assign io_oe[0]   = 1'b1;
assign uart_rx    = io_in[1];
assign io_oe[1]   = 1'b0;

// SPI
assign io_out[2]  = spi_sclk;
assign io_out[3]  = spi_mosi;
assign io_out[5]  = spi_cs_n;
assign io_oe[2]   = 1'b1;
assign io_oe[3]   = 1'b1;
assign io_oe[5]   = 1'b1;
assign spi_miso   = io_in[4];
assign io_oe[4]   = 1'b0;

// SWD (三态)
assign io_oe[6]   = 1'b0;  // SWD CLK
assign io_oe[7]   = 1'b0;  // SWD DATA

// GPIO ODR 输出
assign io_out[22:7]  = gpio_odr;
assign io_oe[22:7]   = 1'b1;

// GPIO OE 输出
assign io_out[38:23] = gpio_oe;
assign io_oe[38:23]  = 1'b1;

// GPIO IDR 输入
assign io_oe[54:39]  = 1'b0;  // 高阻，输入
```

### 1.4 模块实例化

```systemverilog
// RISC-V 核心
riscv_core #(
    .RESET_ADDR(32'h00000000),
    .IRQ_ADDR  (32'h00000010),
    .STACK_ADDR(32'h2000FFFF)
) riscv_core_inst (
    .clk      (clock),
    .resetn   (resetn),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr (mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .irq      ({26'd0, flash_irq, gpio_irq, spi1_irq, usart1_irq, tim2_irq}),
    .trap     (trap)
);

// GPIO
gpio gpio_inst (
    .clk      (clock),
    .resetn   (resetn),
    .Psel     (sel_gpio),
    .Penable  (1'b1),
    .Pwrite   (mem_wstrb != 4'd0),
    .Paddr    (mem_addr),
    .Pwdata   (mem_wdata),
    .Prdata   (),
    .pad_i    (io_in[54:39]),   // GPIO IDR
    .pad_o    (gpio_pad_o),
    .pad_oe   (gpio_pad_oe)
);

// USART
usart usart_inst (
    .clk      (clock),
    .resetn   (resetn),
    .Psel     (sel_usart1),
    .Penable  (1'b1),
    .Pwrite   (mem_wstrb != 4'd0),
    .Paddr    (mem_addr),
    .Pwdata   (mem_wdata),
    .Prdata   (),
    .rx_pin   (io_in[1]),
    .tx_pin   (uart_tx),
    .tx_busy  (),
    .irq      (usart1_irq)
);

// SPI
spi spi_inst (
    .clk      (clock),
    .resetn   (resetn),
    .Psel     (sel_spi1),
    .Penable  (1'b1),
    .Pwrite   (mem_wstrb != 4'd0),
    .Paddr    (mem_addr),
    .Pwdata   (mem_wdata),
    .Prdata   (),
    .sclk     (spi_sclk),
    .mosi     (spi_mosi),
    .miso     (io_in[4]),
    .cs_n     (spi_cs_n),
    .irq      (spi1_irq)
);

// Timer
timer timer_inst (
    .clk      (clock),
    .resetn   (resetn),
    .Psel     (sel_tim2),
    .Penable  (1'b1),
    .Pwrite   (mem_wstrb != 4'd0),
    .Paddr    (mem_addr),
    .Pwdata   (mem_wdata),
    .Prdata   (),
    .cnt_overflow (),
    .irq      (tim2_irq)
);

// NVIC
nvic nvic_inst (
    .clk       (clock),
    .resetn    (resetn),
    .irq_src   ({24'd0, flash_irq, gpio_irq, spi1_irq, usart1_irq, tim2_irq}),
    .irq_en    (32'hffffffff),
    .cpu_irq   (cpu_irq),
    .cpu_irq_ack(),
    .cpu_irq_id(),
    .sys_reset (1'b0),
    .nmi_irq   ()
);
```

## 2. stm32_top.v 模块化重构

### 2.1 改动前

```
stm32_top.v (276 行)
├── picorv32 包装 (riscv_core)
├── Flash 内存数组 + 读逻辑 (内联)
├── SRAM 内存数组 + 字节写 (内联)
├── GPIO 寄存器 + 输出驱动 (内联)
├── RCC 寄存器 (内联)
├── 地址解码 (内联)
└── 读多路复用 (内联)
```

### 2.2 改动后

```
stm32_top.v (约 150 行)
├── riscv_core (picorv32 包装)
├── flash_ctrl (实例化)
├── sram_ctrl (实例化)
├── gpio (实例化)
├── rcc (实例化)
├── ahb_matrix (实例化)
└── apb_bridge (实例化)
```

### 2.3 改动细节

1. **Flash**：将 `flash_mem` 数组 + 读逻辑移入 `flash_ctrl` 实例
2. **SRAM**：将 `sram_mem` 数组 + 字节写逻辑移入 `sram_ctrl` 实例
3. **GPIO**：将寄存器文件 + 输出驱动移入 `gpio` 实例
4. **RCC**：将寄存器文件移入 `rcc` 实例
5. **地址解码**：改用 `ahb_matrix` + `apb_bridge`
6. **读多路复用**：由 `ahb_matrix` 自动处理

## 3. NVIC 连接修复

### 3.1 当前问题

`stm32_top.v` 的中断直接连接到 picorv32 的 `irq` 输入，绕过了 `nvic.v`。

### 3.2 修复方案

```systemverilog
// 连接 NVIC
nvic nvic_inst (
    .clk       (clock),
    .resetn    (resetn),
    .irq_src   ({24'd0, flash_irq, gpio_irq, spi1_irq, usart1_irq, tim2_irq}),
    .irq_en    (32'hffffffff),
    .cpu_irq   (cpu_irq),
    .cpu_irq_ack(),
    .cpu_irq_id(),
    .sys_reset (1'b0),
    .nmi_irq   ()
);
```

## 4. Flash/PSRAM 接口（IO 复用）

### 4.1 复用逻辑

```systemverilog
// IO 复用：Flash/PSRAM 分时共享 SPI 引脚
assign flash_sck = flash_en ? io_out[2] : 1'bz;
assign flash_cs  = flash_en ? io_out[5] : 1'bz;
assign psram_sck = psram_en ? io_out[2] : 1'bz;
assign psram_cs  = psram_en ? io_out[5] : 1'bz;

// PSRAM DQ 复用 GPIO 引脚
assign psram_dq_o = psram_en ? gpio_pad_o[3:0] : 4'bzzzz;
assign psram_dq_oe = psram_en ? gpio_pad_oe[3:0] : 4'b0000;
assign psram_dq_i = io_in[61:58];
```

### 4.2 切换控制

`flash_en`/`psram_en` 互斥，由地址解码器在访问 Flash/PSRAM 寄存器时自动切换。

## 5. 测试设计

### 5.1 独立单元测试

| 测试项 | 描述 | 断言 |
|---|---|---|
| 复位后 GPIO | 读取 IDR | 默认为 0x0000 |
| GPIO 输出 | 写 ODR = 0xFFFF | ODR == 0xFFFF |
| GPIO 方向 | 写 CRL = 0x33333333 | pad_oe == 16'hFFFF |
| UART TX | 写 DR = 0x41 | uart_tx 发送 0x41 |
| SPI 发送 | 写 DR = 0x55 | mosi 移位 0x55 |
| Timer 启动 | 写 CNT = 0, ARR = 100, CEN=1 | 100 个时钟后 UIF=1 |
| Flash 读 | 写 Flash[0] = 0xDEADBEEF | 读回 0xDEADBEEF |
| SRAM 读写 | 写 SRAM[0] = 0xCAFE, 读回 | == 0xCAFE |

### 5.2 FrameTop 集成测试

1. **设计选择**：验证 design ID 选择时序
2. **UART 回环**：驱动 `io_in[1]`（RX），检查 `io_out[0]`（TX）
3. **SPI 通信**：驱动 `io_in[4]`（MISO），检查 `io_out[2:3]`（CLK/MOSI）
4. **GPIO 读写**：写 `io_out[22:7]`（ODR），检查 `io_in[54:39]`（IDR）

## 6. 文件清单

| 文件 | 操作 | 说明 |
|---|---|---|
| `rtl/stm32_mcu_frame.sv` | 新增 | Frame 适配封装 |
| `rtl/stm32_top.v` | 修改 | 模块化重构 |
| `rtl/riscv_core.v` | 修改 | NVIC 连接 |
| `designs/stm32-mcu/design.json` | 新增 | manifest |
| `designs/stm32-mcu/rtl/Stm32Mcu.sv` | 新增 | 用户设计 RTL |
| `designs/stm32-mcu/tests/Stm32McuTb.sv` | 新增 | 单元测试 |
| `designs/stm32-mcu/tests/FrameStm32McuTb.sv` | 新增 | FrameTop 集成测试 |
| `Makefile` | 修改 | 新增 frame 目标 |
| `.github/workflows/ci.yml` | 修改 | 新增 frame-check job |
