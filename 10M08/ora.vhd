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
		A	: inout std_logic := '0';
		B	: inout std_logic := '0';
		-- Global clock
		gclk        		: in    	std_logic;

		-- Camera interface
		ena					: inout	std_logic;
		pwdn					: out		std_logic;
		mclk        		: inout 	std_logic;
		vsync       		: in    	std_logic;
		href       		 	: in    	std_logic;
		pclk        		: in    	std_logic;
		cpi         		: in    	std_logic_vector( 7 downto 0 );

		ora_ack				: in		std_logic;
		ora_has_packet		: inout		std_logic;
		ora_bytes_to_tx	: out		integer;
		ora_packet_buffer	: inout	packet_buffer_t
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
	
	-- Non-clock delay signals
	signal pclk_d			: std_logic := '0';
	signal href_d			: std_logic := '0';
	signal vsync_d			: std_logic := '0';

	signal x 				: integer range FRAME_WIDTH  downto 0 := 0;
	signal y 				: integer range FRAME_HEIGHT downto 0 := 0;
	signal x_i 				: integer range FRAME_WIDTH  downto 0 := 0;
	signal y_i 				: integer range FRAME_HEIGHT downto 0 := 0;
	signal x_r 				: std_logic 	:= '0';
	signal y_r 				: std_logic 	:= '0';
	signal pixel			: unsigned( 7 downto 0 );

	signal c 				: std_logic_vector( 0 to 3 ) := "0000";

	begin
	pixel <= unsigned( cpi );

	A <= ora_ack;
	B <= ora_has_packet;
	
	sync_process : process( gclk )
	-- MCLK divider
	constant MCLK_DIV      	: integer := g_clk_r / m_clk_r;
	constant MCLK_DIV_HALF 	: integer := MCLK_DIV / 2;

	begin
		if rising_edge( gclk ) then
			pclk_d <= pclk;
			href_d <= href;
			vsync_d <= vsync;
			
			if x_r = '1' then
				x <= 0;
--				A <= not A;
			else
				x <= x_i;
			end if;

			if y_r = '1' then
				y <= 0;
--				B <= not B;
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
		
			-- Collect on PCLK
			if pclk = '1' and pclk_d = '0' then
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
			if href = '0' and href_d = '1' then
				x_r <= '1';
				if y < FRAME_HEIGHT then
					y_i <= y + 1;
				else
					y_i <= y;
				end if;
			else
			  x_r <= '0';
			end if;
			
			-- Reset and process on VSYNC
			if vsync = '1' and vsync_d = '0' then
				y_r <= '1';
				
				-- Process frame
				d_map <= density_mapper( frame );

				-- Convolve maps with a kernel
				x_convolve <= convolveX( FRAME_WIDTH,  d_map.x_map, KERNEL_LENGTH, kernel );
				y_convolve <= convolveY( FRAME_HEIGHT, d_map.y_map, KERNEL_LENGTH, kernel );

				-- Calculate peaks in convolved map
				peaks <= maxima( x_convolve, y_convolve );

				ora_packet_buffer( 47 downto 24 ) <= std_logic_vector(to_unsigned(peaks.x_peaks(0), 24));
				ora_packet_buffer( 23 downto 0  ) <= std_logic_vector(to_unsigned(peaks.y_peaks(0), 24));
				ora_has_packet <= '1';
			else
				y_r <= '0';
			end if;
			
			if ora_ack = '1' then
				ora_has_packet <= '0';
			end if;
		end if;
	end process sync_process;
----------------------------------------------
-- Packet composition
----------------------------------------------
--  packet_composer : process()
--  begin
--  end process packet_composer;
end gbehaviour;
