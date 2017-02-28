----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

-- Project constants
use work.C8_constants.all;
use work.C8_types.all;
use work.C8_math.all;

----------------------------------------------
-- Main camera controller entity
----------------------------------------------
entity cam_controller is
  port (
  -- Global clock
  gclk  : in    std_logic;

  -- Camera interface
  mclk  : out   std_logic;
  vsync : in    std_logic;
  href  : in    std_logic;
  pclk  : in    std_logic;
  cpi   : in    std_logic_vector( 7 downto 0 );
  siod  : inout std_logic;
  sioc  : out   std_logic;

  -- Serial interface
  rx    : in    std_logic;
  tx    : out   std_logic;

  dummy
  );
end cam_controller;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of cam_controller is

  signal pixel : unsigned( 7 downto 0 );
  signal frame : frame_t;
  signal d_map : density_map_t;
  signal c_map : density_map_t;

  signal peaks : peaks_t;

  begin
    ----------------------------------------------
    -- Clock divider & mclk driver
    ----------------------------------------------
    mclk_generator : process( clk )
      variable counter : unsigned := ( MCLK_DIVIDER / 2 );
    begin
      counter := counter - 1;
      if( counter = 0 ) then
        mclk <= not mclk;
        counter := ( MCLK_DIVIDER / 2 );
      end if;
    end mclk_generator;
    ----------------------------------------------
    -- CPI driver
    ----------------------------------------------
    capture_frame : process( vsync, href, pclk )
      variable x : unsigned range 0 to FRAME_WIDTH;
      variable y : unsigned range 0 to FRAME_HEIGHT;
    begin
      frame <= ( others => '0' );
      if( vsync'event and vsync = '1' ) then

        -- Capture new frame
        y := 0;
        while( href = '1' ) loop
          x := 0;
          if( pclk'event and pclk = '1' ) then
            pixel := unsigned(cpi);
            if( pixel > PIXEL_THRESH ) then
              frame(y)(x) = '1';
            end if;
            x := x + 1;
          end if;
          y := y + 1;
        end loop;

        -- Process frame
        d_map <= density_mapper( frame );

        -- Convolve maps with a kernel
        c_map.x_map <= convolve( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, PULSE_KERNEL );
        c_map.y_map <= convolve( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, PULSE_KERNEL );

        -- Calculate peaks in convolved map
        peaks <= maxima( c_map );

      end if;
    end capture_frame;
    ----------------------------------------------
    -- Math
    ----------------------------------------------

    ----------------------------------------------
    -- Packet composition
    ----------------------------------------------
    packet_composer : process()
  end gbehaviour;
