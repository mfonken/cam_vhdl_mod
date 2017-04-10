----------------------------------------------
-- Package include
----------------------------------------------
-- IEEE packages
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_integer.all;

-- Global constants
use work.global_constants.all;

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
  cpi_mclk  : inout 	std_logic;
  cpi_vsync : in    	std_logic;
  cpi_href  : in    	std_logic;
  cpi_pclk  : in    	std_logic;
  cpi_data  : in    	std_logic_vector( 7 downto 0 );
  siod  		: inout 	std_logic;
  sioc  		: inout  std_logic;

  -- Serial interface
  rx    		: in    	std_logic;
  tx    		: out  	std_logic;
  
  reset		: in		std_logic
  );
end C8_Project;

--------------------------------------------------------------------------------
-- Main camera controller behaviour
--------------------------------------------------------------------------------
architecture gbehaviour of C8_Project is

-- Uart signals
signal 	rx_data     :  std_logic_vector(7 downto 0);
signal	rx_stb  		:  std_logic;
signal	rx_ack  		:  std_logic;
signal	tx_data     :  std_logic_vector(7 downto 0);
signal	tx_stb 		:  std_logic;

-- Sio signals
signal 	sio_ena		: 	std_logic;
signal 	sio_rw		:	std_logic;
signal 	sio_wr		:	std_logic_vector( 7 downto 0 );
signal 	sio_rd		: 	std_logic_vector( 7 downto 0 );
signal	sio_bsy		: 	std_logic;
signal	sio_ack_err	:	std_logic;

begin
	com : entity work.uart
	generic map(
		115_200,
		100_000_000
	)
	port map(
		clock,
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
		clock,
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

	cpi : entity work.ora 
	port map(
		clock,
		cpi_mclk,
		cpi_vsync,
		cpi_href,
		cpi_pclk,
		cpi_data
	);
	
	
end gbehaviour;
