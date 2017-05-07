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
entity C8_Project is
	port (
		LED1			: out		std_logic := '0';
		LED2			: out		std_logic := '0';

		-- Global clock
		clock  		: in    	std_logic;

		-- Camera interface
		cam_ena 	: inout 	std_logic;
		mclk     	: inout 	std_logic;
		pwdn			: out		std_logic;
		vsync     : in    	std_logic;
		href      : in    	std_logic;
		pclk      : in    	std_logic;
		cpi       : in    	std_logic_vector( 7 downto 0 );
		sda  			: inout 	std_logic;
		scl  			: inout  std_logic;

		-- Serial interface
		umd_tx    : in    	std_logic;
		umd_rx    : out  	std_logic;

		reset_n		: in		std_logic
	);
end C8_Project;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of C8_Project is
-- signal		reset_n						: std_logic;

constant 	clock_r						: integer 					:= 50_000_000;
-- Module clocks
signal  	umd_clock         : std_logic         := '0';
signal  	i2c_clock         : std_logic         := '0';
signal  	ora_clock         : std_logic         := '0';

-- System states
signal  	state             : system_states_t   := startup;
signal  	next_state        : system_states_t   := activate;

-- System flags
signal  	shdn              : std_logic         := '0';
signal  	reset_sft         : std_logic         := '0';
signal  	reset_hrd         : std_logic         := '0';
signal  	auto_wake         : std_logic         := '0';

--signal	cam_ena				: std_logic				:= '0';
signal  	cam_ready         : std_logic         := '0';
signal  	has_umd_tx        : std_logic        	:= '0';
signal  	has_umd_rx        : std_logic         := '0';

-- Ora tuning
constant	ora_clk_r					: integer						:= 10_000_000;
signal  	ora_thresh        : integer           := DEFAULT_THRESH;
signal  	ora_kernel        : kernel_t          := DEFAULT_KERNEL;
signal  	ora_auto_cor      : auto_correct_t    := DEFAULT_AUTO_CORRECT;

signal  	packet_tx_i   		: integer           := 0;
signal  	ora_bytes_to_tx  	: integer           := 0;
signal  	ora_packet_buffer : packet_buffer_t;
signal		ora_has_packet		: std_logic					:= '0';

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
			baud              :   positive;
			clock_frequency   :   positive
		);
	port
		(
			clock             :   in  std_logic;
			reset_n           :   in  std_logic;
			d_str_in          :   in  std_logic_vector(7 downto 0);
			d_str_in_stb      :   in  std_logic;
			d_str_in_ack      :   out std_logic;
			d_str_out         :   out std_logic_vector(7 downto 0);
			d_str_out_stb     :   out std_logic;
			tx                :   out std_logic;
			rx                :   in  std_logic
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
		);
	end component ora;

begin

	LED1 <= i2c_ena;
	reset <= not reset_n;
	-- UART Module entity map
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
		d_str_in			=>	umd_rx_data,
		d_str_in_stb	=>	umd_rx_stb,
		d_str_in_ack	=>	umd_rx_ack,
		d_str_out			=>	umd_tx_data,
		d_str_out_stb	=>	umd_tx_stb,
		rx						=>	umd_rx,
		tx						=>	umd_tx
	);

	i2c_master_0 : i2c_master
	generic map
	(
		input_clk 		=> sys_clk,
		bus_clk				=> i2c_scl_frq
	)
	port map
	(
		clk 					=> 	i2c_clock,
		reset_n 			=>	reset,
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

	-- ORA/Camera Module entity map
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
--		ora_bytes_to_tx,
--		ora_packet_buffer,
--		ora_has_packet
	);

	--------------------------------------------------------------------------------
	-- Stateless signal assignments
	--------------------------------------------------------------------------------
	umd_clock <= clock;
	i2c_clock <= clock and i2c_ena;
	ora_clock <= clock and cam_ena;
	--------------------------------------------------------------------------------

	--------------------------------------------------------------------------------
	-- Main System State Machine
	--------------------------------------------------------------------------------
	system_process : process(clock)
	-------------------------------------
	-- Prefered order:
	--  state
	--  cam_ena
	--  umd_rx_data
	--  packet_tx_i
	-------------------------------------
	begin
		if rising_edge(clock) then
			case state is
				--  Startup: One-time init
				when startup =>                              -- STARTUP
					-- Wait for camera init
					if cam_ready = '1' then
						state <= activate;
					else
						state <= startup;
					end if;
					cam_ena <= '1';

					umd_rx_data <= "000" & ucp_dat.nack & "0";
					packet_tx_i <= 0;

				-- Activate: Transition to active state
				when activate =>                             -- ACTIVATE
					cam_ena <= '1';
					state <= active;

					--Send actiavition/ready for operation ack
					umd_rx_data <= "111" & ucp_dat.ack & "1";
					packet_tx_i <= 0;

				-- Active: Stable standard operation
				when active =>                               -- ACTIVE
					state 	<= next_state;
					cam_ena <= '1';

					-- If ora packet has bytes to send and umd_rx line is open the send
					if ora_has_packet = '1' and packet_tx_i >= 0 and umd_rx_stb = '0' then
						umd_rx_data <= ora_packet_buffer(packet_tx_i);
						packet_tx_i <= packet_tx_i - 1;
					else
						umd_rx_data <= "000" & ucp_dat.nack & "0";
						packet_tx_i <= ora_bytes_to_tx;
					end if;

				-- Deactivate: Transition to standby or shutdown states
				when deactivate =>                           -- DEACTIVATE
					if shdn = '0' then
						state <= standby;
					else
						state <= shutdown;
					end if;
					cam_ena <= '0';

					umd_rx_data <= "000" & ucp_dat.nack & "0";
					packet_tx_i <= 0;

				-- Standby: Stable inactive operation
				when standby =>                              -- STANDBY
					state <= next_state;
					cam_ena <= '0';
					umd_rx_data <= "000" & ucp_dat.nack & "0";
					packet_tx_i <= 0;

				-- Shutdown: Impending power-off after ack
				when shutdown =>                             -- SHUTDOWN
					state <= next_state;

					cam_ena <= '0';

					--Send deactivation/ready for shutdown ack
					umd_rx_data <= "111" & ucp_dat.ack & "1";
					packet_tx_i <= 0;
			end case;
			ora_thresh 		<= ora_thresh_new;
			ora_kernel 		<= ora_kernel_new;
			ora_auto_cor 	<= ora_auto_cor_new;
		end if;
	end process system_process;
	--------------------------------------------------------------------------------

	--------------------------------------------------------------------------------
	-- UART MODULE Input Handler
	--------------------------------------------------------------------------------
	umd_listener : process(clock, umd_tx_stb, umd_tx_data)
	variable u_listener_state : umd_state_t := umd_standby;
	variable ucp_in : ucp_t;
	variable curr_cmd : ucp_cmd_t;
	variable second_byte : std_logic := '0';
	-------------------------------------
	-- Prefered order:
	--  ucp_in
	--	 second_byte
	--	 curr_cmd
	--  hasAck
	--  hasNack
	--  ora_thresh_new
	--  ora_kernel_new
	--  ora_auto_cor_news
	--  shdn
	--  next_state
	-------------------------------------
	begin
--		if rising_edge(clock) then
--			if umd_tx_stb = '1' then
--				if second_byte = '0' then         -- First byte
--					ucp_in := umd_tx_data;
--
--					case ucp_in( 7 downto 5 ) is              -- hdr
--						when ucp_hdr.sys =>           -- hdr.sys
--							case ucp_in( 4 downto 1 ) is          -- sys
--								when ucp_sys.wake =>      -- sys.wake
--									shdn       <= '0';
--									next_state <= activate;
--								when ucp_sys.sleep =>     -- sys.sleep
--									shdn       <= '0';
--									next_state <= deactivate;
--								when ucp_sys.shutoff =>   -- sys.shutdown
--									shdn       <= '1';
--									next_state <= deactivate;
--								when ucp_sys.fatal =>     -- sys.fatal
--									shdn       <= '1';
--									next_state <= deactivate;
--								when others =>
--									shdn       <= '0';
--									next_state <= state;
--							end case;
--
--							second_byte      := '0';
--							curr_cmd         := ( others => '0' );
--
--							hasAck           <= '0';
--							hasNack          <= '0';
--
--							ora_thresh_new   <= ora_thresh;
--							ora_kernel_new   <= ora_kernel;
--							ora_auto_cor_new <= ora_auto_cor;
--						when ucp_hdr.cfg =>           -- hdr.cfg
--							second_byte      := '1';
--							curr_cmd         := ucp_in( 4 downto 1 );
--
--							hasAck           <= '0';
--							hasNack          <= '0';
--
--							ora_thresh_new   <= ora_thresh;
--							ora_kernel_new   <= ora_kernel;
--							ora_auto_cor_new <= ora_auto_cor;
--
--							shdn             <= '0';
--							next_state       <= state;
--						when ucp_hdr.dat =>           -- hdr.data
--							second_byte      := '0';
--							curr_cmd         := ( others => '0' );
--							case ucp_in( 4 downto 1 ) is          -- dat
--								when ucp_dat.ack =>       -- dat.ack
--									hasAck  <= '1';
--								when ucp_dat.nack =>      -- dat.nack
--									hasNack <= '1';
--								when others =>
--									hasAck  <= '0';
--									hasNack <= '0';
--							end case;
--
--							ora_thresh_new    <= ora_thresh;
--							ora_kernel_new    <= ora_kernel;
--							ora_auto_cor_new  <= ora_auto_cor;
--
--							shdn              <= '0';
--							next_state        <= state;
--						when others =>
--							hasAck              <= '0';
--							hasNack             <= '0';
--							ora_thresh_new      <= ora_thresh;
--							ora_kernel_new      <= ora_kernel;
--							ora_auto_cor_new    <= ora_auto_cor;
--							shdn <= '0';
--							next_state <= state;
--					end case;
--				else
--					ucp_in              := ( others => '0' );
--					hasAck              <= '0';
--					hasNack             <= '0';
--					ora_thresh_new      <= ora_thresh;
--					ora_kernel_new      <= ora_kernel;
--					ora_auto_cor_new    <= ora_auto_cor;
--					shdn <= '0';
--					next_state <= state;
--				end if;
--			else                                       -- Second byte
--				case curr_cmd is          -- cfg
--					when ucp_cfg.thresh =>    -- cfg.thresh
--						ora_thresh_new    <= to_integer( unsigned( umd_tx_data ) );
--					when ucp_cfg.kernel => -- cfg.kernel
--						ora_kernel_new    <= umd_tx_data( 3 downto 0 );
--					when ucp_cfg.auto_cor =>  -- cfg.auto_cor
--						ora_auto_cor_new  <= umd_tx_data( 1 downto 0 );
--					when others =>
--						ora_thresh_new    <= ora_thresh;
--						ora_kernel_new    <= ora_kernel;
--						ora_auto_cor_new  <= ora_auto_cor;
--				end case;
--				ucp_in      := ( others => '0' );
--				second_byte := '0';
--				curr_cmd    := ( others => '0' );
--				hasAck      <= '0';
--				hasNack     <= '0';
--				shdn        <= '0';
--				next_state  <= state;
--			end if;
--		end if;
	end process umd_listener;
	--------------------------------------------------------------------------------

	--------------------------------------------------------------------------------
	-- UART MODULE Output Handler
	--------------------------------------------------------------------------------
	umd_handler : process(clock, umd_rx_stb, umd_rx_data)
	variable u_handler_state : umd_state_t := umd_standby;
	-------------------------------------
	-- Prefered order:
	--  umd_rx_stb
	--  prev_umd_rx
	-------------------------------------
	begin
		--- TODO: Please finish
		if umd_rx_data /= prev_umd_rx and umd_rx_data /= ucp_dat.nack then
			umd_rx_stb  <= '1';
		else
			umd_rx_stb  <= '0';
		end if;
		prev_umd_rx   <= umd_rx_data;
	end process umd_handler;
	--------------------------------------------------------------------------------

	--------------------------------------------------------------------------------
	-- Camera Initializer
	--------------------------------------------------------------------------------
	init_camera : process(i2c_clock)
	variable reg_index : integer := 0;
	variable i2c_state : i2c_tx_states_t := i2c_reg_tx;
	variable i2c_busy_cnt : integer := 0;  --keeps track of i2c busy signals during transaction
	-------------------------------------
	-- Prefered order:
	--  cam_ready
	--  i2c_ena
	--  i2c_wr
	--  i2c_state
	--  reg_index
	-------------------------------------
	begin
		if rising_edge(i2c_clock) then
			-- Runs once at startup
			if cam_ready = '0' then
				if reg_index /= DEFAULT_REGS'length then
					cam_ready <= '0';

					i2c_bsy_prev <= i2c_bsy;                      --capture the value of the previous i2c busy signal
					if i2c_bsy_prev = '0' and i2c_busy = '1') then --i2c busy just went high
						i2c_busy_cnt := i2c_busy_cnt + 1;             --counts the times busy has gone from low to high during transaction
					end if;

					case i2c_busy_cnt is
						when 0 =>
							i2c_ena   <= '1';
							i2c_wr    <= DEFAULT_REGS(reg_index).reg;
							i2c_state := i2c_val_tx;
						when 1 =>
							i2c_ena 	<= '1';
							i2c_wr    <= DEFAULT_REGS(reg_index).val;
							i2c_rw 		<= '0';
							i2c_state := i2c_reg_tx;
						when 2 =>
							i2c_ena <= '0';
							i2c_busy_cnt := 0;
							reg_index := reg_index + 1;
						when others =>
							i2c_wr    <= ( others => '0' );
							i2c_state := i2c_standby;
					end case;


				else
					cam_ready <= '1';
					i2c_ena   <= '0';
					i2c_wr    <= ( others => '0' );
					i2c_state := i2c_standby;
					reg_index := DEFAULT_REGS'length;
				end if;
			end if;
		end if;
	end process init_camera;
	--------------------------------------------------------------------------------

end gbehaviour;
