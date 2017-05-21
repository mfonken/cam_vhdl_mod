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
		ora_has_packet		: inout	std_logic;
		ora_bytes_to_tx	: out		integer;
		ora_packet_buffer	: inout	packet_buffer_t
	);
end ora;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of ora is
--	signal frame 			: frame_t;--                := ( others => ( others => '0' ) );
--	signal d_map 			: density_map_t;--          := ( others => '0' ), ( others => '0');
--	signal x_convolve 	: convolve_result_t;
--	signal y_convolve 	: convolve_result_t;
--	signal x_peaks 		: x_peaks_a;
--	signal y_peaks 		: y_peaks_a;

	-- Non-clock delay signals
	signal pclk_d			: std_logic := '0';
	signal href_d			: std_logic := '0';
	signal vsync_d			: std_logic := '0';

	signal x 				: integer range 0 to FRAME_WIDTH := 0;
	signal y 				: integer range 0 to FRAME_HEIGHT := 0;
	signal pixel			: unsigned( 7 downto 0 );

	signal c 				: std_logic_vector( 0 to 3 ) := "0000";

	signal prepare_packet : std_logic := '0';
	signal x_p_l			: integer := 0;
	signal y_p_l			: integer := 0;

	begin
	pixel <= unsigned( cpi );
	B <= vsync_d;

	sync_process : process( gclk )
	-- MCLK divider
	constant MCLK_DIV      	: integer := g_clk_r / m_clk_r;
	constant MCLK_DIV_HALF 	: integer := MCLK_DIV / 2;
	variable x_map 			: x_array;
	variable y_map 			: y_array;
	variable x_convolve 		: convolve_result_t;
	variable y_convolve 		: convolve_result_t;
	variable x_peaks 			: x_peaks_a;
	variable y_peaks 			: y_peaks_a;
	variable x_max				: integer range 0 to MAX_VALUE;
	variable	y_max				: integer range 0 to MAX_VALUE;
	variable x_i				: integer range 0 to FRAME_WIDTH;
	variable	y_i				: integer range 0 to FRAME_HEIGHT;
--	variable t : integer range -(KERNEL_LENGTH-1) to FRAME_WIDTH := -(KERNEL_LENGTH-1);
	variable peak					: std_logic	:= '1';

	begin
		if rising_edge( gclk ) then
			pclk_d <= pclk;
			href_d <= href;
			vsync_d <= vsync;

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
				if pixel > PIXEL_THRESH then -- and x < FRAME_WIDTH and y < FRAME_HEIGHT then
					x_map(x) := x_map(x) + 1;
					y_map(y) := y_map(y) + 1;
					A <= '1';
				else
					A <= '0';
				end if;

				if x < FRAME_WIDTH then
					x <= x + 1;
				end if;
			end if;

			-- Increment line on HREF
			if href = '1' and href_d = '0' then
				x <= 0;
				if y < FRAME_HEIGHT then
					y <= y + 1;
				end if;
			end if;

			-- Reset and process on VSYNC
			if vsync = '1' and vsync_d = '0' then
				y <= 0;
				x <= 0;
				
				x_max := x_map(0);
				for i in 1 to FRAME_WIDTH - 1 loop
					if x_max < x_map(i) then
						x_max := x_map(i);
						x_i := i;
					end if;
				end loop;
				
				y_max := y_map(0);
				for i in 1 to FRAME_HEIGHT - 1 loop
					if y_max < y_map(i) then
						y_max := y_map(i);
						y_i := i;
					end if;
				end loop;
				
				ora_bytes_to_tx <= 3;
				ora_packet_buffer(1) <= std_logic_vector(to_unsigned(x_i, 8));
				ora_packet_buffer(0) <= std_logic_vector(to_unsigned(y_i, 8));

				prepare_packet <= '1';
			elsif vsync = '0' and vsync_d = '1' then
				x_map 	:= ( others => 0 );
				y_map 	:= ( others => 0 );
				x_peaks	:= ( ( others => 0 ), 0 );
				y_peaks	:= ( ( others => 0 ), 0 );
			end if;

			if ora_ack = '1' then
				prepare_packet <= '0';
			end if;
		end if;
	end process sync_process;
----------------------------------------------
-- Packet composition
----------------------------------------------
  packet_composer : process( gclk)
  begin
	if rising_edge( gclk ) then
		ora_packet_buffer(2) <= PACKET_HEADER;
		ora_has_packet <= prepare_packet;
	end if;
  end process packet_composer;
end gbehaviour;
