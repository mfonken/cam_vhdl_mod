library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package hyperram_types is

  type ca_64MB_t is record
		r_wn  : std_logic;
		as    : std_logic;
		burst : std_logic;
		rsv1  : std_logic_vector( 44 downto 35 );
		row   : std_logic_vector( 34 downto 22 );
		col_u : std_logic_vector( 21 downto 16 );
		rsv2  : std_logic_vector( 15 downto 3  );
		col_l : std_logic_vector(  2 downto 0  );
	end record ca_64MB_t;

  type hyperram_command_t is record
    read_command    : std_logic;
    write_command   : std_logic;
    register_space  : std_logic;
    memory_space    : std_logic;
  end record hyperram_command_t;
  constant hyperram_command : hyperram_command_t :=
  (
    read_command   => '1',
    write_command  => '0',
    register_space => '1',
    memory_space   => '0'
  );

end hyperram_types;
