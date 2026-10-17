---
name: vhdl-rtl-author
description: Synthesizable VHDL-2008 authoring guidelines, synchronous design rules, CDC synchronizers, and VUnit self-checking testbench templates for the Cora Z7-10 project.
---

# VHDL RTL Author Skill

Guidelines and strict design conventions for producing robust, synthesizable VHDL-2008 modules for the Artix-7 FPGA on the Zynq-7010.

## 1. When to Use
- Writing RTL modules in `cora7z/app/hw/src/*.vhdl`.
- Writing testbenches in `cora7z/app/hw/test/tb_*.vhdl`.
- Auditing VHDL code for synthesizability, timing closure risks, and naming consistency.

## 2. Structural Conventions

- **Language Standard**: VHDL-2008 (`--std=08` in GHDL/Vivado).
- **Package Policy**: Use `ieee.std_logic_1164.all` and `ieee.numeric_std.all`.
  - **PROHIBITED**: `std_logic_arith`, `std_logic_unsigned`, `std_logic_signed`.
- **File Naming**: Exactly one entity per file; filename must match entity name: `<entity_name>.vhdl`.
- **Testbench Naming**: Testbench file must be named `tb_<entity_name>.vhdl`.
- **Signal & Port Suffixes**:
  - `_i`: Input port (`clk_i`, `rst_i`, `data_i`)
  - `_o`: Output port (`valid_o`, `data_o`)
  - `_io`: Bidirectional port
  - `_r`: Sequential register output signal
  - `_s`: Pure combinational signal
  - `_n`: Active-low signal (`rst_n_i`, `cs_n_i`)
  - `_c`: Constant value (`CLK_PERIOD_C`)
  - `_t`: Type definition (`state_t`)

## 3. Synchronous Design Invariants
- Single rising-edge clock per domain: `if rising_edge(clk_i) then ... end if;`.
- Synchronous resets preferred for Artix-7 slices (`if rst_i = '1' then ...`).
- **Zero Latches**: All combinational processes (`process(all)`) must assign a default value to every signal at the start of the process.
- **No Synthesizable Delays**: `wait for` and `after` are strictly forbidden in synthesizable files (only permitted in testbenches).
- **Clock Domain Crossing (CDC)**: All external asynchronous signals (e.g., SPI inputs `sclk_i`, `mosi_i`, `cs_n_i`) MUST pass through a 2-stage (or 3-stage) flip-flop synchronizer clocked by the system clock before being sampled by internal FSMs.

## 4. VUnit Testbench Architecture

All testbenches must use VUnit's verification library and self-checking assertions:

```vhdl
library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_example_module is
  generic (runner_cfg : string);
end entity tb_example_module;

architecture tb of tb_example_module is
  constant CLK_PERIOD_C : time := 20 ns; -- 50 MHz
  signal clk_s : std_logic := '0';
  signal rst_s : std_logic := '1';
  -- test signals
begin
  clk_s <= not clk_s after CLK_PERIOD_C / 2;

  dut : entity work.example_module
    port map (
      clk_i => clk_s,
      rst_i => rst_s
    );

  main : process
  begin
    test_runner_setup(runner, runner_cfg);
    while test_suite loop
      if run("test_reset_behavior") then
        wait for 5 * CLK_PERIOD_C;
        check_equal(1, 1, "Reset check");
      elsif run("test_nominal_operation") then
        rst_s <= '0';
        wait for 10 * CLK_PERIOD_C;
        check(true, "Nominal operation check");
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process main;
end architecture tb;
```

## 5. Verification Commands
Before submitting RTL to the orchestrator:
```bash
# Lint checks (static GHDL analysis + anti-latch / numeric_std grep)
TASK_ID=<id> bash .agents/hooks/vhdl-lint.sh

# Simulation check
TASK_ID=<id> bash .agents/hooks/vhdl-sim-gate.sh
```
