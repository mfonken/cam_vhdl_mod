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

	signal x 				: integer range FRAME_WIDTH  downto 0 := 0;
	signal y 				: integer range FRAME_HEIGHT downto 0 := 0;
	signal x_i 				: integer range FRAME_WIDTH  downto 0 := 0;
	signal y_i 				: integer range FRAME_HEIGHT downto 0 := 0;
	signal x_r 				: std_logic 	:= '0';
	signal y_r 				: std_logic 	:= '0';
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
	variable t : integer range -(KERNEL_LENGTH-1) to FRAME_WIDTH := -(KERNEL_LENGTH-1);

	begin
		if rising_edge( gclk ) then
			pclk_d <= pclk;
			href_d <= href;
			vsync_d <= vsync;
			
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
		
			-- Collect on PCLK
			if pclk = '1' and pclk_d = '0' then
				if pixel > PIXEL_THRESH and x < FRAME_WIDTH and y < FRAME_HEIGHT then
--					frame(y)(x) <= '1';
					x_map(x) := x_map(x) + 1;
					y_map(y) := y_map(y) + 1;
					A <= '1';
				else
--					frame(y)(x) <= '0';
					A <= '0';
				end if;

				if x < FRAME_WIDTH then
					x_i <= x + 1;
				else
					x_i <= x;
				end if;
			end if;
			
			-- Increment line on HREF
			if href = '1' and href_d = '0' then
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
				for i in 0 to FRAME_WIDTH - 1 loop
					for j in 0 to KERNEL_LENGTH - 1 loop
						t := i - j;
						if t >= 0 and kernel(j) = '1' then
							x_convolve(i) := x_convolve(i) + x_map(t);
						end if;
					end loop;
				end loop;
				for i in 0 to FRAME_HEIGHT - 1 loop
					for j in 0 to KERNEL_LENGTH - 1 loop
						t := i - j;
						if t >= 0 and kernel(j) = '1' then
							y_convolve(i) := y_convolve(i) + y_map(t);
						end if;
					end loop;
				end loop;
				
				ora_bytes_to_tx <= UART_BUFFER_BYTE_LENGTH;
				
				for i in 0 to UART_BUFFER_BYTE_LENGTH/2 - 1 loop
					ora_packet_buffer(i) <= std_logic_vector(to_unsigned(x_map(i), 8));
					ora_packet_buffer(i+UART_BUFFER_BYTE_LENGTH/2) <= std_logic_vector(to_unsigned(y_map(i), 8));
				end loop;
				
				prepare_packet <= '1';
				y_r <= '1';
			elsif vsync = '0' and vsync_d = '1' then
				x_map 			:= ( others => 0 );
				y_map 			:= ( others => 0 );
				x_convolve		:= ( others => 0 );
				y_convolve		:= ( others => 0 );
				x_peaks.peaks	:= ( others => 0 );
				y_peaks.peaks	:= ( others => 0 );
				
			else
				y_r <= '0';
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
		ora_has_packet <= prepare_packet;
	end if;
  end process packet_composer;
end gbehaviour;
