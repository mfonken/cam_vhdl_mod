---------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Global files
use work.global_constants.all;
use work.global_types.all;

-- UCP package
use work.ucp_lib.all;

--------------------------------------------------------------------------------

----------------------------------------------
-- Main controller entity
----------------------------------------------
entity master is
  generic
    (
      input_clk : integer
    );
	port
    (
      clk				: in 			std_logic;
      reset_n		: inout  	std_logic;

      i2c_ena		: out     std_logic;
      i2c_rw    : out     std_logic;
      i2c_wr	  : out     std_logic_vector( 7 downto 0 );
      i2c_rd		: in      std_logic_vector( 7 downto 0 );
      i2c_bsy		: in      std_logic;
      -- i2c_ack_err       : std_logic;

      umd_ena   : out     std_logic;
      umd_tx    : out     std_logic_vector( 7 downto 0 );
      umd_rx    : in      std_logic_vector( 7 downto 0 );
      umd_r_stb : in      std_logic;
      umd_r_ack : out     std_logic;
      umd_t_stb : out     std_logic;

      ora_ena   : out     std_logic;
      cam_ena   : in      std_logic
      -- ora_rx    : in      std_logic_vector( 23 downto 0 )
    );

end master;

architecture mbehaviour of master is
  -- System states
  signal  	state             : system_states_t   := startup;
  signal  	next_state        : system_states_t   := activate;


  -- System flags
  signal  	shdn              : std_logic         := '0';
  signal  	reset_sft         : std_logic         := '0';
  signal  	reset_hrd         : std_logic         := '0';
  signal  	auto_wake         : std_logic         := '0';

  --signal	cam_ena				: std_logic				:= '0';
  signal  	has_umd_tx        : std_logic        	:= '0';
  signal  	has_umd_rx        : std_logic         := '0';


  -- i2c signals
  signal 		i2c_ena		      	: std_logic;
  signal 		i2c_rw		     		: std_logic;
  signal 		i2c_wr		      	: std_logic_vector( 7 downto 0 );
  signal 		i2c_rd		      	: std_logic_vector( 7 downto 0 );
  signal		i2c_bsy		      	: std_logic;
  signal		i2c_bsy_prev    	: std_logic;
  signal		i2c_ack_err       : std_logic;

  -- Uart signals
  signal		umd_rx_data       : std_logic_vector(7 downto 0);
  signal		umd_rx_stb  	   	: std_logic;
  signal		umd_rx_ack  	   	: std_logic;
  signal		umd_tx_data       : std_logic_vector(7 downto 0);
  signal		umd_tx_stb 	      : std_logic;

  signal    cam_ena           : std_logic         := '0';
  signal  	cam_ready         : std_logic         := '0';
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
  	umd_clock <= clock and umd_ena;
  	i2c_clock <= clock and i2c_ena;
  	ora_clock <= clock and ora_ena;

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
		if rising_edge(clock) then
			if umd_tx_stb = '1' then
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
									next_state <= state;
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
							next_state       <= state;
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
							next_state        <= state;
						when others =>
							hasAck              <= '0';
							hasNack             <= '0';
							ora_thresh_new      <= ora_thresh;
							ora_kernel_new      <= ora_kernel;
							ora_auto_cor_new    <= ora_auto_cor;
							shdn <= '0';
							next_state <= state;
					end case;
				else
					ucp_in              := ( others => '0' );
					hasAck              <= '0';
					hasNack             <= '0';
					ora_thresh_new      <= ora_thresh;
					ora_kernel_new      <= ora_kernel;
					ora_auto_cor_new    <= ora_auto_cor;
					shdn <= '0';
					next_state <= state;
				end if;
			else                                       -- Second byte
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
				next_state  <= state;
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
      if cam_ena = '0' then
        cam_ready <= '0';
      end if;
			-- Runs once every startup startup
			if cam_ena = '1' and cam_ready = '0' then
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
end mbehaviour;
