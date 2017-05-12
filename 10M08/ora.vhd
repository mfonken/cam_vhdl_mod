----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_integer.all;

-- Project constants
use work.ora_types.all;
use work.ora_math.all;

----------------------------------------------
-- Object Recognition Architecture
----------------------------------------------
entity ora is
	generic
	(
		g_clk_r		: integer				:= 50_000_000;
		m_clk_r		: integer				:= 10_000_000;
		thresh    	: integer				:= 250;
		kernel    	: kernel_t				:= ( others => '0' );
		buffer_c  	: auto_correct_t		:= ( others => '0' )
--		pbuffer   	: packet_buffer_t 	:= ( others => ( others => '0' ) );
--		hasPacket 	: std_logic				:= '0'
	);
	port
	(
		-- Global clock
		gclk        : in    	std_logic;

		-- Camera interface
		ena			: inout	std_logic;
		pwdn			: out		std_logic;
		mclk        : inout 	std_logic;
		vsync       : in    	std_logic;
		href        : in    	std_logic;
		pclk        : in    	std_logic;
		cpi         : in    	std_logic_vector( 7 downto 0 );

		ora_pkt_ct	: out		integer;
		ora_data		: out		std_logic_vector( 7 downto 0 )
	);
end ora;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of ora is
	signal frame 			: frame_t;--                := ( others => ( others => '0' ) );
	signal d_map 			: density_map_t;--          := ( others => '0' ), ( others => '0');
	signal x_convolve 	: convolve_result_t;
	signal y_convolve 	: convolve_result_t;
	signal peaks 			: peaks_t;

	signal x 				: integer range FRAME_WIDTH  downto 0 := 0;
	signal y 				: integer range FRAME_HEIGHT downto 0 := 0;
	signal x_i 				: integer range FRAME_WIDTH  downto 0 := 0;
	signal y_i 				: integer range FRAME_HEIGHT downto 0 := 0;
	signal x_r 				: std_logic 	:= '0';
	signal y_r 				: std_logic 	:= '0';
	signal pixel			: unsigned( 7 downto 0 );

	signal c 				: std_logic_vector( 0 to 3 ) := "0000";

	begin
	pixel <= unsigned( CPI );



	sync_main : process( GCLK, PCLK, HREF, VSYNC, x, y, x_i, y_i )
	-- MCLK divider
	constant MCLK_DIV      	: integer := g_clk_r / m_clk_r;
	constant MCLK_DIV_HALF 	: integer := MCLK_DIV / 2;

	begin
		if rising_edge( gclk ) then
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
			if c = std_logic_vector(to_unsigned(MCLK_DIV_HALF,4)) then
				mclk <= not mclk;
				pwdn <= '0';
				c <= "0000";
			else
				c <= std_logic_vector(unsigned(c) + to_unsigned(1,4));
			end if;
		end if;

		-- Collect on PCLK
		if rising_edge( pclk ) then
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
		end if;

		-- Increment line on HREF
		if falling_edge( href ) then
			x_r <= '1';
			if y < FRAME_HEIGHT then
				y_i <= y + 1;
			else
				y_i <= y;
			end if;
			--      else
			--        x_r <= '0';
		end if;

		-- Reset and process on VSYNC
		if rising_edge( vsync ) then
--			y_r <= '1';
--			-- Process frame
--			d_map <= density_mapper( frame );
--
--			-- Convolve maps with a kernel
--			x_convolve <= convolveX( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, kernel );
--			y_convolve <= convolveY( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, kernel );
--
--			-- Calculate peaks in convolved map
--			peaks <= maxima( x_convolve, y_convolve );
--
--					buffer_c := 4;
--
----			Only set after packet is fully in buffer
--					hasPacket := '1';
--			   else
--			     y_r <= '0';
--			     hasPacket <= '0';
		end if;
	end process sync_main;
----------------------------------------------
-- Packet composition
----------------------------------------------
--  packet_composer : process()
--  begin
--  end process packet_composer;
end gbehaviour;
