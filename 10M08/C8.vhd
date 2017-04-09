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

  signal pixel : unsigned( 7 downto 0 );
  signal frame : frame_t;
  signal d_map : density_map_t;
  signal x_convolve : convolve_result_t;
  signal y_convolve : convolve_result_t;
  signal peaks : peaks_t;

  signal x : integer range FRAME_WIDTH  downto 0 := 0;
  signal y : integer range FRAME_HEIGHT downto 0 := 0;
  begin
    sync_main : process( GCLK )
    variable counter : integer := MCLK_DIV_HALF;
    begin
      if rising_edge( GCLK ) then

-- Clock divider & MCLK driver
        if counter = 0 then
          MCLK <= not MCLK;
          counter := MCLK_DIV_HALF;
        else
          counter := counter - 1;
        end if;

-- Collect on PCLK
        if rising_edge( PCLK ) then
          pixel <= unsigned( CPI );
          if( pixel > PIXEL_THRESH ) then
            frame(y)(x) <= '1';
          else
            frame(y)(x) <= '0';
          end if;

          if x < FRAME_WIDTH then
            x <= x + 1;
          end if;
        end if;

-- Increment line on HREF
        elsif falling_edge( HREF ) then
          x <= 0;
          
          if y < FRAME_HEIGHT then
            y <= y + 1;
          end if;

        end if;

-- Reset and process on VSYNC
        elsif rising_edge( VSYNC ) then
          y <= 0;

          -- Process frame
          d_map <= density_mapper( frame );

          -- Convolve maps with a kernel
          x_convolve <= convolve( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, PULSE_KERNEL );
          y_convolve <= convolve( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, PULSE_KERNEL );

          -- Calculate peaks in convolved map
          peaks <= maxima( x_convolve, y_convolve );
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
