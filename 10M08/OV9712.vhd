library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package OV9712 is

-- Camera info
  constant OV9712_ADDR : std_logic_vector( 6 downto 0 ) := b"0000000"; -- TODO: get actual address

	constant DVP_CTRL_00 : std_logic_vector( 7 downto 0 ) := x"80";

  type OV9712_reg_t is record
    reg : std_logic_vector( 7 downto 0 );
    val : std_logic_vector( 7 downto 0 )
  end record OV9712_reg_t;

  constant DEFAULT_REGS : array ( 0 to 1 ) of OV9712_reg_t :=
    (
      ( DVP_CTRL_00, x"b0" ),
      ( null, null )
    );

end OV9712;
