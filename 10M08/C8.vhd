----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_integer.all;

-- Project constants
use work.C8_constants.all;
use work.C8_types.all;
use work.C8_math.all;

----------------------------------------------
-- Main camera controller entity
----------------------------------------------
entity C8_Project is
  port (
  -- Global clock
  GCLK  : in    std_logic;

  -- Camera interface
  MCLK  : inout std_logic;
  VSYNC : in    std_logic;
  HREF  : in    std_logic;
  PCLK  : in    std_logic;
  CPI   : in    std_logic_vector( 7 downto 0 );
  SIOD  : inout std_logic;
  SIOC  : out   std_logic;

  -- Serial interface
  RX    : in    std_logic;
  TX    : out   std_logic
  );
end C8_Project;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of C8_Project is


  signal frame : frame_t                := ( others => ( others => '0' ) );
  signal d_map : density_map_t          := ( others => '0' ), ( others => '0');
  signal x_convolve : convolve_result_t;
  signal y_convolve : convolve_result_t;
  signal peaks : peaks_t;

  signal x : integer range FRAME_WIDTH  downto 0 := 0;
  signal y : integer range FRAME_HEIGHT downto 0 := 0;
  signal x_i : integer range FRAME_WIDTH  downto 0 := 0;
  signal y_i : integer range FRAME_HEIGHT downto 0 := 0;
  signal x_r : std_logic := '0';
  signal y_r : std_logic := '0';
  signal pixel   : unsigned( 7 downto 0 );

  begin

    pixel := unsigned( CPI );

    sync_main : process( GCLK )
    variable c : integer := MCLK_DIV_HALF;
    variable c_p : integer := 0;
    begin
      if rising_edge( GCLK ) then
        if x_r = '1' then
          x <= 0;
        else
          x <= x_i;
        end if;

        if y_r = '1' then
          y <= 0;
        else
          y <= y_i;
        end if;

        -- Clock divider & MCLK driver
        if c = 0 then
          MCLK <= not MCLK;
          c_i := MCLK_DIV_HALF;
        else
          c_i := c - 1;
        end if;
      else
        c := c_i;
        x <= x_i;
        y <= y_i;
      end if;

      -- Collect on PCLK
      if rising_edge( PCLK ) then
        if( pixel > PIXEL_THRESH ) then
          frame(y)(x) <= '1';
        else
          frame(y)(x) <= '0';
        end if;

        if x < FRAME_WIDTH then
          x_i <= x + 1;
        else
          x_i <= x;
        end if;
      else
        x_i <= x;
      end if;

      -- Increment line on HREF
      if falling_edge( HREF ) then
        x_r <= '1';

        if y < FRAME_HEIGHT then
          y_i <= y + 1;
        else
          y_i <= y;
        end if;
      else
        x_r <= '0';
        y_i <= y;
      end if;

      -- Reset and process on VSYNC
    elsif rising_edge( VSYNC ) then
      y_r <= '1';
      -- Process frame
      d_map <= density_mapper( frame );

      -- Convolve maps with a kernel
      x_convolve <= convolve( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, PULSE_KERNEL );
      y_convolve <= convolve( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, PULSE_KERNEL );

      -- Calculate peaks in convolved map
      peaks <= maxima( x_convolve, y_convolve );
    else
      y_r <= '0';
    end if;
  end if;
end process sync_main;
----------------------------------------------
-- Packet composition
----------------------------------------------
--  packet_composer : process()
--  begin
--  end process packet_composer;
end gbehaviour;