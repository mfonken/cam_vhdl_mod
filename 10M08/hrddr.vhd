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
        clock               : in    std_logic;
        reset_n             : in    std_logic;

        data_wr             : in    std_logic_vector(  7 downto 0 );
        data_wr_stb         : in    std_logic;
        data_wr_ack         : out   std_logic;
        data_wr_lat         : in    std_logic;
        data_wr_len         : in   	std_logic_vector(  7 downto 0 );
        data_rd             : out   std_logic_vector(  7 downto 0 );
        data_rd_stb         : in   	std_logic;
        data_rd_len         : in   	std_logic_vector(  7 downto 0 );
	
        data_str            : inout std_logic;

        burst               : in    std_logic;
        as                  : in    std_logic;
        row                 : in    std_logic_vector( 12 downto 0 );
        col                 : in    std_logic_vector(  8 downto 0 );
		  
        cs_n                : inout std_logic;
        ck_p                : inout std_logic;
        ck_n                : out   std_logic;
        rwds                : inout std_logic;
        dq                  : inout std_logic_vector(  7 downto 0 )
    );
end hrddr;

architecture rtl of hrddr is
  constant ddr_ck_div : integer := sys_ck_frequency / ddr_ck_frequency;
  constant ddr_ck_div_width : integer := integer(log2(real(ddr_ck_div))) + 1;
  signal   ddr_ck_div_counter : unsigned(ddr_ck_div_width - 1 downto 0) := (others => '0');
  constant lv : std_logic := '0';
  constant MAX_BURST : integer := 1024;

  signal  ck_prev : std_logic;

  type machine is(ready, start, command, latency_delay, wr, rd, stop); --needed states
  signal state         : machine;
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

  signal internal_str_prev  : std_logic := '0';
  signal internal_rwds_prev : std_logic := '0';
  signal internal_ck_prev   : std_logic := '0';

begin

ca.as     <= as;
ca.burst  <= burst;
ca.row    <= row;
ca.col_u  <= col( 8 downto 3 );
ca.col_l  <= col( 2 downto 0 );
ca_bfr    <= ca.r_wn & ca.as & ca.burst & ca.rsv1 & ca.row & ca.col_u & ca.rsv2 & ca.col_l;
ck_n      <= ck_p and lv;
---------------------------------------------------------------------------
-- OVERSAMPLE_CLOCK_DIVIDER
-- generate an oversampled tick (baud * 16)
---------------------------------------------------------------------------
  clock_divider : process (clock)
  begin
    if rising_edge (clock) then
        if reset_n = '0' and cs_n = '0' then
            ddr_ck_div_counter <= (others => '0');
            ck_p <= '0';
        else
            if ddr_ck_div_counter = ddr_ck_div then
                ddr_ck_div_counter <= (others => '0');
                ck_p <= '1';
            else
                ddr_ck_div_counter <= ddr_ck_div_counter + 1;
                ck_p <= '0';
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
        state <= ready;
        tick_counter := 0;
        data_counter := 0;
        internal_data_in <= "00000000";
        internal_data_in_l <= 0;
      end if;

      case state is
        when ready =>
          cs_n <= '0';
          if data_wr_stb = '1' xor data_rd_stb = '1' then
            ca.r_wn <= not data_wr_stb and data_rd_stb;
            state <= start;
          end if;

        when start =>
          cs_n <= '1';
          rwds <= 'Z';
          data_counter := 0;
          internal_data_in_l <= 0;
          state <= command;

        when command =>
          cs_n <= '1';
          if ck_p /= internal_ck_prev then                -- Sync to ck (ddr)
            if tick_counter = 0 then
              if ca.r_wn = '0' and ( data_wr_lat = '0' or as = '1' ) then
                state <= wr;
              else
                state <= latency_delay;
              end if;
            else
              tick_counter := tick_counter - 1;
              dq <= ca_bfr( tick_counter*8+7 downto tick_counter*8 ); --TX command-address (6 clock events)
            end if;
          end if;

        when latency_delay =>
          cs_n <= '1';
          if ck_p /= internal_ck_prev then                -- Sync to ck (ddr)
            if tick_counter = 6*latency then
              if ca.r_wn = '0' then
                state <= wr;
              else
                state <= rd;
              end if;
            else
              tick_counter := tick_counter + 1;
            end if;
          end if;

        when wr =>
          cs_n <= '1';
          if ck_p /= internal_ck_prev then                -- Sync to ck (ddr)
            if data_counter = to_integer( unsigned( data_wr_len ) ) then
              state <= stop;
              data_wr_ack <= '1';
            else
              dq <= data_wr;
              data_counter := data_counter + 1;
              data_str <= not internal_str_prev;
            end if;
          end if;

        when rd =>
          cs_n <= '1';
          if rwds /= internal_rwds_prev then
            if data_counter = to_integer( unsigned( data_rd_len ) ) then
              state <= stop;
            else
              internal_data_in <= dq;
              data_counter := data_counter + 1;
              data_str <= not internal_str_prev;
            end if;
          end if;
			 
        when stop =>
          cs_n <= '0';
          rwds <= 'Z';
      end case;
      internal_str_prev <= data_str;
      internal_rwds_prev <= rwds;
      internal_ck_prev <= ck_p;
    end if;
  end process hrddr_process;
end rtl;
