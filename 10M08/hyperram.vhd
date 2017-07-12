-------------------------------------------------------------------------------
-- HyperRAM DDR
-- Implements the HyperBus interface
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.hyperram_types.all;

entity hyperram is
	generic (
		sys_ck_frequency  : positive;
		ddr_ck_frequency  : positive;
		latency_config		: positive
	);
	port (
		A	: inout std_logic := '0';
		B	: inout std_logic := '0';
		clock            	: in    	std_logic;
		reset_n           : in    	std_logic;

		rd_data           : out   	std_logic_vector(  15 downto 0 );
		rd_request        : in		std_logic;
		rd_length         : in   	std_logic_vector(  7 downto 0 );

		wr_data           : in    	std_logic_vector(  15 downto 0 );
		wr_request        : in    	std_logic;
		wr_length         : in   	std_logic_vector(  7 downto 0 );

		busy					: inout		std_logic;

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
end hyperram;

architecture rtl of hyperram is
	constant 	ddr_ck_div : integer := sys_ck_frequency / ( ddr_ck_frequency * 2 );
	constant 	ddr_ck_div_width : integer := ddr_ck_div / 2;
	signal   	ddr_ck_div_counter : unsigned(ddr_ck_div_width - 1 downto 0) := (others => '0');
	constant 	lv : std_logic := '0';
	constant		MAX_BURST : integer := 1024;
	signal		latency : integer range 1 to 2 := 1;

	type machine is(idle, command, latency_delay, wr, rd ); --needed states
	signal state         : machine := idle;

	signal ca      : ca_64MB_t;
	signal ca_bfr  : std_logic_vector( 47 downto 0 );

	signal internal_data_out  : std_logic_vector( 7 downto 0 );
	signal tick_counter       : integer;

	--  type hrddr_byte_stream_t is array( MAX_BURST downto 0) of std_logic_vector( 7 downto 0 );
	signal internal_data_in   : std_logic_vector( 7 downto 0 );
	signal internal_data_in_l : integer range 0 to MAX_BURST;
	signal ck_ena             : std_logic := '0';

	signal internal_clock			: std_logic := '0';
	signal internal_clock_prev		: std_logic := '0';

	signal strobe_prev  : std_logic := '0';
	signal rwds_prev : std_logic := '0';
	signal ck_prev   : std_logic := '0';

begin

ca.as     <= as;
ca.burst  <= burst;
ca.row    <= row;
ca.col_u  <= col( 8 downto 3 );
ca.col_l  <= col( 2 downto 0 );
ca.rsv1   <= ( others => '0' );
ca.rsv2   <= ( others => '0' );
ca_bfr    <= ca.r_wn & ca.as & ca.burst & ca.rsv1 & ca.row & ca.col_u & ca.rsv2 & ca.col_l;

cs_n				<= not busy;
request_ack 	<= busy;


A <= busy;
---------------------------------------------------------------------------
-- OVERSAMPLE_CLOCK_DIVIDER
-- generate an oversampled tick (baud * 16)
---------------------------------------------------------------------------
	clock_divider : process (clock)
	begin
		if rising_edge (clock) then
			if reset_n = '0' then    -- Sync reset or ram not selected
				ddr_ck_div_counter <= (others => '0');
				internal_clock <= '0';
			else
				ddr_ck_div_counter <= ddr_ck_div_counter + 1;
				if ddr_ck_div_counter < ddr_ck_div_width then
					internal_clock <= '0';
				elsif ddr_ck_div_counter < ddr_ck_div then
					internal_clock <= '1';
				else
					ddr_ck_div_counter <= ( others => '0' );
				end if;
			end if;
--			internal_clock_prev <= internal_clock;
		end if;
	end process clock_divider;
	
	clock_driver : process (internal_clock)
	begin
		if rising_edge (internal_clock) then
			if busy = '1' then
				ck_p <= not ck_p;
				ck_n <= ck_p;
			else
				ck_p <= '0';
				ck_n <= '1';
			end if;
		end if;
	end process clock_driver;

	hrddr_process : process(internal_clock)
	variable tick_counter    : integer range 0 to 6 := 6;
	variable latency_counter : integer range 0 to latency_config*4 := 0;
	variable data_counter    : integer range 0 to MAX_BURST;
	begin
	if falling_edge(internal_clock) then-- internal_clock_prev /= internal_clock then
		if reset_n = '0' then
			busy <= '1';
			rwds <= 'Z';
			dq <= ( others => 'Z' );
			tick_counter 		:= 0;
			latency_counter 	:= 0;
			data_counter 		:= 0;
			state <= idle;
		else
			case state is
				when idle =>
					B <= '0';

					busy <= '0';
					rwds <= 'Z';
					dq <= ( others => 'Z' );
					tick_counter := 6;
					latency_counter := 0;

					if wr_request = '1' then
						ca.r_wn <= hyperram_command.write_command;
						data_counter := to_integer( unsigned( wr_length ) );
						state <= command;
					elsif rd_request = '1' then
						ca.r_wn <= hyperram_command.read_command;
						data_counter := to_integer( unsigned( rd_length ) );
						state <= command;
					else
						ca.r_wn <= '0';
						data_counter := 0;
						state <= idle;
					end if;

				when command =>
					B <= '1';
			
					busy <= '1';
					rwds <= 'Z';

					tick_counter := tick_counter - 1;
					dq <= ca_bfr( tick_counter*8 + 7 downto tick_counter*8 ); --TX command-address (6 clock events) std_logic_vector(to_unsigned(tick_counter, 8));

					if tick_counter = 0 then
						if ca.as = hyperram_command.register_space and ca.r_wn = hyperram_command.write_command then -- if writing to register space
							state <= wr;                     -- write without latency
						else
							state <= latency_delay;
						end if;
					elsif tick_counter < 2 then
						if rwds = '1' then
							latency <= 2;
						else
							latency <= 1;
						end if;
						latency_counter := latency_counter + 1;
					end if;

				when latency_delay =>
					B <= '0';

					busy <= '1';
					rwds <= 'Z';
					dq <= ( others => 'Z' );
					tick_counter := 0;

					latency_counter := latency_counter + 1;
--					dq <= std_logic_vector(to_unsigned(data_counter, 8));
	
					if latency_counter = latency_config*2*latency then
						if ca.r_wn = hyperram_command.write_command then
							state <= wr;
						else
							state <= rd;
						end if;
					else
						state <= latency_delay;
					end if;

				when wr =>
					B <= '1';
				
					busy <= '1';
					rwds <= '0';
					tick_counter 		:= 0;
					latency_counter 	:= 0;

					if ck_p = '0' then
						dq <= wr_data( 15 downto 8 );
						
					else
						dq <= wr_data( 7 downto 0 );
						strobe <= not strobe_prev;
						data_counter := data_counter - 1;
						if data_counter = 0 then
							state <= idle;
						end if;
					end if;

				when rd =>
					B <= '1';
					
					busy <= '1';
					rwds <= 'Z';
					tick_counter 		:= 0;
					latency_counter 	:= 0;

					if rwds = '0' then
						rd_data( 15 downto 8 ) <= dq;
						
					else
						rd_data( 7 downto 0 ) <= dq;
						strobe <= not strobe_prev;
						data_counter := data_counter - 1;
						if data_counter = 0 then
							state <= idle;
						end if;
					end if;

			end case;
		end if;
		strobe_prev <= strobe;
--		rwds_prev <= rwds;
--		ck_prev <= ck_p;	
	end if;
	
	end process hrddr_process;
end rtl;