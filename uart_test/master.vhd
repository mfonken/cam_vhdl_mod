---------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- UART packages
use work.ucp_lib.all;

--------------------------------------------------------------------------------

----------------------------------------------
-- Main controller entity
----------------------------------------------
entity master is
	port
    (
		LED1	: out	std_logic := '1';
		LED2	: out	std_logic := '1';
		LED3	: out	std_logic := '1';
		LED4	: out	std_logic := '1';
		LED5	: out	std_logic := '1';
		
		A	: out std_logic;
		B	: out std_logic;
		C	: out std_logic;
		D	: out std_logic;

		clock			: in 			std_logic;
      reset_n		: inout  	std_logic;
		
		rx		: in 	std_logic;
		tx 	: out std_logic
    );

end master;

architecture mbehaviour of master is
	-- Uart signals
	signal	umd_rx_data : std_logic_vector(7 downto 0);
	signal	prev_umd_rx : std_logic_vector(7 downto 0);
	signal	umd_rx_stb  : std_logic;
	signal	umd_rx_ack  : std_logic;
	signal	umd_tx_data : std_logic_vector(7 downto 0) := x"ab";
	signal	umd_tx_stb 	: std_logic;
	
	signal	umd_clock	: std_logic;
	signal	umd_ena   	: std_logic;

	
	component uart is
		generic (
		  baud                : positive;
		  clock_frequency     : positive
		);
		port (  
		C	: out std_logic;
		D	: out std_logic;
		  clock               :   in  std_logic;
		  reset               :   in  std_logic;    
		  data_stream_in      :   in  std_logic_vector(7 downto 0);
		  data_stream_in_stb  :   in  std_logic;
		  data_stream_in_ack  :   out std_logic;
		  data_stream_out     :   out std_logic_vector(7 downto 0);
		  data_stream_out_stb :   out std_logic;
		  tx                  :   out std_logic;
		  rx                  :   in  std_logic
		);
end component uart;
	
  begin
	A	<= clock;
	B	<= umd_rx_stb;
	
	local_uart : uart
    generic map(
        baud         			=> 115_200,
        clock_frequency     	=> 50_000_000
    )
    port map(
        -- general
		  C => C,
		  D => D,
        clock        			=> clock,
        reset        			=> not reset_n,
        data_stream_in      	=> umd_rx_data,
        data_stream_in_stb 	=> umd_rx_stb,
        data_stream_in_ack  	=> umd_rx_ack,
        data_stream_out     	=> umd_tx_data,
        data_stream_out_stb 	=> umd_tx_stb,
        tx           			=> tx,
        rx           			=> rx
    );


	test_process : process(clock)
	variable tx_byte : std_logic := '0';
	variable ucp_pkt : ucp_t := ucp_hdr.dat & ucp_dat.ack & ucp_ftr.mst;
	begin
		if rising_edge(clock) then
			if tx_byte = '0' then
				tx_byte := '1';
				umd_rx_stb <= '1';
				umd_rx_data <= ucp_pkt;
			elsif umd_rx_ack = '1' then
				umd_rx_stb <= '0';
			end if;
		
			if umd_tx_stb = '1' then
				ucp_pkt( 4 downto 1 ) :=  umd_tx_data(3 downto 0);
				tx_byte := '0';
			end if;
		end if;
	end process test_process;
end mbehaviour;
