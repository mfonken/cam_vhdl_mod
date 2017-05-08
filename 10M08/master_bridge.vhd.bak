----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Global files
use work.global_constants.all;
use work.global_types.all;


-- Ora files
use work.ora_constants.all;
use work.ora_types.all;
use work.ora_math.all;

-- Camera files
use work.OV9712.all;

-- UART files
use work.uart.all;
use work.ucp_lib.all;

-- I2C files
use work.i2c_master.all;
--------------------------------------------------------------------------------

----------------------------------------------
-- Main controller entity
----------------------------------------------
entity master_bridge is
	port (
		LED1			: out			std_logic := '0';
		LED2			: out			std_logic := '0';

		-- Global clock
		clock  		: in    	std_logic;

		-- Camera interface
		cam_ena 	: inout 	std_logic;
		mclk     	: inout 	std_logic;
		pwdn			: out			std_logic;
		vsync     : in    	std_logic;
		href      : in    	std_logic;
		pclk      : in    	std_logic;
		cpi       : in    	std_logic_vector( 7 downto 0 );
		sda  			: inout 	std_logic;
		scl  			: inout 	std_logic;

		-- Serial interface
		umd_tx    : in    	std_logic;
		umd_rx    : out  		std_logic;

		-- Synchronous reset (active low)
		reset_n		: in			std_logic
	);
end master_bridge;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of master_bridge is
-- signal		reset_n						: std_logic;

constant 	sys_clk_frq				: integer 					:= 50_000_000;

-- Module clocks
signal  	umd_clock         : std_logic         := '0';
signal  	i2c_clock         : std_logic         := '0';
signal  	ora_clock         : std_logic         := '0';

-- Ora data
signal 		ora_pkt_ct				: integer						:= 0;
signal		ora_data					: std_logic_vector( 7 downto 0 );

-- Ora tuning
constant	ora_clk_r					: integer						:= 10_000_000;
signal  	ora_thresh        : integer           := DEFAULT_THRESH;
signal  	ora_kernel        : kernel_t          := DEFAULT_KERNEL;
signal  	ora_auto_cor      : auto_correct_t    := DEFAULT_AUTO_CORRECT;

signal  	packet_tx_i   		: integer           := 0;
-- signal  	ora_bytes_to_tx  	: integer           := 0;
-- signal  	ora_packet_buffer : packet_buffer_t;
-- signal		ora_has_packet		: std_logic					:= '0';

-- Uart signals
signal		umd_rx_data       : std_logic_vector(7 downto 0);
signal		umd_rx_stb  	   	: std_logic;
signal		umd_rx_ack  	   	: std_logic;
signal		umd_tx_data       : std_logic_vector(7 downto 0);
signal		umd_tx_stb 	      : std_logic;

-- UCP flags/inputs
signal  	prev_umd_rx       : std_logic_vector( 7 downto 0 );
signal  	hasAck            : std_logic         := '0';
signal  	hasNack           : std_logic         := '0';
signal  	ora_thresh_new    : integer           :=  0;
signal  	ora_kernel_new    : kernel_t					:= kernel.pulse_kernel;
signal  	ora_auto_cor_new  : auto_correct_t 		:= auto_correct.auto_cor_none;

-- i2c signals
signal 		i2c_ena		      	: std_logic					:= '0';
signal 		i2c_rw		     		: std_logic       	:= '0';
signal 		i2c_wr		      	: std_logic_vector( 7 downto 0 );
signal 		i2c_rd		      	: std_logic_vector( 7 downto 0 );
signal		i2c_bsy		      	: std_logic;
signal		i2c_bsy_prev    	: std_logic;
signal		i2c_ack_err       : std_logic;

-- COMPONENTS
	component master is
		generic
	    (
	      input_clk : integer
	    );
		port
	    (
	      clk				: in 			std_logic;
	      reset_n		: inout  	std_logic;

	      i2c_ena		: out     std_logic				:= '0';
	      i2c_rw    : out     std_logic       := '0';
	      i2c_wr	  : out     std_logic_vector( 7 downto 0 );
	      i2c_rd		: in      std_logic_vector( 7 downto 0 );
	      i2c_bsy		: in      std_logic;
	      -- i2c_ack_err       : std_logic;

	      umd_ena   : out     std_logic				:= '0';
	      umd_tx    : out     std_logic_vector( 7 downto 0 );
	      umd_rx    : in      std_logic_vector( 7 downto 0 );
	      umd_r_stb : in      std_logic;
	      umd_r_ack : out     std_logic;
	      umd_t_stb : out     std_logic;

	      ora_ena   : out     std_logic				:= '0';
				cam_ena   : in      std_logic
	    );
	end component master;

	component i2c_master is
		generic
			(
				input_clk : integer;
				bus_clk		: integer
			);
		port
			(
				clk				: in 			std_logic;
				reset_n		: in 			std_logic;
				ena				: in 			std_logic;
				addr			: in 			std_logic_vector( 6 downto 0 );
				rw				: in 			std_logic;
				data_wr		: in			std_logic_vector( 7 downto 0 );
				busy			: out 		std_logic := '0';
				data_rd 	: out 		std_logic_vector( 7 downto 0 );
				ack_error : buffer 	std_logic;
				sda				: inout		std_logic;
				scl				: inout		std_logic
			);
	end component i2c_master;

component uart is
	generic
		(
			baud        :   positive;
			clk_frq   	:   positive
		);
	port
		(
			clock       :   in  std_logic;
			reset_n     :   in  std_logic;
			uart_tx     :   in  std_logic_vector(7 downto 0);
			uart_tx_stb	:   in  std_logic;
			uart_tx_ack :   out std_logic;
			uart_rx     :   out std_logic_vector(7 downto 0);
			uart_rx_stb :   out std_logic;
			tx          :   out std_logic;
			rx          :   in  std_logic
		);
	end component uart;

	component ora is
		generic
		(
			g_clk_r			: integer;
			m_clk_r			: integer;
			thresh    	: integer;
			kernel    	: kernel_t;
			buffer_c  	: auto_correct_t
	--		pbuffer   	: packet_buffer_t := ( others => ( others => '0' ) );
	--		hasPacket 	: std_logic			:= '0'
		);
		port
		(
			-- Global clock
			gclk        : in    	std_logic;

			-- Camera interface
			ena					: inout		std_logic	:= '1';
			pwdn				: out			std_logic	:= '1';
			mclk        : inout 	std_logic;
			vsync       : in    	std_logic;
			href        : in    	std_logic;
			pclk        : in    	std_logic;
			cpi         : in    	std_logic_vector( 7 downto 0 )

			ora_pkt_ct	: out			integer 	:= 0;
			ora_data		: out			std_logic_vector( 7 downto 0 )
		);
	end component ora;

begin

	-- Master module component initialization
	master_m : master
	generic map
	(
		input_clk			=> 	sys_clk_frq
	)
	port map
	(
		clk						=>	clock,
		reset_n				=>	reset_n,

		i2c_ena				=>	i2c_ena,
		i2c_rw   			=>	i2c_rw,
		i2c_wr	 			=>	i2c_wr,
		i2c_rd				=>	i2c_rd,
		i2c_bsy				=>	i2c_bsy,
		-- i2c_ack_err       : std_logic;

		umd_ena   		=>	umd_ena,
		umd_tx    		=>	umd_tx_data,
		umd_rx    		=>	umd_rx_data,
		umd_r_stb 		=> 	umd_rx_stb,
		umd_r_ack 		=>	umd_rx_ack,
		umd_t_stb 		=>	umd_tx_stb,

		ora_ena   		=>	ora_ena,
		cam_ena				=> 	cam_ena
	);

	-- I2C Module component instantiation
	i2c_master_0 : i2c_master
	generic map
	(
		input_clk 		=> sys_clk,
		bus_clk				=> i2c_scl_frq
	)
	port map
	(
		clk 					=> 	i2c_clock,
		reset_n 			=>	reset_n,
		ena						=> 	i2c_ena,
		addr					=> 	OV9712_ADDR,
		rw						=> 	i2c_rw,
		data_wr 			=> 	i2c_wr,
		busy  				=> 	i2c_bsy,
		data_rd				=>	i2c_rd,
		ack_error			=> 	i2c_ack_err,
		sda 					=>	sda,
		scl						=> 	scl
	);

	-- UART Module component instantiation
	umd : uart
	generic map
	(
		115_200,		-- UART Baud Rate
		clock_r		-- System clock speed
	)
	port map
	(
		clock					=>	umd_clock,
		reset_n				=>	reset_n,

		-- tx: rx_pin>(UART MODULE)>tx_data>(CTL MODULE)
		-- rx: tx_pin<(UART MODULE)<rx_data<(CTL_MODULE)
		uart_tx				=>	umd_rx_data,
		uart_tx_stb		=>	umd_rx_stb,
		uart_tx_ack		=>	umd_rx_ack,
		uart_rx				=>	umd_tx_data,
		uart_rx_stb		=>	umd_tx_stb,
		rx						=>	umd_rx,
		tx						=>	umd_tx
	);

	-- ORA/Camera Module component instantiation
	ora : ora
	generic map
	(
		g_clk_r				=> 	sys_clk,
		m_clk_r				=> 	ora_clk_frq,
		thresh 				=> 	DEFAULT_THRESH,
		kernel 				=>	DEFAULT_KERNEL,
		buffer_c			=>	DEFAULT_AUTO_CORRECT
	)
	port map
	(
		gclk					=>	ora_clock,
		ena						=>	cam_ena,
		pwdn					=>	pwdn,
		mclk					=>	mclk,
		vsync					=>	vsync,
		href					=>	href,
		pclk 					=>	pclk,
		cpi						=>	cpi

		ora_pkt_ct		=>	ora_pkt_ct,
		ora_data			=> 	ora_data
--		ora_bytes_to_tx,
--		ora_packet_buffer,
--		ora_has_packet
	);

	--------------------------------------------------------------------------------

end gbehaviour;
