----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Global files
use work.global_types.all;


-- Ora files
use work.ora_types.all;
use work.ora_math.all;

-- Camera files
use work.OV9712.all;

-- UART files
--use work.uart.all;
use work.ucp_lib.all;

-- I2C files
--use work.i2c_master.all;

-- RAM files
--use work.hrddr.all;
--------------------------------------------------------------------------------

----------------------------------------------
-- Main controller entity
----------------------------------------------
entity master_bridge is
	port (
		LED1	: out	std_logic := '1';
		LED2	: out	std_logic := '1';
		LED3	: out	std_logic := '1';
		LED4	: out	std_logic := '1';
		LED5	: out	std_logic := '1';
		A	: inout std_logic := '0';
		B	: inout std_logic := '0';

		-- Global clock
		clock  		: in    	std_logic;

		-- Camera interface
		cam_ena 		: inout 	std_logic := '1';
		mclk     	: inout 	std_logic;
		pwdn			: out		std_logic;
		vsync     	: in    	std_logic;
		href      	: in    	std_logic;
		pclk      	: in    	std_logic;
		cpi       	: in    	std_logic_vector( 7 downto 0 );
		sda  			: inout 	std_logic;
		scl  			: inout 	std_logic;

		-- Serial interface
		umd_tx    	: out    std_logic;
		umd_rx    	: in  	std_logic;
		
		-- HyperRAM interface
		ram_rst     : inout 	std_logic := '1';
		ram_cs_n    : inout	std_logic := '1';
		ram_ck_p    : inout 	std_logic := '0';
		ram_ck_n    : inout 	std_logic := '1';
		ram_rwds    : inout 	std_logic := 'Z';
		ram_dq      : inout	std_logic_vector( 7 downto 0 );
		
		ram_vcc		: out		std_logic := '0';
		ram_vccq		: out		std_logic := '0';
		
		t_ram_rst   : out 	std_logic;
		t_ram_cs_n  : out 	std_logic;
		t_ram_ck_p  : out 	std_logic;
		t_ram_ck_n  : out		std_logic;
		t_ram_rwds  : out 	std_logic;
		t_ram_dq    : out 	std_logic_vector( 7 downto 0 );

		-- Synchronous reset (active low)
		reset_n		: inout	std_logic
	);
end master_bridge;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of master_bridge is
-- signal		reset_n						: std_logic;

constant sys_clk_frq			: integer 			:= 50_000_000;
constant	i2c_scl_frq			: integer			:= 100_000;
constant	umd_baud_r			: integer			:= 921_600;
constant	ora_clk_frq			: integer			:= 10_000_000;
constant	ram_clk_frq			: integer			:= 5_000_000;
constant ram_lat_config		: positive			:= 6;

-- Module clocks
signal  	umd_clock         : std_logic       := '0';
signal  	i2c_clock         : std_logic       := '0';
signal  	ora_clock         : std_logic       := '0';
signal	ram_clock			: std_logic			:= '0';

-- RAM data
signal	ram_ena				: std_logic			:= '0';
signal	ram_wr_data       : std_logic_vector(  7 downto 0 );
signal	ram_wr_request   	: std_logic			:= '0';
signal	ram_wr_length   	: std_logic_vector(  7 downto 0 );
	
signal	ram_rd_data       : std_logic_vector(  7 downto 0 );
signal	ram_rd_request   	: std_logic 		:= '0';
signal	ram_rd_length   	: std_logic_vector(  7 downto 0 );
signal	ram_strobe      	: std_logic 		:= '0';
signal	ram_request_ack	: std_logic 		:= '0';
signal	ram_burst         : std_logic;
signal	ram_as            : std_logic;
signal	ram_row           : std_logic_vector( 12 downto 0 );
signal	ram_col           : std_logic_vector(  8 downto 0 );

-- Ora data
signal	ora_ena				: std_logic			:= '1';
signal 	ora_pkt_ct			: integer			:= 0;
signal	ora_data				: std_logic_vector( 7 downto 0 );

-- Ora tuning
constant	ora_clk_r			: integer			:= 10_000_000;
signal  	ora_thresh        : integer         := DEFAULT_THRESH;
signal  	ora_kernel        : kernel_t        := DEFAULT_KERNEL;
signal  	ora_auto_cor      : auto_correct_t 	:= DEFAULT_AUTO_CORRECT;

signal  	packet_tx_i   		: integer         := 0;
signal	ora_ack				: std_logic			:= '0';
signal	ora_has_packet		: std_logic			:= '0';
signal  	ora_bytes_to_tx  	: integer         := 0;
signal  	ora_packet_buffer	: packet_buffer_t;

-- Uart signals
signal	umd_ena				: std_logic			:= '1';
signal	umd_rx_data    	: std_logic_vector(7 downto 0);
signal	umd_rx_stb  		: std_logic;
signal	umd_rx_ack  		: std_logic;
signal	umd_tx_data    	: std_logic_vector(7 downto 0);
signal	umd_tx_stb 	   	: std_logic;

-- UCP flags/inputs
signal  	prev_umd_rx       : std_logic_vector( 7 downto 0 );
signal  	hasAck            : std_logic       := '0';
signal  	hasNack           : std_logic       := '0';
signal  	ora_thresh_new    : integer         := 0;
signal  	ora_kernel_new    : kernel_t			:= kernel.pulse_kernel;
signal  	ora_auto_cor_new  : auto_correct_t 	:= auto_correct.auto_cor_none;

-- i2c signals
signal 	i2c_ena		   	: std_logic			:= '1';
signal 	i2c_rw		   	: std_logic       := '0';
signal 	i2c_wr		   	: std_logic_vector( 7 downto 0 );
signal 	i2c_rd		   	: std_logic_vector( 7 downto 0 );
signal	i2c_bsy		   	: std_logic			:= '0';
signal	i2c_bsy_prev   	: std_logic;
signal	i2c_ack_err    	: std_logic;

-- COMPONENTS
	component master is
		generic
		(
			input_clk : integer
		);
		port
		(
			LED1	: out	std_logic := '1';
			LED2	: out	std_logic := '1';
			LED3	: out	std_logic := '1';
			LED4	: out	std_logic := '1';
			LED5	: out	std_logic := '1';

			clock					: in 		std_logic;
			reset_n				: inout  std_logic;

			umd_clock			: inout	std_logic;
			i2c_clock			: inout	std_logic;
			ora_clock			: inout	std_logic;
			ram_clock			: inout	std_logic;

			i2c_ena				: out    std_logic;
			i2c_rw    			: out    std_logic	:= '0';
			i2c_wr	  			: out    std_logic_vector( 7 downto 0 );
			i2c_rd				: in     std_logic_vector( 7 downto 0 );
			i2c_bsy				: in     std_logic	:= '0';
			-- i2c_ack_err       : std_logic;

			umd_ena   			: inout 	std_logic;
			umd_rx_data			: inout  std_logic_vector( 7 downto 0 );
			umd_rx_stb 			: inout  std_logic;
			umd_rx_ack 			: inout  std_logic;
			umd_tx_data			: inout  std_logic_vector( 7 downto 0 );
			umd_tx_stb 			: inout  std_logic;

			ora_ena   			: inout 	std_logic;
			ora_ack				: inout	std_logic;
			ora_has_packet		: in		std_logic;
			ora_bytes_to_tx	: in 		integer;
			ora_packet_buffer	: inout	packet_buffer_t;
			cam_ena   			: inout  std_logic;
			
			ram_ena				: inout 	std_logic
		);
	end component master;

	component i2c_master is
		generic
		(
			input_clk 	: 			integer;
			bus_clk		: 			integer
		);
		port
		(
			clk			: in 		std_logic;
			reset_n		: in 		std_logic;
			ena			: in 		std_logic;
			addr			: in 		std_logic_vector( 6 downto 0 );
			rw				: in 		std_logic;
			data_wr		: in		std_logic_vector( 7 downto 0 );
			busy			: out 	std_logic 		:= '0';
			data_rd 		: out 	std_logic_vector( 7 downto 0 );
			ack_error 	: buffer std_logic;
			sda			: inout	std_logic;
			scl			: inout	std_logic
		);
	end component i2c_master;

	component uart is
		generic
		(
			baud                : positive;
			clock_frequency     : positive
		);
		port
		(
			clock               :   in  std_logic;
			reset               :   in  std_logic;
			data_stream_in      :   in  std_logic_vector(7 downto 0);
			data_stream_in_stb  :   in  std_logic;
			data_stream_in_ack  :   out std_logic;
			data_stream_out     :   out std_logic_vector(7 downto 0);
			data_stream_out_stb :   out std_logic;
			tx                  :   out std_logic;
			rx                  :   in  std_logic
		);
	end component uart;

	component ora is
		generic
		(
			g_clk_r				: integer;
			m_clk_r				: integer;
			thresh    			: integer;
			kernel    			: kernel_t;
			buffer_c  			: auto_correct_t
		);
		port
		(
			
				-- Global clock
			gclk        		: in    	std_logic;

			-- Camera interface
			reset_n				: inout	std_logic;
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
			ora_packet_buffer	: inout	packet_buffer_t;
			
			r_rd_data       	: in   	std_logic_vector(  7 downto 0 );
			r_rd_request    	: out    std_logic;
			r_rd_length     	: out   	std_logic_vector(  7 downto 0 );

			r_wr_data     		: out    std_logic_vector(  7 downto 0 );
			r_wr_request    	: out    std_logic;
			r_wr_length     	: inout 	std_logic_vector(  7 downto 0 );

			r_strobe        	: inout 	std_logic;
			r_request_ack   	: in   	std_logic;

			r_burst         	: out    std_logic;
			r_as            	: out    std_logic;
			r_row           	: out    std_logic_vector( 12 downto 0 );
			r_col           	: out    std_logic_vector(  8 downto 0 )
		);
	end component ora;
	
	component hrddr is
		generic 
		(
			sys_ck_frequency  : positive;
			ddr_ck_frequency  : positive;
			latency_config		: positive
		);
		port 
		(
			A	: inout std_logic := '0';
			B	: inout std_logic := '0';
			clock            	: in    	std_logic;
			reset_n           : in    	std_logic;

			rd_data           : out   	std_logic_vector(  7 downto 0 );
			rd_request        : in		std_logic;
			rd_length         : in   	std_logic_vector(  7 downto 0 );

			wr_data           : in    	std_logic_vector(  7 downto 0 );
			wr_request        : in    	std_logic;
			wr_length         : in   	std_logic_vector(  7 downto 0 );

			strobe            : inout	std_logic;
			request_ack       : out   	std_logic;

			burst             : in   	std_logic;
			as                : in    	std_logic;
			row               : in    	std_logic_vector( 12 downto 0 );
			col               : in    	std_logic_vector(  8 downto 0 );

			cs_n              : inout 	std_logic;
			ck_p              : inout 	std_logic;
			ck_n              : out   	std_logic;
			rwds              : inout 	std_logic;
			dq                : inout 	std_logic_vector(  7 downto 0 )
		);
	end component hrddr;

begin
	
	ram_rst <= reset_n;
	
	-- Test lines for HRDDR
	t_ram_rst 	<= ram_rst;
	t_ram_cs_n 	<= ram_cs_n;
	t_ram_ck_p	<= ram_ck_p;
	t_ram_ck_n 	<= ram_ck_n;
	t_ram_rwds 	<= ram_rwds;
	t_ram_dq 	<= ram_dq;
	
--	reset_handler : process( clock )
--	begin
--		if rising_edge( clock ) then
--			if reset_n = '0' then
--				ram_cs_n <= '1';
--			end if;
--		end if;
--	end process reset_handler;

	-- Master module component initialization
	master_m : master
	generic map
	(
		input_clk		=> sys_clk_frq
	)
	port map
	(
		LED1	=> LED1,
		LED2	=> LED2,
		LED3	=> LED3,
		LED4	=> LED4,
		LED5	=> LED5,

		clock						=>	clock,
		reset_n					=>	reset_n,

		umd_clock				=> umd_clock,
		i2c_clock				=> i2c_clock,
		ora_clock				=>	ora_clock,
		ram_clock				=> ram_clock,

		i2c_ena					=>	i2c_ena,
		i2c_rw   				=>	i2c_rw,
		i2c_wr	 				=>	i2c_wr,
		i2c_rd					=>	i2c_rd,
		i2c_bsy					=>	i2c_bsy,
		-- i2c_ack_err       : std_logic;

		umd_ena   				=>	umd_ena,
		umd_tx_data				=>	umd_tx_data,
		umd_rx_data				=>	umd_rx_data,
		umd_rx_stb 				=> umd_rx_stb,
		umd_rx_ack 				=>	umd_rx_ack,
		umd_tx_stb 				=>	umd_tx_stb,

		ora_ena   				=>	ora_ena,
		ora_ack					=> ora_ack,
		ora_has_packet			=> ora_has_packet,
		ora_bytes_to_tx		=> ora_bytes_to_tx,
		ora_packet_buffer		=> ora_packet_buffer,
		cam_ena					=> cam_ena,
		
		ram_ena					=> ram_ena
	);

	-- I2C Module component instantiation
	i2c_master_0 : i2c_master
	generic map
	(
		input_clk 		=> sys_clk_frq,
		bus_clk			=> i2c_scl_frq
	)
	port map
	(
		clk 				=> i2c_clock,
		reset_n 			=>	reset_n,
		ena				=> i2c_ena,
		addr				=> OV9712_ADDR,
		rw					=> i2c_rw,
		data_wr 			=> i2c_wr,
		busy  			=> i2c_bsy,
		data_rd			=>	i2c_rd,
		ack_error		=> i2c_ack_err,
		sda 				=>	sda,
		scl				=> scl
	);

	-- UART Module component instantiation
	umd : uart
	generic map
	(
		baud				 		=> umd_baud_r,		-- UART Baud Rate
		clock_frequency 		=> sys_clk_frq		-- System clock speed
	)
	port map
	(
		clock						=>	umd_clock,
		reset						=>	not reset_n,

		-- tx: rx_pin>(UART MODULE)>tx_data>(CTL MODULE)
		-- rx: tx_pin<(UART MODULE)<rx_data<(CTL_MODULE)
		data_stream_in			=>	umd_rx_data,
		data_stream_in_stb	=>	umd_rx_stb,
		data_stream_in_ack	=>	umd_rx_ack,
		data_stream_out		=>	umd_tx_data,
		data_stream_out_stb	=>	umd_tx_stb,
		tx							=>	umd_tx,
		rx							=>	umd_rx
	);

	-- ORA/Camera Module component instantiation
	ora_0 : ora
	generic map
	(
		g_clk_r					=> sys_clk_frq,
		m_clk_r					=> ora_clk_frq,
		thresh 					=> DEFAULT_THRESH,
		kernel 					=>	DEFAULT_KERNEL,
		buffer_c					=>	DEFAULT_AUTO_CORRECT
	)
	port map
	(
		gclk						=>	ora_clock,
		reset_n					=> reset_n,
		ena						=>	cam_ena,
		pwdn						=>	pwdn,
		mclk						=>	mclk,
		vsync						=>	vsync,
		href						=>	href,
		pclk 						=>	pclk,
		cpi						=>	cpi,

		ora_ack					=>	ora_ack,
		ora_has_packet			=> ora_has_packet,
		ora_bytes_to_tx		=> ora_bytes_to_tx,
		ora_packet_buffer		=> ora_packet_buffer,
		
		r_rd_data          	=>	ram_rd_data,
		r_rd_request       	=>	ram_rd_request,
		r_rd_length        	=>	ram_rd_length,
		r_wr_data         	=>	ram_wr_data,
		r_wr_request			=> ram_wr_request,
		r_wr_length        	=>	ram_wr_length,
		r_strobe        		=>	ram_strobe,
		r_request_ack      	=>	ram_request_ack,
		r_burst            	=>	ram_burst,
		r_as               	=>	ram_as,
		r_row              	=>	ram_row,
		r_col              	=>	ram_col
	);
			
	hrddr_0 : hrddr
	generic map
	(
		sys_ck_frequency    	=>	sys_clk_frq,
		ddr_ck_frequency    	=>	ram_clk_frq,
		latency_config			=> ram_lat_config
	)
	port map
	(  
	A => A,
	B => B,
		clock               	=>	ram_clock,
		reset_n             	=>	ram_rst,

		rd_data             	=>	ram_rd_data,
		rd_request         	=>	ram_rd_request,
		rd_length         	=>	ram_rd_length,
		wr_data         		=>	ram_wr_data,
		wr_request				=> ram_wr_request,
		wr_length         	=>	ram_wr_length,
		strobe         		=>	ram_strobe,
		request_ack        	=>	ram_request_ack,

		burst               	=>	ram_burst,
		as                  	=>	ram_as,
		row                 	=>	ram_row,
		col                 	=>	ram_col,
		
		cs_n                	=>	ram_cs_n,
		ck_p                	=>	ram_ck_p,
		ck_n                	=>	ram_ck_n,
		rwds                	=>	ram_rwds,
		dq                  	=>	ram_dq
		
		
	);
	
	--------------------------------------------------------------------------------

end gbehaviour;
