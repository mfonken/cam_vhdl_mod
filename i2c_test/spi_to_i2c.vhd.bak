--------------------------------------------------------------------------------
--
--   FileName:         spi_to_i2c.vhd
--   Dependencies:     spi_to_i2c_bridge.vhd (v1.0)
--                     spi_slave.vhd (v1.1)
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

ENTITY spi_to_i2c IS
PORT(
  clk         : IN   STD_LOGIC;                     --system clock
  reset_n     : IN   STD_LOGIC;                     --active low reset
  spi_rrdy    : IN   STD_LOGIC;                     --receive ready signal from spi (new message arrived)
  spi_rx_data : IN   STD_LOGIC_VECTOR(24 DOWNTO 0); --message received on spi
  spi_busy    : IN   STD_LOGIC;                     --spi slave busy signal (talking to spi master)
  spi_rx_req  : OUT  STD_LOGIC;                     --request received message from the spi slave
  spi_tx_ena  : OUT  STD_LOGIC;                     --load return message into spi slave
  spi_tx_data : OUT  STD_LOGIC_VECTOR(24 DOWNTO 0); --return message to send over spi
  i2c_busy    : IN   STD_LOGIC;                     --i2c busy signal (talking to i2c slave)
  i2c_data_rd : IN   STD_LOGIC_VECTOR(7 DOWNTO 0);  --data received from i2c slave
  i2c_ack_err : IN   STD_LOGIC;                     --i2c acknowledge error flag
  i2c_ena     : OUT  STD_LOGIC;                     --latch command into i2c master
  i2c_addr    : OUT  STD_LOGIC_VECTOR(6 DOWNTO 0);  --i2c slave address
  i2c_rw      : OUT  STD_LOGIC;                     --i2c read/write command
  i2c_data_wr : OUT  STD_LOGIC_VECTOR(7 DOWNTO 0)); --data to write over the i2c bus
END spi_to_i2c;

ARCHITECTURE behavior OF spi_to_i2c IS
  TYPE machine IS(ready, spi_rx, i2c, spi_load_tx);     --state machine datatype
  SIGNAL state         : machine;                       --current state
  SIGNAL message       : STD_LOGIC_VECTOR(24 DOWNTO 0); --message sent and received
  SIGNAL i2c_busy_prev : STD_LOGIC;                     --previous busy signal for i2c transactions
BEGIN
  PROCESS(clk, reset_n)
    VARIABLE i2c_busy_cnt : INTEGER := 0;  --keeps track of i2c busy signals during transaction
  BEGIN
    IF(reset_n = '0') THEN                 --reset asserted
      i2c_busy_cnt := 0; 
      i2c_ena <= '0';
      spi_rx_req <= '0';
      spi_tx_ena <= '0';
      state <= ready;
    ELSIF(clk'EVENT AND clk = '1') THEN
      CASE state IS
      
        WHEN ready =>
          spi_tx_ena <= '0';                         --do not load spi tx register
          IF(spi_busy = '0' AND spi_rrdy = '1') THEN --new message from spi
            spi_rx_req <= '1';                       --request message from spi
            state <= spi_rx;                         --retrieve message from spi
          ELSE                                       --no new message from spi
            state <= ready;                          --wait for new message from spi
          END IF;
          
        WHEN spi_rx =>
          message <= spi_rx_data;        --retrieve message from spi
          spi_rx_req <= '0';             --stop requesting
          IF(spi_rx_data(24) = '1') THEN --i2c enable bit is set
            state <= i2c;                --initiate i2c transaction
          ELSE
            state <= ready;              --wait for new message from spi
          END IF;
          
        WHEN i2c =>
          i2c_busy_prev <= i2c_busy;                      --capture the value of the previous i2c busy signal
          IF(i2c_busy_prev = '0' AND i2c_busy = '1') THEN --i2c busy just went high
            i2c_busy_cnt := i2c_busy_cnt + 1;             --counts the times busy has gone from low to high during transaction
          END IF;
          CASE i2c_busy_cnt IS                            --busy_cnt keeps track of which command we are on
            WHEN 0 =>                                     --no command latched in yet
              i2c_ena <= '1';                               --initiate the transaction
              i2c_addr <= message(23 DOWNTO 17);            --slave address is this 7 bits of message
              i2c_rw <= '0';                                --write the name of the slave register to access
              i2c_data_wr <= message(15 DOWNTO 8);          --the slave register to access is these 8 bits
            WHEN 1 =>                                     --1st busy high: command 1 latched, okay to issue command 2
              i2c_rw <= message(16);                        --command to read or right the slave register is bit 16
              i2c_data_wr <= message(7 DOWNTO 0);           --data to write to register (i2c master ignores if it's a read)
            WHEN 2 =>                                     --2nd busy high: command 2 latched, ready to stop
              i2c_ena <= '0';                               --deassert enable to stop transaction after command 2
              IF(i2c_busy = '0') THEN                       --indicates command 2 is finished and any data is ready
                IF(message(16) = '1') THEN                  --if it was a read
                  message(7 DOWNTO 0) <= i2c_data_rd;       --retrieve data from command 2 into 8 LSBs of message
                END IF;
                message(24) <= i2c_ack_err;                 --let spi master know if there was an i2c ack error
                i2c_busy_cnt := 0;                          --reset busy_cnt for next transaction
                state <= spi_load_tx;                       --transaction complete, load outcome into spi slave
              END IF;
            WHEN OTHERS => NULL;
          END CASE;
        
        WHEN spi_load_tx =>
          IF(spi_busy = '0') THEN
            spi_tx_ena <= '1';      --latch i2c outcome into spi slave transmit register
            spi_tx_data <= message; --tx data is now the last command sent and the data written or read  
            state <= ready;         --ready for new transaction from spi
          ELSE
            state <= spi_load_tx;   --wait to load spi tx register
          END IF;
          
      END CASE;
    END IF;
  END PROCESS;
END behavior;
