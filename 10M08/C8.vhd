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

-- Camera files
use work.OV9712.all;

-- Ora files
use work.ora_constants.all;
use work.ora_types.all;
use work.ora_math.all;

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
  -- Global clock
  clock  	: in    		std_logic;

  -- Camera interface
  mclk      : inout 	std_logic;
  vsync     : in    	std_logic;
  href      : in    	std_logic;
  pclk      : in    	std_logic;
  cpi       : in    	std_logic_vector( 7 downto 0 );
  siod  		: inout 	std_logic;
  sioc  		: inout   std_logic;

  -- Serial interface
  umd_tx    		: in    	std_logic;
  umd_rx    		: out  	  std_logic;

  reset		  : in		  std_logic
  );
end C8_Project;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of C8_Project is

-- Module clocks
signal  umd_clock         : std_logic           := '0';
signal  sio_clock         : std_logic           := '0';
signal  ora_clock         : std_logic           := '0';

-- System states
signal  state             : system_states_t     := startup;
signal  next_state        : system_states_t     := activate;

-- System flags
signal  shdn              : std_logic           := '0';
signal  reset_sft         : std_logic           := '0';
signal  reset_hrd         : std_logic           := '0';
signal  auto_wake         : std_logic           := '0';

signal  cam_ready         : std_logic           := '0';
signal  has_umd_tx        : std_logic           := '0';
signal  has_umd_rx        : std_logic           := '0';

-- Ora tuning
signal  ora_thresh        : integer             := DEFAULT_THRESH;
signal  ora_kernel        : kernel_l            := DEFAULT_KERNEL;
signal  ora_auto_cor      : auto_correct_l      := DEFAULT_AUTO_CORRECT;

signal  packet_umd_rx_i   : integer             := 0;
signal  ora_bytes_to_urx  : integer             := 0;
signal  ora_packet_buffer : packet_buffer_t;

-- Uart signals
signal 	umd_rx_data       : std_logic_vector(7 downto 0);
signal	umd_rx_stb  	    : std_logic;
signal	umd_rx_ack  	    : std_logic;
signal	umd_tx_data       : std_logic_vector(7 downto 0);
signal	umd_tx_stb 	      : std_logic;

-- UCP flags/inputs
signal  new_umd_rx        : std_logic_vector( 7 downto 0 );
signal  hasAck            : std_logic           := '0';
signal  hasNack           : std_logic           := '0';
signal  ora_thresh_new    : integer             :=  0;
signal  ora_kernel_new    : integer             :=  0;
signal  ora_auto_cor_new  : integer             :=  0;

-- Sio signals
signal 	sio_ena		        : std_logic;
signal 	sio_rw		        :	std_logic           := '1';
signal 	sio_wr		        :	std_logic_vector( 7 downto 0 );
signal 	sio_rd		        : std_logic_vector( 7 downto 0 );
signal	sio_bsy		        : std_logic;
signal	sio_ack_er        :	std_logic;



begin

-- UART Module entity map
	umd : entity work.uart
	generic map(
		115_200,
		100_000_000
	)
	port map(
		umd_clock,
		reset,

    -- tx: rx_pin>(UART MODULE)>tx_data>(CTL MODULE)
    -- rx: tx_pin<(UART MODULE)<rx_data<(CTL_MODULE)
		umd_rx_data,
		umd_rx_stb,
		umd_rx_ack,
		umd_tx_data,
		umd_tx_stb,
		umd_rx,
		umd_tx
	);

-- SIO Module entity map
	sio : entity work.i2c_master
	port map(
		sio_clock,
		reset,
		sio_ena,
		OV9712_ADDR,
		sio_rw,
		sio_wr,
		sio_bsy,
		sio_rd,
		sio_ack_err,
		siod,
		sioc
	);

-- ORA/Camera Module entity map
	ora : entity work.ora
  generic map(
    DEFAULT_THRESH,
    DEFAULT_KERNEL,
    ora_bytes_to_umd_rx,
    ora_packet_buffer
  )
	port map(
		ora_clock,
		mclk,
		vsync,
		href,
	  pclk,
		cpi
	);

--------------------------------------------------------------------------------
-- Stateless signal assignments
--------------------------------------------------------------------------------
  umd_clock <= clock;
  sio_clock <= clock and sio_ena;
  ora_clock <= clock and cam_ena;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Main System State Machine
--------------------------------------------------------------------------------
  system_process : process(clock)
  -------------------------------------
  -- Prefered order:
  --  state
  --  cam_en
  --  umd_rx_data
  --  packet_umd_rx_i
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
          cam_en <= '1';

          umd_rx_data <= umd_cmds_l.nack;
          packet_umd_rx_i <= 0;

        -- Activate: Transition to active state
        when activate =>                             -- ACTIVATE
          cam_en <= '1';
          state <= active;

          --Send actiavition/ready for operation ack
          umd_rx_data <= umd_cmds_l.ack;
          packet_umd_rx_i <= 0;
        -- Active: Stable standard operation
        when active =>                               -- ACTIVE
          state <= next_state;
          cam_en  <= '1';

          -- If ora packet has bytes to send and umd_rx line is open the send
          if hasData = '1' and packet_umd_rx_i >= 0 and umd_rx_stb = '0' then
            umd_rx_data <= ora_packet_buffer(packet_umd_rx_i);
            packet_umd_rx_i <= packet_umd_rx_i - 1;
          else
            umd_rx_data <= umd_cmds_l.nack;
            packet_umd_rx_i <= ora_bytes_to_umd_rx;
          end if;

        -- Deactivate: Transition to standby or shutdown states
        when deactivate =>                           -- DEACTIVATE
          if shdn = '0' then
            state <= standby;
          else
            state <= shutoff;
          end if;
          cam_en <= '0';

          umd_rx_data <= umd_cmds_l.nack;
          packet_umd_rx_i <= 0;

        -- Standby: Stable inactive operation
        when standby =>                              -- STANDBY
          state <= next_state;
          cam_en <= '0';
          umd_rx_data <= umd_cmds_l.nack;
          packet_umd_rx_i <= 0;

        -- Shutdown: Impending power-off after ack
        when shutdown =>                             -- SHUTDOWN
          state <= next_state;

          cam_en <= '0';

          --Send deactivation/ready for shutdown ack
          umd_rx_data <= umd_cmds_l.ack;
          packet_umd_rx_i <= 0;

      end case;

      ora_thresh <= ora_thresh_new;
      ora_kernel <= ora_kernel_new;
      ora_auto_cor <= ora_auto_cor_new;
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
        if second_byte = '0' then                -- First byte
          ucp_in := umd_tx_data;

          case ucp_in.hdr is              -- hdr
            when ucp_hdr.sys =>           -- hdr.sys
              case ucp_in.cmd is          -- sys
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
                others =>
                  shdn       <= '0';
                  next_state <= state;
              end case;
              hasAck           <= '0';
              hasNack          <= '0';

              ora_thresh_new   <= ora_thresh;
              ora_kernel_new   <= ora_kernel;
              ora_auto_cor_new <= ora_auto_cor;
            when ucp_hdr.cfg =>           -- hdr.cfg
              second_byte      <= '1';
              curr_cmd         <= ucp_in.cmd;

              hasAck           <= '0';
              hasNack          <= '0';

              ora_thresh_new   <= ora_thresh;
              ora_kernel_new   <= ora_kernel;
              ora_auto_cor_new <= ora_auto_cor;

              shdn             <= '0';
              next_state       <= state;
            when ucp_hdr.dat =>           -- hdr.data
              case ucp_in.cmd is          -- dat
                when ucp_dat.ack =>       -- dat.ack
                  hasAck  <= '1';
                when ucp_dat.nack =>      -- dat.nack
                  hasNack <= '1';
                others =>
                  hasAck  <= '0';
                  hasNack <= '0';
              end case;

              ora_thresh_new    <= ora_thresh;
              ora_kernel_new    <= ora_kernel;
              ora_auto_cor_new  <= ora_auto_cor;

              shdn              <= '0';
              next_state        <= state;
          end case;
        else
          ucp_in              := ( others <= '0' );
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
            ora_thresh_new    <= umd_tx_data;
          when ucp_sys.kernel =>    -- cfg.kernel
            ora_kernel_new    <= umd_tx_data;
          when ucp_sys.auto_cor =>  -- cfg.auto_cor
            ora_auto_cor_new  <= umd_tx_data
          others =>
            ora_thresh_new    <= ora_thresh;
            ora_kernel_new    <= ora_kernel;
            ora_auto_cor_new  <= ora_auto_cor;
        end case;
        ucp_in      := ( others <= '0' );
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
    if umd_rx_data /= prev_umd_rx and umd_rx_data /= umd_cmds_l.nack then
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
  init_camera : process(clock)
  variable reg_index : integer := 0;
  variable sio_state : sio_tx_states_t := sio_reg_tx;
  -------------------------------------
  -- Prefered order:
  --  cam_ready
  --  sio_ena
  --  sio_wr
  --  sio_state
  --  reg_index
  -------------------------------------
  begin
    if rising_edge(clock) then
      -- Runs once at startup
      if cam_ready = '0' then
        if reg_index /= DEFAULT_REGS'length then
          cam_ready <= '0';
          sio_ena   <= '1';
          if sio_bsy = '0' then
            case sio_state
              when sio_reg_umd_rx =>
                sio_wr    <= DEFAULT_REGS(reg_index).reg;
                sio_state := sio_val_tx;
              when sio_val_umd_rx =>
                sio_wr    <= DEFAULT_REGS(reg_index).val;
                sio_state := sio_reg_tx;
            end case;
            reg_index := reg_index + 1;
          end if;
        else
          cam_ready <= '1';
          sio_ena   <= '0';
          sio_wr    <= ( others => '0' );
          sio_state := sio_standby;
          reg_index := DEFAULT_REGS'length;
        end if;
      end if;
    end if;
  end process init_camera;
--------------------------------------------------------------------------------

end gbehaviour;
