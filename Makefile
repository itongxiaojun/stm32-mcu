# ========================================================================
# Makefile for STM32-Compatible MCU (mpc-frame)
# ========================================================================

.PHONY: all sim synth clean sim-unit help

# Tool paths
IVERILOG ?= iverilog
VVP      ?= vvp
YOSYS    ?= yosys
PYTHON   ?= python3

# Directories
DESIGN   := designs/stm32-mcu
RTL      := $(DESIGN)/rtl
TESTS    := $(DESIGN)/tests
SYN      := syn
PNR      := pnr

# Source files (mpc-frame design package)
PICORV32 := picorv32/picorv32.v
RISCV    := $(RTL)/riscv_core.v
TOP      := $(RTL)/Stm32Mcu.sv
TESTBENCH:= $(TESTS)/Stm32McuTb.sv

# Output files
SIM_VVP  := stm32_mcu_sim.vvp
SYN_V    := $(SYN)/stm32_mcu_synth.v
VCD      := /tmp/Stm32McuTb.vcd

# Registry (for frame build)
MPC_FRAME := ../mpc-frame
REGISTRY  := $(MPC_FRAME)/rtl/generated/FrameDesignRegistry.sv

# ========================================================================
# Default target
# ========================================================================

all: sim synth

# ========================================================================
# Unit Simulation
# ========================================================================

sim: $(SIM_VVP)
	$(VVP) $(SIM_VVP)

$(SIM_VVP): $(PICORV32) $(RISCV) $(TOP) $(TESTBENCH)
	@echo "=== Compiling with Icarus Verilog ==="
	$(IVERILOG) -g2012 -o $@ $(PICORV32) $(RISCV) $(TOP) $(TESTBENCH)

# ========================================================================
# Design Registry (validate / build)
# ========================================================================

validate:
	@echo "=== Validating design manifest ==="
	$(PYTHON) $(MPC_FRAME)/scripts/design_registry.py validate-design \
		--design $(DESIGN)/design.json

design-build:
	@echo "=== Building design for FrameTop ==="
	$(PYTHON) $(MPC_FRAME)/scripts/design_registry.py design-build \
		--design $(DESIGN)/design.json \
		--output-dir build/stm32-mcu \
		--kind unit

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
	rm -rf build/

# ========================================================================
# Help
# ========================================================================

help:
	@echo "Targets:"
	@echo "  all         - Run simulation and synthesis"
	@echo "  sim         - Compile and run unit simulation"
	@echo "  validate    - Validate design.json manifest"
	@echo "  design-build - Build design for mpc-frame integration"
	@echo "  synth       - Run Yosys synthesis"
	@echo "  clean       - Remove build artifacts"
	@echo "  help        - Show this help message"
