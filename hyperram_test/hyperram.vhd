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
	rd_request        : in			std_logic;
	rd_length         : in   		integer range 0 to 255;

	wr_data           : in    	std_logic_vector(  15 downto 0 );
	wr_request        : in    	std_logic;
	wr_length         : in   		integer range 0 to 255; --std_logic_vector(  7 downto 0 );

	busy              : out			std_logic;
	strobe            : out			std_logic;
	request_ack       : out   	std_logic;

	burst             : in   		std_logic;
	as                : in    	std_logic;
	row               : in    	std_logic_vector( 12 downto 0 );
	col               : in    	std_logic_vector(  8 downto 0 );

	cs_n              : out 		std_logic;
	ck_p              : out 		std_logic;
	ck_n              : out   	std_logic;
	rwds              : inout 	std_logic;
	dq                : inout 	std_logic_vector(  7 downto 0 );

	t_cs_n              : out 	std_logic;
	t_ck_p              : out 	std_logic;
	t_ck_n              : out   std_logic;
	t_rwds              : out 	std_logic;
	t_dq                : out 	std_logic_vector(  7 downto 0 )
	);
end hyperram;

architecture rtl of hyperram is
	constant 	ddr_ck_div 			: integer := sys_ck_frequency / ( ddr_ck_frequency * 2 );
	constant 	ddr_ck_div_half 	: integer := ddr_ck_div / 2;
	signal   	ddr_ck_div_counter : unsigned(integer(ceil(log2(real(ddr_ck_div_half)))) downto 0) := (others => '0');
	constant 	lv 					: std_logic := '0';
	constant		MAX_BURST 			: integer := 1024;
	signal		latency 				: integer range 1 to 2 := 1;

	type machine is(idle, command, latency_delay, wr, rd ); --needed states
	signal state         			: machine := idle;

	signal ca      					: ca_64MB_t;
	signal ca_bfr  					: std_logic_vector( 47 downto 0 );

	signal internal_data_out  		: std_logic_vector( 7 downto 0 );
--	signal command_counter       		: integer;

	signal internal_dq				: std_logic_vector( 7 downto 0 );

	--  type hrddr_byte_stream_t is array( MAX_BURST downto 0) of std_logic_vector( 7 downto 0 );
	signal internal_data_in  	 	: std_logic_vector( 7 downto 0 );
	signal internal_data_in_l 		: integer range 0 to MAX_BURST;
	signal ck_ena             		: std_logic := '0';

	signal internal_clock			: std_logic := '0';
	signal internal_clock_prev		: std_logic := '0';
	signal internal_ck_p 			: std_logic := '0';

	signal internal_mask				: std_logic := '0';

	signal busy_prev					: std_logic	:= '0';
	signal rwds_prev					: std_logic := '0';
	signal strobe_prev  				: std_logic := '0';
	signal read_write					: std_logic := '0';

	signal command_counter    : integer range 0 to 6 + latency_config*4 := 0;
	-- signal latency_counter : integer range 0 to latency_config*4 := 0;
	signal data_counter    : integer range 0 to MAX_BURST;

	begin
		---------------------------------------------------------------------------
		-- OVERSAMPLE_CLOCK_DIVIDER
		-- generate an oversampled tick (baud * 16)
		---------------------------------------------------------------------------
		clock_divider : process (clock, reset_n)
		begin
			if rising_edge (clock) then
				if reset_n = '0' or busy = '0' then
					ddr_ck_div_counter <= (others => '0');
					internal_clock <= '0';
				else
					if ddr_ck_div_counter < ddr_ck_div_half then
						internal_clock <= '0';
					else
						internal_clock <= '1';
					end if;
					if ddr_ck_div_counter = ddr_ck_div then
						ddr_ck_div_counter <= ( others => '0' );
					else
						ddr_ck_div_counter <= ddr_ck_div_counter + 1;
					end if;
				end if;
			end if;
		end process clock_divider;

		clock_driver : process (clock, reset_n)
		begin
			if rising_edge(clock) then
				if internal_clock_prev = '0' and internal_clock = '1' then
					if reset_n = '1' then
						internal_ck_p <= not internal_ck_p;
					else
						internal_ck_p <= '0';
					end if;
--					busy_prev <= busy;
				end if;
				internal_clock_prev <= internal_clock;
			end if;
		end process clock_driver;

		data_process : process(clock, reset_n)
		begin
			if rising_edge(clock) then
				if reset_n = '0' then
					B <= '1';
					command_counter 		<= 0;
					data_counter 		<= 0;
					state 				<= idle;
				else
					case state is
						when idle =>
							B <= '0';
							command_counter <= 0;

							if wr_request = '1' then
								data_counter <= wr_length;
								read_write <= hyperram_command.write_command;
								state <= command;
							elsif rd_request = '1' then
								data_counter <= rd_length;
								read_write <= hyperram_command.read_command;
								state <= command;
							else
								data_counter <= 0;
								read_write <= '0';
								state <= idle;
							end if;

						when command =>
							B <= '1';
							internal_data_out <= ca_bfr( ( ( ( 5 - command_counter ) * 8 ) + 7 ) downto ( ( 5 - command_counter ) * 8 ) );

							if internal_clock_prev = '1' and internal_clock = '0' then
								command_counter <= command_counter + 1;
								 --std_logic_vector(to_unsigned(command_counter, 8));
							end if;

							if command_counter = 3 then
								if rwds = '1' then
									latency <= 2;
								else
									latency <= 1;
								end if;
							elsif command_counter = 6 then
								if ca.as = hyperram_command.register_space and read_write = hyperram_command.write_command then -- if writing to register space
									state <= wr;                     -- write without latency
								else
									state <= latency_delay;
								end if;
							end if;

						when latency_delay =>
							B <= '0';
							internal_data_out <= x"00";

							if internal_clock_prev = '1' and internal_clock = '0' then
								command_counter <= command_counter + 1;
							end if;

							if command_counter = ( latency_config*2*latency ) + 3 then
								if read_write = hyperram_command.write_command then
									state <= wr;
								else
									state <= rd;
								end if;
							end if;

						when wr =>
							B <= '1';
							command_counter <= 0;

							if internal_clock_prev = '1' and internal_clock = '0' then
								if ck_p = '0' then
									internal_data_out <= wr_data( 15 downto 8 );
									if data_counter = 0 then
										state <= idle;
									end if;
								else
									internal_data_out <= wr_data( 7 downto 0 );
									data_counter <= data_counter - 1;
									strobe <= not strobe_prev;
								end if;
							end if;

						when rd =>
							B <= '1';
							command_counter <= 0;

--							if rwds_prev /= rwds then
--								if rwds = '1' then
							if internal_clock_prev = '1' and internal_clock = '0' then
								if internal_ck_p = '1' then

									rd_data( 15 downto 8 ) <= dq;
								else
									rd_data( 7 downto 0 ) <= dq;
									data_counter <= data_counter - 1;
									if data_counter = 0 then
										state <= idle;
									end if;
									strobe <= not strobe_prev;
								end if;
							end if;

				end case;
			end if;
			strobe_prev <= strobe;
--			rwds_prev <= rwds;
		end if;
	end process data_process;

	-- Module signals --
	request_ack 	<= busy;
	busy <= '0' when state = idle else '1';

	ca.r_wn	  <= read_write;
	ca.as     <= as;
	ca.burst  <= burst;
	ca.row    <= row;
	ca.col_u  <= col( 8 downto 3 );
	ca.col_l  <= col( 2 downto 0 );
	ca.rsv1   <= ( others => '0' );
	ca.rsv2   <= ( others => '0' );
	ca_bfr    <= ca.r_wn & ca.as & ca.burst & ca.rsv1 & ca.row & ca.col_u & ca.rsv2 & ca.col_l;


	-- Physical signals --
	cs_n			<= not busy;
	ck_p 			<= internal_ck_p;
	ck_n 			<= not internal_ck_p;
	rwds 			<= internal_mask when state = wr else 'Z';
	dq 				<= internal_data_out when ( state = command or state = wr ) else ( others => 'Z' ) when ( state = rd ) else ( others => '0' );

	-- Test signals --
	t_cs_n		<= not busy;
	t_ck_p 		<= internal_ck_p;
	t_ck_n 		<= not internal_ck_p;
	t_rwds 		<= rwds;
	t_dq 			<= dq;

	A <= internal_clock;

end rtl;
