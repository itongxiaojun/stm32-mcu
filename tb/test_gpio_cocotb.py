#!/usr/bin/env python3
"""
cocotb testbench for STM32-compatible MCU GPIO peripheral.
Tests GPIO input/output, BSRR, BRR, and configuration registers.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.result import TestFailure


class GPIO_Tester:
    """Helper class for testing the GPIO peripheral."""

    def __init__(self, dut):
        self.dut = dut

    async def reset(self):
        """Reset the design."""
        self.dut.resetn.value = 0
        await Timer(100, units='ns')
        self.dut.resetn.value = 1
        await Timer(100, units='ns')

    async def write_reg(self, addr, value):
        """Write to a GPIO register."""
        self.dut.Paddr.value = addr
        self.dut.Pwdata.value = value
        self.dut.Pwrite.value = 1
        self.dut.Psel.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.Psel.value = 0
        await RisingEdge(self.dut.clk)

    async def read_reg(self, addr):
        """Read from a GPIO register."""
        self.dut.Paddr.value = addr
        self.dut.Pwrite.value = 0
        self.dut.Psel.value = 1
        await RisingEdge(self.dut.clk)
        value = self.dut.Prdata.value
        self.dut.Psel.value = 0
        await RisingEdge(self.dut.clk)
        return int(value)

    async def check_gpio_output(self, expected):
        """Check that GPIO output matches expected value."""
        await RisingEdge(self.dut.clk)
        actual = int(self.dut.gpio_out.value)
        if actual != expected:
            raise TestFailure(f"GPIO output mismatch: expected {expected:#06x}, got {actual:#06x}")


@cocotb.test()
async def test_gpio_output(dut):
    """Test GPIO output functionality."""
    tester = GPIO_Tester(dut)

    # Clock generation: 100 MHz
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())

    await tester.reset()

    # Test 1: Set all pins as output and drive high
    await tester.write_reg(0x40020000, 0x44444444)  # CRL: output mode
    await tester.write_reg(0x40020004, 0x44444444)  # CRH: output mode
    await tester.write_reg(0x4002000C, 0xFFFF)      # ODR: all high

    # Wait for output to settle
    await Timer(20, units='ns')

    # Check output
    await tester.check_gpio_output(0xFFFF)

    # Test 2: Drive low
    await tester.write_reg(0x4002000C, 0x0000)  # ODR: all low
    await Timer(20, units='ns')
    await tester.check_gpio_output(0x0000)

    # Test 3: Write alternating pattern
    await tester.write_reg(0x4002000C, 0xAAAA)  # ODR: alternating
    await Timer(20, units='ns')
    await tester.check_gpio_output(0xAAAA)

    # Test 4: BSRR set bits
    await tester.write_reg(0x40020010, 0x00000001)  # BSRR: set PA0
    await Timer(20, units='ns')
    await tester.check_gpio_output(0x0001)

    # Test 5: BSRR reset bits
    await tester.write_reg(0x40020010, 0x00010000)  # BSRR: reset PA0
    await Timer(20, units='ns')
    await tester.check_gpio_output(0x0000)

    # Test 6: BRR reset bits
    await tester.write_reg(0x4002000C, 0xFFFF)  # ODR: all high
    await tester.write_reg(0x40020014, 0x0001)  # BRR: reset PA0
    await Timer(20, units='ns')
    await tester.check_gpio_output(0xFFFE)

    # Test 7: Partial pin configuration
    await tester.write_reg(0x40020000, 0x44444444)  # CRL
    await tester.write_reg(0x40020004, 0x00000044)  # CRH: only PA14, PA15 as output
    await tester.write_reg(0x4002000C, 0xFFFF)      # ODR: all high
    await Timer(20, units='ns')
    await tester.check_gpio_output(0xFFFF)

    dut._log.info("GPIO output tests PASSED")


@cocotb.test()
async def test_gpio_input(dut):
    """Test GPIO input functionality."""
    tester = GPIO_Tester(dut)

    # Clock generation: 100 MHz
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())

    await tester.reset()

    # Configure PA0 as input
    await tester.write_reg(0x40020000, 0x00000000)  # CRL: input floating

    # Test: read input pin
    dut.gpio_in.value = 0x0000
    await Timer(20, units='ns')
    idr = await tester.read_reg(0x40020008)  # IDR
    assert idr == 0x0000, f"IDR mismatch: expected 0x0000, got {idr:#06x}"

    # Test: drive input high
    dut.gpio_in.value = 0x0001
    await Timer(20, units='ns')
    idr = await tester.read_reg(0x40020008)  # IDR
    assert idr == 0x0001, f"IDR mismatch: expected 0x0001, got {idr:#06x}"

    # Test: drive input all high
    dut.gpio_in.value = 0xFFFF
    await Timer(20, units='ns')
    idr = await tester.read_reg(0x40020008)  # IDR
    assert idr == 0xFFFF, f"IDR mismatch: expected 0xFFFF, got {idr:#06x}"

    dut._log.info("GPIO input tests PASSED")


@cocotb.test()
async def test_rcc_register(dut):
    """Test RCC register read/write."""
    tester = GPIO_Tester(dut)

    # Clock generation: 100 MHz
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())

    await tester.reset()

    # Test: write to CR register
    await tester.write_reg(0x40021000, 0x00000001)  # CR: HSI enable
    cr = await tester.read_reg(0x40021000)
    assert cr == 0x00000001, f"CR mismatch: expected 0x00000001, got {cr:#06x}"

    # Test: write to CFGR register
    await tester.write_reg(0x40021004, 0x00000000)  # CFGR
    cfgr = await tester.read_reg(0x40021004)
    assert cfgr == 0x00000000, f"CFGR mismatch: expected 0x00000000, got {cfgr:#06x}"

    dut._log.info("RCC register tests PASSED")
