---------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Global files
use work.global_types.all;
use work.ora_types.all;

-- UCP package
use work.ucp_lib.all;

-- Camera files
use work.OV9712.all;

--------------------------------------------------------------------------------

----------------------------------------------
-- Main controller entity
----------------------------------------------
entity master is
  generic
    (
      input_clk 	:	 			integer
    );
	port
    (
		LED1	: out	std_logic := '1';
		LED2	: out	std_logic := '1';
		LED3	: out	std_logic := '1';
		LED4	: out	std_logic := '1';
		LED5	: out	std_logic := '1';
		
		clock					: in 			std_logic;
      reset_n				: inout  	std_logic;
		
		umd_clock			: inout 		std_logic;
		i2c_clock			: inout 		std_logic;
		ora_clock			: inout 		std_logic;
		ram_clock			: inout		std_logic;

      i2c_ena				: out     	std_logic;
      i2c_rw    			: out     	std_logic;
      i2c_wr	  			: out     	std_logic_vector( 7 downto 0 );
      i2c_rd				: in      	std_logic_vector( 7 downto 0 );
      i2c_bsy				: in      	std_logic;
      -- i2c_ack_err       : std_logic;

		
      umd_ena   			: inout   	std_logic;
      umd_rx_data			: inout    	std_logic_vector( 7 downto 0 );
      umd_rx_stb 			: inout    	std_logic;
      umd_rx_ack 			: inout     std_logic;
		umd_tx_data			: inout     std_logic_vector( 7 downto 0 );
      umd_tx_stb 			: inout     std_logic;

      ora_ena   			: inout   	std_logic;
		ora_ack				: inout		std_logic;
		ora_has_packet		: in			std_logic;
		ora_bytes_to_tx	: in 			integer;
		ora_packet_buffer	: inout		packet_buffer_t;
		
      cam_ena   			: inout   	std_logic;
		
		ram_ena				: inout		std_logic
    );

end master;

architecture mbehaviour of master is
	-- System states
	signal  	state             : system_states_t := startup;
	signal  	next_state        : system_states_t := activate;
	signal  	state_lock        : system_states_t := live;

	signal	ora_thresh			: integer;
	signal	ora_kernel    		: kernel_t			:= ( others => '0' );
	signal	ora_auto_cor		: auto_correct_t	:= ( others => '0' );
	signal	ora_thresh_new		: integer;
	signal	ora_kernel_new		: kernel_t			:= ( others => '0' );
	signal	ora_auto_cor_new	: auto_correct_t	:= ( others => '0' );
--		pbuffer   	: packet_buffer_t := ( others => ( others => '0' ) );

	signal	i2c_bsy_prev		: std_logic			:= '0';
	
	-- System flags
	signal  	shdn              : std_logic       := '0';
	signal  	reset_sft         : std_logic       := '0';
	signal  	reset_hrd         : std_logic       := '0';
	signal  	auto_wake         : std_logic       := '0';

	signal  	has_umd_tx        : std_logic      	:= '0';
	signal  	has_umd_rx        : std_logic       := '0';
	
	signal	hasAck				: std_logic			:= '0';
	signal	hasNack				: std_logic 		:= '0';

	signal	packet_tx_i			: integer			range 0 to UART_BUFFER_LENGTH := 0;

	-- Uart signals
	signal	prev_umd_rx			: std_logic_vector(7 downto 0);

	signal	ora_bytes_txd		: integer	:= 0;
	
	--  signal    cam_ena           : std_logic         := '0';
	signal  	cam_ready         : std_logic         := '0';
  
  begin
	umd_clock <= clock and umd_ena and reset_n;
  	i2c_clock <= clock and reset_n;-- and i2c_ena;
  	ora_clock <= clock and ora_ena and reset_n;
	ram_clock <= clock and ram_ena and reset_n;
  
	ram_ena <= '1';
	ora_ena <= '1';
	umd_ena <= '1';
--	LED1 <= not ( umd_ena and reset_n );
--	LED2 <= not ( cam_ready and reset_n );
--	LED5 <= not ( i2c_ena and reset_n );
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
    --------------------------------------------------------------------------------
  	-- Stateless signal assignments
  	--------------------------------------------------------------------------------
		if rising_edge(clock) then
			if umd_rx_ack = '1' then
				umd_rx_stb <= '0';
			end if;
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

					umd_rx_stb <= '1';
					umd_rx_data <= ucp_hdr.dat & ucp_dat.nack & ucp_ftr.slv;
					packet_tx_i <= 0;

				-- Activate: Transition to live state
				when activate =>                             -- ACTIVATE
					cam_ena <= '1';
					state <= live;
					state_lock <= live;
					--Send actiavition/ready for operation ack
					umd_rx_stb 	<= '0';
					umd_rx_data <= x"41";
					packet_tx_i <= 0;

				-- live: Stable standard operation
				when live =>                               -- live
					state 	<= next_state;
					cam_ena 	<= '1';--not ora_ack;

					-- If ora packet has bytes to send and umd_rx line is open the send
					if ora_has_packet = '1' then
						packet_tx_i <= ora_bytes_to_tx;
						ora_ack <= '1';
					elsif ora_ack = '1' and umd_rx_stb = '0' then
						if packet_tx_i >= 1 then
							umd_rx_stb <= '1';
							umd_rx_data <= ora_packet_buffer(packet_tx_i-1);--std_logic_vector(to_unsigned(packet_tx_i,8));
							packet_tx_i <= packet_tx_i - 1;
							ora_ack <= '1';
						else
							ora_ack <= '0';
						end if;
					elsif umd_rx_ack = '1' then
						umd_rx_stb <= '0';
					end if;

				-- Deactivate: Transition to standby or shutdown states
				when deactivate =>                           -- DEACTIVATE
					if shdn = '0' then
						state <= standby;
						state_lock <= standby;
					else
						state <= shutdown;
						state_lock <= shutdown;
					end if;
					cam_ena <= '0';

					umd_rx_stb <= '1';
					umd_rx_data <= ucp_hdr.dat & ucp_dat.nack & ucp_ftr.slv;
					packet_tx_i <= 0;

				-- Standby: Stable inlive operation
				when standby =>                              -- STANDBY
					state <= next_state;
					cam_ena <= '0';
					
					umd_rx_stb <= '1';
					umd_rx_data <= ucp_hdr.dat & ucp_dat.nack & ucp_ftr.slv;
					packet_tx_i <= 0;

				-- Shutdown: Impending power-off after ack
				when shutdown =>                             -- SHUTDOWN
					state <= next_state;

					cam_ena <= '0';

					--Send deactivation/ready for shutdown ack
					umd_rx_stb <= '1';
					umd_rx_data <= ucp_hdr.dat & ucp_dat.ack & ucp_ftr.slv;
					packet_tx_i <= 0;
			end case;
			ora_thresh 		<= ora_thresh_new;
			ora_kernel 		<= ora_kernel_new;
			ora_auto_cor 	<= ora_auto_cor_new;
		end if;
	end process system_process;
	--------------------------------------------------------------------------------

	--------------------------------------------------------------------------------
	-- UART Echo Handler
	--------------------------------------------------------------------------------
--	echo_process : process(umd_clock)
--	variable tx_byte : std_logic := '0';
--	begin
--		if rising_edge(umd_clock) then
--			if tx_byte = '0' then
--				tx_byte := '1';
--				umd_rx_stb <= '1';
--				umd_rx_data <= umd_tx_data;
--			elsif umd_rx_ack = '1' then
--				umd_rx_stb <= '0';
--			end if;
--		
--			if umd_tx_stb = '1' then
--				tx_byte := '0';
--			end if;
--		end if;
--	end process echo_process;
	
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
		if rising_edge(clock) then
			if umd_tx_stb = '1' then
				LED3 <= '0';
				if umd_tx_data = x"57" then
					LED4 <= '0';
				else
					LED4 <= '1';
				end if;
				if second_byte = '0' then         -- First byte
					ucp_in := umd_tx_data;
					
					case ucp_in( 7 downto 5 ) is              -- hdr
						when ucp_hdr.sys =>           -- hdr.sys
							case ucp_in( 4 downto 1 ) is          -- sys
								when ucp_sys.wake =>      -- sys.wake
									shdn       <= '0';
									next_state <= activate;
								when ucp_sys.sleep =>     -- sys.sleep
									shdn       <= '0';
									next_state <= deactivate;
								when ucp_sys.shutoff =>   -- sys.shutdown
									shdn       <= '1';
									next_state <= deactivate;
								when ucp_sys.fatal =>     -- sys.fatal
									shdn       <= '1';
									next_state <= deactivate;
								when others =>
									shdn       <= '0';
									next_state <= state_lock;
							end case;

							second_byte      := '0';
							curr_cmd         := ( others => '0' );

							hasAck           <= '0';
							hasNack          <= '0';

							ora_thresh_new   <= ora_thresh;
							ora_kernel_new   <= ora_kernel;
							ora_auto_cor_new <= ora_auto_cor;
						when ucp_hdr.cfg =>           -- hdr.cfg
							second_byte      := '1';
							curr_cmd         := ucp_in( 4 downto 1 );

							hasAck           <= '0';
							hasNack          <= '0';

							ora_thresh_new   <= ora_thresh;
							ora_kernel_new   <= ora_kernel;
							ora_auto_cor_new <= ora_auto_cor;

							shdn             <= '0';
							next_state       <= state_lock;
						when ucp_hdr.dat =>           -- hdr.data
							second_byte      := '0';
							curr_cmd         := ( others => '0' );
							case ucp_in( 4 downto 1 ) is          -- dat
								when ucp_dat.ack =>       -- dat.ack
									hasAck  <= '1';
								when ucp_dat.nack =>      -- dat.nack
									hasNack <= '1';
								when others =>
									hasAck  <= '0';
									hasNack <= '0';
							end case;

							ora_thresh_new    <= ora_thresh;
							ora_kernel_new    <= ora_kernel;
							ora_auto_cor_new  <= ora_auto_cor;

							shdn              <= '0';
							next_state        <= state_lock;
						when others =>
							hasAck              <= '0';
							hasNack             <= '0';
							ora_thresh_new      <= ora_thresh;
							ora_kernel_new      <= ora_kernel;
							ora_auto_cor_new    <= ora_auto_cor;
							shdn <= '0';
							next_state <= state_lock;
					end case;
				else						-- Second byte
					ucp_in              := ( others => '0' );
					hasAck              <= '0';
					hasNack             <= '0';
					ora_thresh_new      <= ora_thresh;
					ora_kernel_new      <= ora_kernel;
					ora_auto_cor_new    <= ora_auto_cor;
					shdn <= '0';
					next_state <= state_lock;
				end if;
			else                                       
				LED3 <= '1';
				case curr_cmd is          -- cfg
					when ucp_cfg.thresh =>    -- cfg.thresh
						ora_thresh_new    <= to_integer( unsigned( umd_tx_data ) );
					when ucp_cfg.kernel => -- cfg.kernel
						ora_kernel_new    <= umd_tx_data( 3 downto 0 );
					when ucp_cfg.auto_cor =>  -- cfg.auto_cor
						ora_auto_cor_new  <= umd_tx_data( 1 downto 0 );
					when others =>
						ora_thresh_new    <= ora_thresh;
						ora_kernel_new    <= ora_kernel;
						ora_auto_cor_new  <= ora_auto_cor;
				end case;
				ucp_in      := ( others => '0' );
				second_byte := '0';
				curr_cmd    := ( others => '0' );
				hasAck      <= '0';
				hasNack     <= '0';
				shdn        <= '0';
				next_state  <= state_lock;
			end if;
		end if;
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
--		if umd_rx_data /= prev_umd_rx and umd_rx_data /= ucp_dat.nack then
--			umd_rx_stb  <= '1';
--		else
--			umd_rx_stb  <= '0';
--		end if;
--		prev_umd_rx   <= umd_rx_data;
	end process umd_handler;
	--------------------------------------------------------------------------------

	--------------------------------------------------------------------------------
	-- Camera Initializer
	--------------------------------------------------------------------------------
	init_camera : process(reset_n, i2c_clock)
	variable reg_index 		: integer := 0;
	variable i2c_busy_cnt 	: integer := 0;  --keeps track of i2c busy signals during transaction
	-------------------------------------
	-- Prefered order:
	--  cam_ready
	--  i2c_ena
	--  i2c_wr
	--  i2c_state
	--  reg_index
	-------------------------------------
	begin
		if reset_n = '0' then
			i2c_busy_cnt 	:= 0;
			i2c_ena 			<= '0';
			cam_ready 		<= '0';
		elsif rising_edge(i2c_clock) then
			if cam_ready = '0' then
				i2c_bsy_prev <= i2c_bsy;                      --capture the value of the previous i2c busy signal
				if i2c_bsy_prev = '0' and i2c_bsy = '1' then --i2c busy just went high
					i2c_busy_cnt := i2c_busy_cnt + 1;             --counts the times busy has gone from low to high during transaction
				end if;

				case i2c_busy_cnt is
					when 0 =>
						i2c_ena   	<= '1';
						i2c_rw		<= '0';
						i2c_wr    	<= DEFAULT_REGS(reg_index).reg;
					when 1 =>
						i2c_ena 		<= '1';
						i2c_rw 		<= '0';
						i2c_wr    	<= DEFAULT_REGS(reg_index).val;
					when 2 =>
						i2c_ena 		<= '0';
						if i2c_bsy = '0' then
							i2c_busy_cnt 	:= 0;
							cam_ready <= '1';	
							if reg_index < 2 then
								reg_index := reg_index + 1;
							else
								cam_ready <= '1';	
							end if;
						end if;
					when others => null;
				end case;
			end if;
		end if;
	end process init_camera;
end mbehaviour;
