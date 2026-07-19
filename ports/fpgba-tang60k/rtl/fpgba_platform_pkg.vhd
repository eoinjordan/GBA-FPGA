library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fpgba_platform_pkg is
    subtype pixel5_t is std_logic_vector(4 downto 0);
    subtype audio16_t is signed(15 downto 0);

    type gba_keys_t is record
        a      : std_logic;
        b      : std_logic;
        key_select : std_logic;
        start  : std_logic;
        right  : std_logic;
        left   : std_logic;
        up     : std_logic;
        down   : std_logic;
        r      : std_logic;
        l      : std_logic;
    end record;

    constant GBA_KEYS_RELEASED : gba_keys_t := (
        a      => '0',
        b      => '0',
        key_select => '0',
        start  => '0',
        right  => '0',
        left   => '0',
        up     => '0',
        down   => '0',
        r      => '0',
        l      => '0'
    );
end package;

package body fpgba_platform_pkg is
end package body;
