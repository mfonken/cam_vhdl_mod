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

-- Module clocks
signal  	umd_clock         : std_logic       := '0';
signal  	i2c_clock         : std_logic       := '0';
signal  	ora_clock         : std_logic       := '0';

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
signal 	i2c_ena		   	: std_logic;
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
			
			i2c_ena				: out    std_logic;
			i2c_rw    			: out    std_logic	:= '0';
			i2c_wr	  			: out    std_logic_vector( 7 downto 0 );
			i2c_rd				: in     std_logic_vector( 7 downto 0 );
			i2c_bsy				: in     std_logic	:= '0';
			-- i2c_ack_err       : std_logic;

			umd_ena   			: inout 	std_logic := '1';
			umd_rx_data			: inout  std_logic_vector( 7 downto 0 );
			umd_rx_stb 			: inout  std_logic;
			umd_rx_ack 			: inout  std_logic;
			umd_tx_data			: inout  std_logic_vector( 7 downto 0 );
			umd_tx_stb 			: inout  std_logic;

			ora_ena   			: inout 	std_logic	:= '1';
			ora_ack				: inout	std_logic;
			ora_has_packet		: in		std_logic;
			ora_bytes_to_tx	: in 		integer;
			ora_packet_buffer	: inout	packet_buffer_t;
			cam_ena   			: inout  std_logic	:= '1'
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
			g_clk_r		: 			integer;
			m_clk_r		: 			integer;
			thresh    	: 			integer;
			kernel    	: 			kernel_t;
			buffer_c  	: 			auto_correct_t
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
	end component ora;

begin
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
	
		clock					=>	clock,
		reset_n				=>	reset_n,
		
		umd_clock			=> umd_clock,
		i2c_clock			=> i2c_clock,
		ora_clock			=>	ora_clock,

		i2c_ena				=>	i2c_ena,
		i2c_rw   			=>	i2c_rw,
		i2c_wr	 			=>	i2c_wr,
		i2c_rd				=>	i2c_rd,
		i2c_bsy				=>	i2c_bsy,
		-- i2c_ack_err       : std_logic;

		umd_ena   			=>	umd_ena,
		umd_tx_data			=>	umd_tx_data,
		umd_rx_data			=>	umd_rx_data,
		umd_rx_stb 			=> umd_rx_stb,
		umd_rx_ack 			=>	umd_rx_ack,
		umd_tx_stb 			=>	umd_tx_stb,

		ora_ena   			=>	ora_ena,
		ora_ack				=> ora_ack,
		ora_has_packet		=> ora_has_packet,
		ora_bytes_to_tx	=> ora_bytes_to_tx,
		ora_packet_buffer	=> ora_packet_buffer,
		cam_ena				=> cam_ena
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
		A => A,
		B => B,
		gclk						=>	ora_clock,
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
		ora_packet_buffer		=> ora_packet_buffer
	);

	--------------------------------------------------------------------------------

end gbehaviour;
