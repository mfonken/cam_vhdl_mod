----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_integer.all;

-- Global files
use work.global_constants.all;
use work.global_types.all;

-- Camera files
use work.OV9712.all

-- Ora files
use work.ora_constants.all;
use work.ora_types.all;
use work.ora_math.all;

----------------------------------------------
-- Main camera controller entity
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
  rx    		: in    	std_logic;
  tx    		: out  	  std_logic;

  reset		  : in		  std_logic
  );
end C8_Project;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of C8_Project is

-- Module clocks
signal  ucom_clock : std_logic      := '0';
signal  sio_clock  : std_logic      := '0';
signal  ora_clock  : std_logic      := '0';

-- System states
signal  state      : system_states_t   := startup;
signal  next_state : system_states_t   := activate;

-- System flags
signal  shdn       : std_logic       := '0';
signal  reset_sft  : std_logic       := '0';
signal  reset_hrd  : std_logic       := '0';
signal  auto_wake  : std_logic       := '0';

signal  cam_ready  : std_logic       := '0';
signal  has_urx    : std_logic       := '0';
signal  has_utx    : std_logic       := '0';

-- Ora tuning
signal  ora_thresh : integer         := DEFAULT_THRESH;
signal  kernel_idx : std_logic_vector(1 downto 0) := DEFAULT_KERNEL;

-- Uart signals
signal 	rx_data    :  std_logic_vector(7 downto 0);
signal	rx_stb  	 :  std_logic;
signal	rx_ack  	 :  std_logic;
signal	tx_data    :  std_logic_vector(7 downto 0);
signal	tx_stb 	   :  std_logic;

-- Sio signals
signal 	sio_ena		 : 	std_logic;
signal 	sio_rw		 :	std_logic        := '1';
signal 	sio_wr		 :	std_logic_vector( 7 downto 0 );
signal 	sio_rd		 : 	std_logic_vector( 7 downto 0 );
signal	sio_bsy		 : 	std_logic;
signal	sio_ack_er :	std_logic;

begin
	ucom : entity work.uart
	generic map(
		115_200,
		100_000_000
	)
	port map(
		ucom_clock,
		reset,
		rx_data,
		rx_stb,
		rx_ack,
		tx_data,
		tx_stb,
		tx,
		rx
	);

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

	ora : entity work.ora
  generic map(
    DEFAULT_THRESH,
    DEFAULT_KERNEL
  )
	port map(
		ora_clock,
		mclk,
		vsync,
		href,
	  pclk,
		data
	);

  ucom_clock  <= clock;
  sio_clock   <= clock & sio_ena;
  ora_clock   <= clock & cam_ena;

  init_camera : process(clock)
  variable reg_index : integer := 0;
  variable sio_state : sio_tx_states_t := sio_reg_tx;
  begin
    if rising_edge(clock) then
      -- Runs once at startup
      if cam_ready = '0' then
        if reg_index /= DEFAULT_REGS'length then
          cam_ready <= '0';
          sio_ena <= '1';
          if sio_bsy = '0' then
            case sio_state
              when sio_reg_tx =>
                sio_wr  <= DEFAULT_REGS(reg_index).reg;
                sio_state <= sio_val_tx;
              when sio_val_tx =>
                sio_wr  <= DEFAULT_REGS(reg_index).val;
                sio_state <= sio_reg_tx;
            end case;
            reg_index := reg_index + 1;
          end if;
        else
          cam_ready <= '1';
          sio_ena <= '0';
          reg_index <= DEFAULT_REGS'length;
        end if;
      end if;
    end if;
  end process init_camera;

  system_process : process(clock)
  begin

    if rising_edge(clock) then
      case state is

        --  Startup: One-time init
        when startup =>
          cam_en <= '1';
          -- Wait for camera init
          if cam_ready = '1' then
            next_state <= activate;
          else
            next_state <= startup;
          end if;

        -- Activate: Transition to active state
        when activate =>
          cam_en <= '1';
          next_state <= active;

        -- Active: Stable standard operation
        when active =>
          cam_en <= '1';

        -- Deactivate: Transition to standby or shutdown states
        when deactivate =>
          cam_en <= '0';
          if shdn = '0' then
            next_state <= standby;
          else
            next_state <= shutoff;
          end if;

        -- Standby: Stable inactive operation
        when standby =>
          cam_en <= '0';

        -- Shutdown: Impending power-off after ack
        when shutdown =>
          cam_en <= '0';

          --Send deactivation ack
          tx_data <= ucom_cmds_l.ack;
          tx_stb <= '1';

      end case;
      state <= next_state;
    end if;
  end process system_process;

  ucom_listener : process(clock, rx_stb, rx_data)
  variable u_listener_state : ucom_state_t := ucom_standby;
  begin
    if rising_edge(clock) then
      if rx_stb = '1' then
        case rx_data is
          when ucom_cmds_l.wake =>
            shdn <= '0';
            state <= activate;
          when ucom_cmds_l.sleep =>
            shdn <= '0';
            state <= deactivate;
          when ucom_cmds_l.shutoff =>
            shdn <= '1';
            state <= deactivate;
          others =>
            shdn <= '0';
            state <= next_state;
        end case;
      else
        shdn <= '0';
        state <= next_state;
      end if;
    end if;
  end process ucom_listener;

end gbehaviour;
