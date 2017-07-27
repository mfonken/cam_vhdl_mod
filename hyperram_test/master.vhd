---------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hyperram_types.all;
--------------------------------------------------------------------------------

----------------------------------------------
-- Main controller entity
----------------------------------------------
entity master is
	port
    (
		A	: inout std_logic;
		B	: inout std_logic;

		clock			: in 		std_logic;
		reset_n		: in  	std_logic;

		-- HyperRAM interface
		ram_rst     : out 	std_logic := '1';
		ram_cs_n    : out		std_logic := '1';
		ram_ck_p    : inout 	std_logic := '0';
		ram_ck_n    : out 	std_logic := '1';
		ram_rwds    : inout	std_logic := 'Z';
		ram_dq      : inout	std_logic_vector( 7 downto 0 )
		
--		t_ram_rst   : out		std_logic;
--		t_ram_cs_n  : out		std_logic;
--		t_ram_ck_p  : inout	std_logic;
--		t_ram_ck_n  : out		std_logic;
--		t_ram_rwds  : inout 	std_logic;
--		t_ram_dq    : inout	std_logic_vector( 7 downto 0 )
    );
end master;

architecture mbehaviour of master is
	constant sys_clk_frq			: integer 			:= 400_000_000;
	constant	ram_clk_frq			: integer			:= 10_000_000;
	constant ram_lat_config		: positive			:= 6;

	-- RAM data
	signal	ram_ena				: std_logic			:= '0';
	signal	ram_wr_data       : std_logic_vector(  15 downto 0 );
	signal	ram_wr_request   	: std_logic			:= '0';
	signal	ram_wr_length   	: integer range 0 to 255; --std_logic_vector(  7 downto 0 );

	signal	ram_rd_data       : std_logic_vector(  15 downto 0 );
	signal	ram_rd_request   	: std_logic 		:= '0';
	signal	ram_rd_length   	: integer range 0 to 255;
	signal	ram_strobe      	: std_logic 		:= '0';
	signal	ram_request_ack	: std_logic 		:= '0';
	signal	ram_busy				: std_logic			:= '0';
	signal	ram_burst         : std_logic;
	signal	ram_as            : std_logic;
	signal	ram_row           : std_logic_vector( 12 downto 0 );
	signal	ram_col           : std_logic_vector(  8 downto 0 );


	signal internal_ram_rst    : std_logic := '1';
	signal internal_ram_cs_n   : std_logic := '1';
	signal internal_ram_ck_p   : std_logic := '0';
	signal internal_ram_ck_n   : std_logic := '1';
	signal internal_ram_rwds   : std_logic := 'Z';
	signal internal_ram_dq     : std_logic_vector( 7 downto 0 );

--	signal internal_reset_n		: std_logic := '1';

	component hyperram is
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
			rd_length         : in   	integer range 0 to 255;

			wr_data           : in    	std_logic_vector(  15 downto 0 );
			wr_request        : in    	std_logic;
			wr_length         : in   	integer range 0 to 255;

			busy              : inout	std_logic;
			strobe            : inout	std_logic;
			request_ack       : out   	std_logic;

			burst             : in   	std_logic;
			as                : in    	std_logic;
			row               : in    	std_logic_vector( 12 downto 0 );
			col               : in    	std_logic_vector(  8 downto 0 );

			cs_n              : out 	std_logic;
			ck_p              : out 	std_logic;
			ck_n              : out   	std_logic;
			rwds              : inout 	std_logic;
			dq                : inout 	std_logic_vector(  7 downto 0 )

--			t_cs_n            : out 	std_logic;
--			t_ck_p            : out 	std_logic;
--			t_ck_n            : out   	std_logic;
--			t_rwds            : out 	std_logic;
--			t_dq              : out 	std_logic_vector(  7 downto 0 )
		);
	end component hyperram;

begin


	hyperram_0 : hyperram
	generic map
	(
		sys_ck_frequency    	=>	sys_clk_frq,
		ddr_ck_frequency   	=>	ram_clk_frq,
		latency_config			=> ram_lat_config
	)
	port map
	(
		A => A,
		B => B,
		clock               	=>	clock,
		reset_n             	=>	reset_n,

		rd_data             	=>	ram_rd_data,
		rd_request         	=>	ram_rd_request,
		rd_length         	=>	ram_rd_length,
		wr_data         		=>	ram_wr_data,
		wr_request				=> ram_wr_request,
		wr_length         	=>	ram_wr_length,

		busy						=> ram_busy,

		strobe         		=>	ram_strobe,
		request_ack        	=>	ram_request_ack,

		burst               	=>	ram_burst,
		as                  	=>	ram_as,
		row                 	=>	ram_row,
		col                 	=>	ram_col,

		cs_n                	=>	ram_cs_n,
		ck_p                	=>	ram_ck_p,
		ck_n                	=>	ram_ck_n,
		rwds                	=>	ram_rwds,
		dq                  	=>	ram_dq

--		t_cs_n              	=>	t_ram_cs_n,
--		t_ck_p               =>	t_ram_ck_p,
--		t_ck_n               =>	t_ram_ck_n,
--		t_rwds               =>	t_ram_rwds,
--		t_dq                 =>	t_ram_dq
	);

	ram_burst 			<= '1';
	ram_as    			<= hyperram_command.memory_space;
	ram_row          <= "0000000000100";
	ram_col          <= "000000000";

	ram_rd_length    <= 1;
	ram_wr_length    <= 1;

	--/*******RAM TEST START******/
	hrddram_test : process( clock )
	variable state_counter 		: integer range 0 to 5000 := 0;
	constant write_wait			: integer := 100;
	constant read_wait			: integer := write_wait + 1500;
	constant finished				: integer := read_wait + 1000;

	constant	test_word			: std_logic_vector( 15 downto 0 ) := x"abcd";--x"8ff3";1000 1111 1111 0011";
	variable write_index			: integer range 0 to 100 := 61;
--	variable write_lower			: integer	:= 7;
	variable ram_busy_prev			: std_logic := '0';
	variable ram_strobe_prev		: std_logic := '0';
	variable ram_request_ack_prev	: std_logic := '0';

	begin
		if rising_edge( clock ) then
			if reset_n = '0' then
				state_counter 	:= 0;
				ram_wr_request 	<= '0';
				ram_rd_request 	<= '0';
			else
				if state_counter = write_wait then
					ram_wr_data     	<= x"abcd";
					ram_wr_request 	<= '1';
					ram_rd_request 	<= '0';
--				elsif state_counter = read_wait then
--					ram_wr_request 	<= '0';
--					ram_rd_request 	<= '1';
--				elsif state_counter = finished then
--					ram_wr_data    	<= ram_rd_data;
--					ram_wr_request 	<= '1';
--					ram_rd_request 	<= '0';
--				end if;
				elsif ram_request_ack = '1' then
					ram_wr_request 	<= '0';
					ram_rd_request 	<= '0';
				end if;

				if state_counter < finished then
					state_counter := state_counter + 1;
				else
					state_counter := finished + 1;
				end if;

--				if ram_strobe_prev /= ram_strobe then
--					ram_wr_data   <= std_logic_vector(to_unsigned(write_index, 16));
--					write_index := write_index + 1;
--				end if;
			end if;
--			ram_strobe_prev := ram_strobe;
--			ram_busy_prev := ram_busy;
--			ram_request_ack_prev := ram_request_ack;
		end if;
	end process hrddram_test;

end mbehaviour;
