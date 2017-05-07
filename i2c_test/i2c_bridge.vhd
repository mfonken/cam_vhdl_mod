--------------------------------------------------------------------------------
--
--   FileName:         spi_to_i2c_bridge.vhd
--   Dependencies:     spi_slave.vhd (v1.1)
--                     spi_to_i2c.vhd (v1.0)
--                     i2c_master.vhd (v1.0)
--   Design Software:  Quartus II 32-bit Version 11.1 Build 173 SJ Full Version
--
--   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
--   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
--   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
--   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
--   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
--   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
--   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
--
--   Version History
--   Version 1.0 12/05/2012 Scott Larson
--     Initial Public Release
--
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY i2c_bridge IS
GENERIC(
  sys_clk_frq : INTEGER   := 50_000_000; --system clock speed in Hz
  i2c_scl_frq : INTEGER   := 100_000 );   --speed the i2c bus (scl) will run at in Hz
PORT(
	A    	 : in    STD_LOGIC_vector( 1 downto 0 );
	B 		 : in 	std_logic_vector( 1 downto 0 );
	LED1 : inout std_logic := '1';
	LED2 : inout std_logic := '1';
	LED5 : inout std_logic := '1';

  clock   : IN    STD_LOGIC;  --system clock
  reset_n : IN    STD_LOGIC;  --active low reset

  sioc     : INOUT STD_LOGIC;  --i2c serial clock
  siod     : INOUT STD_LOGIC); --i2c serial data
END i2c_bridge;

ARCHITECTURE logic OF i2c_bridge IS
  SIGNAL   i2c_en     : STD_LOGIC;
  SIGNAL   i2c_addr    : STD_LOGIC_VECTOR(6 DOWNTO 0);
  SIGNAL   i2c_rw      : STD_LOGIC;
  SIGNAL   i2c_data_wr : STD_LOGIC_VECTOR(7 DOWNTO 0);
  SIGNAL   i2c_data_rd : STD_LOGIC_VECTOR(7 DOWNTO 0);
  SIGNAL   i2c_ack_err : STD_LOGIC;
  SIGNAL   i2c_busy    : STD_LOGIC := '0';

  --declare spi to i2c component
  COMPONENT spi_to_i2c IS
    PORT(
		A    	 		: in    STD_LOGIC_vector( 1 downto 0 );
		LED1 			: out std_logic;
		LED2 			: out std_logic;
		LED5 			: out std_logic;
      clk         : IN   STD_LOGIC;                     --system clock
      reset_n     : IN   STD_LOGIC;                     --active low reset
      i2c_busy    : IN   STD_LOGIC := '0';                     --i2c busy signal (talking to i2c slave)
      i2c_data_rd : IN   STD_LOGIC_VECTOR(7 DOWNTO 0);  --data received from i2c slave
      i2c_ack_err : IN   STD_LOGIC;                     --i2c acknowledge error flag
      i2c_ena     : OUT  STD_LOGIC := '0';                     --latch command into i2c master
      i2c_addr    : OUT  STD_LOGIC_VECTOR(6 DOWNTO 0);  --i2c slave address
      i2c_rw      : OUT  STD_LOGIC;                     --i2c read/write command
      i2c_data_wr : OUT  STD_LOGIC_VECTOR(7 DOWNTO 0)); --data to write over the i2c bus
  END COMPONENT spi_to_i2c;

  --declare i2c master component
  COMPONENT i2c_master IS
    GENERIC(
      input_clk : INTEGER;  --input clock speed from user logic in Hz
      bus_clk   : INTEGER); --speed the i2c bus (scl) will run at in Hz
    PORT(
		B 			 : in std_logic_vector( 1 downto 0 );
      clk       : IN     STD_LOGIC;                    --system clock
      reset_n   : IN     STD_LOGIC;                    --active low reset
      ena       : IN     STD_LOGIC;                    --latch in command
      addr      : IN     STD_LOGIC_VECTOR(6 DOWNTO 0); --address of target slave
      rw        : IN     STD_LOGIC;                    --'0' is write, '1' is read
      data_wr   : IN     STD_LOGIC_VECTOR(7 DOWNTO 0); --data to write to slave
      busy      : inOUT    STD_LOGIC := '0';                    --indicates transaction in progress
      data_rd   : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0); --data read from slave
      ack_error : BUFFER STD_LOGIC;                    --flag if improper acknowledge from slave
      sda       : INOUT  STD_LOGIC;                    --serial data output of i2c bus
      scl       : INOUT  STD_LOGIC);                   --serial clock output of i2c bus
  END COMPONENT i2c_master;

BEGIN

  --instantiate the bridge component
  spi_to_i2c_0:  spi_to_i2c
    PORT MAP(A => A, LED1 => LED1, LED2 => LED2, LED5 => LED5, clk => clock, reset_n => reset_n, i2c_busy => i2c_busy,
             i2c_data_rd => i2c_data_rd, i2c_ack_err => i2c_ack_err,
             i2c_ena => i2c_en, i2c_addr => i2c_addr, i2c_rw => i2c_rw,
             i2c_data_wr => i2c_data_wr);

  --instantiate the i2c master
  i2c_master_0:  i2c_master
    GENERIC MAP(input_clk => sys_clk_frq, bus_clk => i2c_scl_frq)
    PORT MAP(B => B, clk => clock, reset_n => reset_n, ena => i2c_en, addr => i2c_addr,
             rw => i2c_rw, data_wr => i2c_data_wr, busy => i2c_busy,
             data_rd => i2c_data_rd, ack_error => i2c_ack_err, sda => siod,
             scl => sioc);

END logic;
