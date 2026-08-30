# ========================================================================
# Makefile for STM32-Compatible MCU
# ========================================================================

.PHONY: all sim synth clean sim-cocotb help

# Tool paths
IVERILOG ?= iverilog
VVP      ?= vvp
YOSYS    ?= yosys
COCOTB   ?= cocotb
PYTHON   ?= python3

# Directories
RTL      := rtl
TB       := tb
SYN      := syn
PNR      := pnr

# Source files
PICORV32 := /foss/picorv32/picorv32.v
RISCV    := $(RTL)/riscv_core.v
TOP      := $(RTL)/stm32_top.v
TESTBENCH:= $(TB)/stm32_top_tb.v

# Output files
SIM_VVP  := stm32_top_sim.vvp
SYN_V    := $(SYN)/stm32_top_synth.v
VCD      := /tmp/stm32_top_tb.vcd

# ========================================================================
# Default target
# ========================================================================

all: sim synth

# ========================================================================
# Simulation
# ========================================================================

sim: $(SIM_VVP)
	$(VVP) $(SIM_VVP)

$(SIM_VVP): $(PICORV32) $(RISCV) $(TOP) $(TESTBENCH)
	@echo "=== Compiling with Icarus Verilog ==="
	$(IVERILOG) -g2012 -o $@ $(PICORV32) $(RISCV) $(TOP) $(TESTBENCH)

# ========================================================================
# cocotb Simulation
# ========================================================================

sim-cocotb:
	@echo "=== Running cocotb tests ==="
	cd $(TB) && $(PYTHON) -m cocotb test -module test_gpio_cocotb -top stm32_top

# ========================================================================
# Synthesis
# ========================================================================

synth: $(SYN_V)

$(SYN_V): $(PICORV32) $(RISCV) $(TOP)
	@echo "=== Running Yosys synthesis ==="
	$(YOSYS) -s $(SYN)/synth.ys

# ========================================================================
# Clean
# ========================================================================

clean:
	rm -f $(SIM_VVP) $(VCD) $(SYN_V)
	rm -f *.vvp *.vcd

# ========================================================================
# Help
# ========================================================================

help:
	@echo "Targets:"
	@echo "  all         - Run simulation and synthesis"
	@echo "  sim         - Compile and run Icarus Verilog simulation"
	@echo "  sim-cocotb  - Run cocotb tests"
	@echo "  synth       - Run Yosys synthesis"
	@echo "  clean       - Remove build artifacts"
	@echo "  help        - Show this help message"
