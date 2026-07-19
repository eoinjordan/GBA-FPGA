library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fpgba_platform_pkg.all;

entity fpgba_tang60k_platform is
    generic (
        RESET_HOLD_CYCLES : positive := 1024
    );
    port (
        clk_core          : in  std_logic;
        pll_locked        : in  std_logic;
        ddr_calibrated    : in  std_logic;
        external_reset_n  : in  std_logic;

        button_a_n        : in  std_logic;
        button_b_n        : in  std_logic;
        button_select_n   : in  std_logic;
        button_start_n    : in  std_logic;
        button_right_n    : in  std_logic;
        button_left_n     : in  std_logic;
        button_up_n       : in  std_logic;
        button_down_n     : in  std_logic;
        button_r_n        : in  std_logic;
        button_l_n        : in  std_logic;

        core_reset        : out std_logic;
        core_enable       : out std_logic;
        keys              : out gba_keys_t
    );
end entity;

architecture rtl of fpgba_tang60k_platform is
    function clog2(value : positive) return positive is
        variable remaining : natural := value - 1;
        variable result    : positive := 1;
    begin
        while remaining > 1 loop
            remaining := remaining / 2;
            result := result + 1;
        end loop;
        return result;
    end function;

    constant RESET_COUNTER_WIDTH : positive := clog2(RESET_HOLD_CYCLES + 1);
    signal reset_counter : unsigned(RESET_COUNTER_WIDTH - 1 downto 0) := (others => '0');
    signal ready         : std_logic := '0';

    function active_low_to_pressed(signal input_n : std_logic) return std_logic is
    begin
        if input_n = '0' then
            return '1';
        end if;
        return '0';
    end function;

begin
    process (clk_core)
    begin
        if rising_edge(clk_core) then
            if external_reset_n = '0' or pll_locked = '0' or ddr_calibrated = '0' then
                reset_counter <= (others => '0');
                ready <= '0';
            elsif ready = '0' then
                if to_integer(reset_counter) >= RESET_HOLD_CYCLES - 1 then
                    ready <= '1';
                else
                    reset_counter <= reset_counter + 1;
                end if;
            end if;
        end if;
    end process;

    core_reset  <= not ready;
    core_enable <= ready;

    keys.a      <= active_low_to_pressed(button_a_n);
    keys.b      <= active_low_to_pressed(button_b_n);
    keys.key_select <= active_low_to_pressed(button_select_n);
    keys.start  <= active_low_to_pressed(button_start_n);
    keys.right  <= active_low_to_pressed(button_right_n);
    keys.left   <= active_low_to_pressed(button_left_n);
    keys.up     <= active_low_to_pressed(button_up_n);
    keys.down   <= active_low_to_pressed(button_down_n);
    keys.r      <= active_low_to_pressed(button_r_n);
    keys.l      <= active_low_to_pressed(button_l_n);
end architecture;
