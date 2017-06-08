-------------------------------------------------------------------------------
-- HyperRAM DDR
-- Implements the HyperBus interface
-------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity hrddr is
	generic (
		sys_ck_frequency    : positive;
		ddr_ck_frequency    : positive;
		latency             : positive
	);
	port (
		A	: inout std_logic := '0';
		B	: inout std_logic := '0';
		clock               : in    	std_logic;
		reset_n             : in    	std_logic;

		rd_data             : out   	std_logic_vector(  7 downto 0 );
		rd_request          : in		std_logic;
		rd_length           : in   	std_logic_vector(  7 downto 0 );

		wr_data             : in    	std_logic_vector(  7 downto 0 );
		wr_request          : in    	std_logic;
		wr_length           : in   	std_logic_vector(  7 downto 0 );

		strobe              : inout	std_logic;
		request_ack         : out   	std_logic;

		burst               : in   	std_logic;
		as                  : in    	std_logic;
		row                 : in    	std_logic_vector( 12 downto 0 );
		col                 : in    	std_logic_vector(  8 downto 0 );

		cs_n                : inout 	std_logic;
		ck_p                : inout 	std_logic;
		ck_n                : out   	std_logic;
		rwds                : inout 	std_logic;
		dq                  : inout 	std_logic_vector(  7 downto 0 )
	);
end hrddr;

architecture rtl of hrddr is
  constant ddr_ck_div : integer := sys_ck_frequency / ddr_ck_frequency;
  constant ddr_ck_div_width : integer := ddr_ck_div / 2;--integer(log2(real(ddr_ck_div))) + 1;
  signal   ddr_ck_div_counter : unsigned(ddr_ck_div_width - 1 downto 0) := (others => '0');
  constant lv : std_logic := '0';
  constant MAX_BURST : integer := 1024;

  type machine is(ready, start, command, latency_delay, wr, rd, stop); --needed states
  signal state         : machine := ready;
  type ca_64MB_t is record
		r_wn  : std_logic;
		as    : std_logic;
		burst : std_logic;
		rsv1  : std_logic_vector( 44 downto 35 );
		row   : std_logic_vector( 34 downto 22 );
		col_u : std_logic_vector( 21 downto 16 );
		rsv2  : std_logic_vector( 15 downto 3  );
		col_l : std_logic_vector(  2 downto 0  );
	end record ca_64MB_t;

  signal ca      : ca_64MB_t;
  signal ca_bfr  : std_logic_vector( 47 downto 0 );

  signal internal_data_out  : std_logic_vector( 7 downto 0 );
  signal tick_counter       : integer;

--  type hrddr_byte_stream_t is array( MAX_BURST downto 0) of std_logic_vector( 7 downto 0 );
  signal internal_data_in   : std_logic_vector( 7 downto 0 );
  signal internal_data_in_l : integer range 0 to MAX_BURST;
  signal ck_ena             : std_logic := '0';

  signal strobe_prev  : std_logic := '0';
  signal rwds_prev : std_logic := '0';
  signal ck_prev   : std_logic := '0';
  
  signal data_ready	: std_logic := '0';

begin

ca.as     <= as;
ca.burst  <= burst;
ca.row    <= row;
ca.col_u  <= col( 8 downto 3 );
ca.col_l  <= col( 2 downto 0 );
ca.rsv1   <= ( others => '0' );
ca.rsv2   <= ( others => '0' );
ca_bfr    <= ca.r_wn & ca.as & ca.burst & ca.rsv1 & ca.row & ca.col_u & ca.rsv2 & ca.col_l;
---------------------------------------------------------------------------
-- OVERSAMPLE_CLOCK_DIVIDER
-- generate an oversampled tick (baud * 16)
---------------------------------------------------------------------------
	clock_divider : process (clock)
	begin
		if rising_edge (clock) then
			if reset_n = '0' or cs_n = '1' or data_ready = '0' then    -- Sync reset or ram not selected
				ddr_ck_div_counter <= (others => '0');
				ck_p <= '0';
				ck_n <= '1';
			elsif data_ready = '1' then
				ddr_ck_div_counter <= ddr_ck_div_counter + 1;
				if ddr_ck_div_counter < ddr_ck_div_width then
					ck_p <= '0';
					ck_n <= '1';
				elsif ddr_ck_div_counter < ddr_ck_div then
					ck_p <= '1';
					ck_n <= '0';
				else
					ddr_ck_div_counter <= ( others => '0' );
				end if;
			end if;
		end if;
	end process clock_divider;


	hrddr_process : process(clock)
	variable tick_counter : integer range 0 to 6*latency := 6*latency;
	variable data_counter : integer range 0 to MAX_BURST;
	begin
		if rising_edge(clock) then
			if reset_n = '0' then
				cs_n <= '1';
				request_ack <= '0';
				tick_counter := 0;
				data_counter := 0;
				state <= ready;
			end if;

			case state is
				when ready =>
					cs_n <= '1';
					data_ready <= '0';
					request_ack <= '0';
					A <= '1';
					B <= '1';

					if wr_request = '1' xor rd_request = '1' then
						ca.r_wn <= not wr_request and rd_request;
						state <= start;
					end if;

				when start =>
					cs_n <= '0';
					data_ready <= '0';
					request_ack <= '1';
					tick_counter := 5;
					dq <= ca_bfr( 47 downto 40 );
					A <= '0';
					B <= '0';
					state <= command;

				when command =>
					cs_n <= '0';
					data_ready <= '1';
					request_ack <= '1';
					data_counter := 0;
					
					if ck_p /= ck_prev then                -- Sync to ck (ddr)
						if tick_counter = 0 then
							if ca.r_wn = '0' then              -- if writing
								dq <= wr_data;
								strobe <= not strobe_prev;
								state <= wr;                     -- write without latency
							else
								state <= latency_delay;
							end if;
						else
							tick_counter := tick_counter - 1;
							dq <= ca_bfr( tick_counter*8+7 downto tick_counter*8 ); --TX command-address (6 clock events) std_logic_vector(to_unsigned(tick_counter, 8));--
						end if;
					end if;

				when latency_delay =>
					cs_n <= '0';
					data_ready <= '1';
					request_ack <= '1';
					
					A <= '0';
					B <= '1';

					if ck_p /= ck_prev then                -- Sync to ck (ddr)
						if tick_counter = 8*latency then
							if ca.r_wn = '0' then
								state <= wr;
							else
								dq <= ( others => 'Z' );
								rwds <= 'Z';
								state <= rd;
							end if;
						else
--							dq <= std_logic_vector(to_unsigned(tick_counter, 8));
							tick_counter := tick_counter + 1;
						end if;
					end if;

				when wr =>
					cs_n <= '0';
					data_ready <= '1';
					request_ack <= '1';
					A <= '0';
					B <= '0';

					if ck_p /= ck_prev then                -- Sync to ck (ddr)
						if data_counter = to_integer( unsigned( wr_length ) ) - 1 then
							state <= stop;
						else
							dq <= wr_data;
							data_counter := data_counter + 1;
							strobe <= not strobe_prev;
						end if;
					end if;

				when rd =>
					cs_n <= '0';
					data_ready <= '1';
					request_ack <= '1';
					A <= '1';
					B <= '0';

					if rwds /= rwds_prev then
						if data_counter = to_integer( unsigned( rd_length ) ) - 1 then
							state <= stop;
						else
							rd_data <= dq;
							data_counter := data_counter + 1;
							strobe <= not strobe_prev;
						end if;
					end if;

				when stop =>
					A <= '1';	
					B <= '1';
					cs_n <= '1';
					data_ready <= '0';
					request_ack <= '0';
					state <= ready;

			end case;

			strobe_prev <= strobe;
			rwds_prev <= rwds;
			ck_prev <= ck_p;

		end if;
	end process hrddr_process;
end rtl;