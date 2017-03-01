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

	signal pixel : integer range 7 downto 0;
	signal frame : frame_t;
	signal d_map : density_map_t;
	signal x_convolve : convolve_result_t;
	signal y_convolve : convolve_result_t;
	signal peaks : peaks_t;

  begin
    ----------------------------------------------
    -- Clock divider & MCLK driver
    ----------------------------------------------
 MCLK_generator : process( GCLK, MCLK )
	variable counter : integer := ( MCLK_DIVIDER / 2 );
	begin
		counter := counter - 1;
		if( counter = 0 ) then
			MCLK <= not MCLK;
			counter := ( MCLK_DIVIDER / 2 );
		end if;
	end process;
    ----------------------------------------------
    -- CPI driver
    ----------------------------------------------
	capture_frame : process( VSYNC, HREF, PCLK )
	variable x : integer range 0 to FRAME_WIDTH;
	variable y : integer range 0 to FRAME_HEIGHT;
	begin
--	frame <= ( others => '0' );
	if( VSYNC'event and VSYNC = '1' ) then

		-- Capture new frame
		y := 0;
		while( HREF = '1' ) loop
			x := 0;
			if( PCLK'event and PCLK = '1' ) then
				pixel <= to_integer(unsigned(CPI));
				if( pixel > PIXEL_THRESH ) then
					frame(y)(x) <= '1';
				else
					frame(y)(x) <= '0';
				end if;
				x := x + 1;
			end if;
			y := y + 1;
		end loop;

		----------------------------------------------
		-- Math
		----------------------------------------------
		-- Process frame
		d_map <= density_mapper( frame );

		-- Convolve maps with a kernel
		x_convolve <= convolve( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, PULSE_KERNEL );
		y_convolve <= convolve( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, PULSE_KERNEL );

		-- Calculate peaks in convolved map
		peaks <= maxima( x_convolve, y_convolve );

	end if;
end process;

    ----------------------------------------------
    -- Packet composition
    ----------------------------------------------
--    packet_composer : process()
--	 begin
--	 end process;
  end gbehaviour;
