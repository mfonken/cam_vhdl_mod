library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use work.ora_constants.all;

package ucp_lib is

	--------------------------------------------------------------------------------
	-- UART Control Protocol
	--------------------------------------------------------------------------------
	---- Header definitions
	subtype ucp_hdr_t      is std_logic_vector( 7 downto 5 );
	type ucp_hdr_l is record
		sys      : ucp_hdr_t;
		cfg      : ucp_hdr_t;
		dat      : ucp_hdr_t;
	end record ucp_hdr_l;
	constant ucp_hdr : ucp_hdr_l :=
	(
		sys   => "001",
		cfg   => "010",
		dat   => "100"
	);

	-- UART Commands
	subtype ucp_cmd_t      is std_logic_vector( 4 downto 1 );
	---- System definitions
	type ucp_sys_l is record
		wake     : ucp_cmd_t;
		sleep    : ucp_cmd_t;
		shutoff  : ucp_cmd_t;
		fatal    : ucp_cmd_t;
	end record ucp_sys_l;
	constant ucp_sys : ucp_sys_l :=
	(
		wake    => "0001",
		sleep   => "0010",
		shutoff => "0100",
		fatal   => "1111"
	);
	---- Configuration definitions
	type ucp_cfg_l is record
		thresh   : ucp_cmd_t;
		kernel   : ucp_cmd_t;
		auto_cor : ucp_cmd_t;
	end record ucp_cfg_l;
	constant ucp_cfg : ucp_cfg_l :=
	(
		thresh   => "0001",
		kernel   => "0011",
		auto_cor => "0010"
	);
	---- Data definitions
	type ucp_dat_l is record
		ack      : ucp_cmd_t;
		nack     : ucp_cmd_t; 
	end record ucp_dat_l;
	constant ucp_dat : ucp_dat_l :=
	(
		ack   => "1111",
		nack  => "0000"
	);

	---- Footer definitions
	subtype ucp_ftr_t is std_logic;-- std_logic_vector( 1 downto 0 );
	type ucp_ftr_l is record
		slv     : ucp_ftr_t;
		mst     : ucp_ftr_t;
	end record ucp_ftr_l;
	constant ucp_ftr : ucp_ftr_l :=
	(
		slv   => '0',
		mst   => '1'
	);

	---- Full definition
	subtype ucp_t is std_logic_vector( 7 downto 0 );
	type ucp is record
		hdr     : ucp_hdr_t;
		cmd     : ucp_cmd_t;
		ftr     : ucp_ftr_t;
	end record ucp;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
end package ucp_lib;
