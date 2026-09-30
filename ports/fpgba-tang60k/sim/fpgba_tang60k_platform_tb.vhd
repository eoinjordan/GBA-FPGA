-- =============================================================================
-- fpgba_tang60k_platform_tb -- reset release and key mapping checks
-- =============================================================================
-- With RESET_HOLD_CYCLES = 4: reset must stay asserted for the hold time after
-- all conditions are met, then release; A and Left map to pressed while B stays
-- released; losing DDR3 calibration must reset the core again.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.fpgba_platform_pkg.all;

entity fpgba_tang60k_platform_tb is
end entity;

architecture tb of fpgba_tang60k_platform_tb is
    constant CLK_PERIOD : time := 10 ns;

    signal clk_core         : std_logic := '0';
    signal pll_locked       : std_logic := '0';
    signal ddr_calibrated   : std_logic := '0';
    signal external_reset_n : std_logic := '0';

    signal button_a_n      : std_logic := '1';
    signal button_b_n      : std_logic := '1';
    signal button_select_n : std_logic := '1';
    signal button_start_n  : std_logic := '1';
    signal button_right_n  : std_logic := '1';
    signal button_left_n   : std_logic := '1';
    signal button_up_n     : std_logic := '1';
    signal button_down_n   : std_logic := '1';
    signal button_r_n      : std_logic := '1';
    signal button_l_n      : std_logic := '1';

    signal core_reset  : std_logic;
    signal core_enable : std_logic;
    signal keys        : gba_keys_t;
begin
    clk_core <= not clk_core after CLK_PERIOD / 2;

    dut : entity work.fpgba_tang60k_platform
        generic map (
            RESET_HOLD_CYCLES => 4
        )
        port map (
            clk_core         => clk_core,
            pll_locked       => pll_locked,
            ddr_calibrated   => ddr_calibrated,
            external_reset_n => external_reset_n,
            button_a_n       => button_a_n,
            button_b_n       => button_b_n,
            button_select_n  => button_select_n,
            button_start_n   => button_start_n,
            button_right_n   => button_right_n,
            button_left_n    => button_left_n,
            button_up_n      => button_up_n,
            button_down_n    => button_down_n,
            button_r_n       => button_r_n,
            button_l_n       => button_l_n,
            core_reset       => core_reset,
            core_enable      => core_enable,
            keys             => keys
        );

    -- ---- Stimulus and checks -------------------------------------------------------
    stimulus : process
    begin
        wait for 3 * CLK_PERIOD;
        external_reset_n <= '1';
        pll_locked <= '1';
        ddr_calibrated <= '1';

        wait for 3 * CLK_PERIOD;
        assert core_reset = '1' report "Reset released too early" severity failure;

        wait for 2 * CLK_PERIOD;
        assert core_reset = '0' report "Reset did not release" severity failure;
        assert core_enable = '1' report "Core enable did not assert" severity failure;

        button_a_n <= '0';
        button_left_n <= '0';
        wait for CLK_PERIOD;
        assert keys.a = '1' report "A button mapping failed" severity failure;
        assert keys.left = '1' report "Left button mapping failed" severity failure;
        assert keys.b = '0' report "Released B button reported pressed" severity failure;

        ddr_calibrated <= '0';
        wait for CLK_PERIOD;
        assert core_reset = '1' report "DDR calibration loss did not reset core" severity failure;

        report "PASS: fpgba_tang60k_platform" severity note;
        wait;
    end process;
end architecture;
