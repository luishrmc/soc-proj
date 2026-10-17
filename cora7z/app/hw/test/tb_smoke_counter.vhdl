-- Temporary smoke testbench used only to validate the VUnit + GHDL flow.
library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_smoke_counter is
  generic (runner_cfg : string);
end entity tb_smoke_counter;

architecture tb of tb_smoke_counter is
  constant CLK_PERIOD_C : time := 10 ns;
  signal clk_s : std_logic := '0';
  signal rst_s : std_logic := '1';
  signal q_s   : unsigned(3 downto 0);
begin
  clk_s <= not clk_s after CLK_PERIOD_C / 2;

  dut : entity work.smoke_counter
    port map (clk_i => clk_s, rst_i => rst_s, q_o => q_s);

  main : process
  begin
    test_runner_setup(runner, runner_cfg);
    while test_suite loop
      if run("reset_holds_zero") then
        wait for 3 * CLK_PERIOD_C;
        check_equal(to_integer(q_s), 0, "counter must stay at 0 during reset");
      elsif run("counts_up") then
        wait for 2 * CLK_PERIOD_C;
        rst_s <= '0';
        wait for 5 * CLK_PERIOD_C;
        check(to_integer(q_s) > 0, "counter must advance after reset release");
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process main;
end architecture tb;
