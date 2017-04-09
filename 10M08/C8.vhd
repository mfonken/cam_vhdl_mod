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
    ----------------------------------------------------------------------------
    -- Clock divider & MCLK driver
    --   Note: MCLK toggles twice every period, thus MCLK_DIV_HALF = MCLK / 2
    ----------------------------------------------------------------------------
    mclk_generator : process( GCLK )
    variable counter : integer := MCLK_DIV_HALF;
    begin
      counter := counter - 1;
      if( counter = 0 ) then
        MCLK <= not MCLK;
        counter := MCLK_DIV_HALF;
      end if;
    end process mclk_generator;

    ----------------------------------------------
    -- CPI driver
    ----------------------------------------------

    -- Collect on PCLK
    pclk_event : process( PCLK )
    begin
      if rising_edge( PCLK ) then
        pixel <= unsigned( CPI );
        if( pixel > PIXEL_THRESH ) then
          frame(y)(x) <= '1';
        else
          frame(y)(x) <= '0';
        end if;
        if VSYNC = '0' then
          x <= x + 1;
        else
          x <= 0;
        end if;
      end if;
    end process pclk_event;

    -- Increment line on HREF
    href_event : process( HREF )
    begin
      if falling_edge( HREF ) then
        if VSYNC = '0' then
          y <= y + 1;
        else
          y <= 0;
        end if;
      end if;
    end process href_event;

    -- Reset and process on VSYNC
    vsync_event : process( VSYNC )
    begin
      if rising_edge( VSYNC ) then
        -- Process frame
        d_map <= density_mapper( frame );

        -- Convolve maps with a kernel
        x_convolve <= convolve( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, PULSE_KERNEL );
        y_convolve <= convolve( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, PULSE_KERNEL );

        -- Calculate peaks in convolved map
        peaks <= maxima( x_convolve, y_convolve );
      end if;
    end process vsync_event;

    ----------------------------------------------
    -- Packet composition
    ----------------------------------------------
      --  packet_composer : process()
    	--  begin
    	--  end process packet_composer;
  end gbehaviour;
