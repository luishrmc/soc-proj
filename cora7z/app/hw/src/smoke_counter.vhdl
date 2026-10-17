-- Temporary smoke module used only to validate the VUnit + GHDL flow.
-- Removed once the first real RTL block lands (task 2.1).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity smoke_counter is
  port (
    clk_i : in  std_logic;
    rst_i : in  std_logic;
    q_o   : out unsigned(3 downto 0)
  );
end entity smoke_counter;

architecture rtl of smoke_counter is
  signal count_r : unsigned(3 downto 0) := (others => '0');
begin
  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        count_r <= (others => '0');
      else
        count_r <= count_r + 1;
      end if;
    end if;
  end process;

  q_o <= count_r;
end architecture rtl;
