library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package global_types is

	-- System state type
	type system_states_t is ( startup, activate, live, deactivate, standby, shutdown );
	
	-- i2c state type
	type i2c_tx_states_t is ( i2c_standby, i2c_reg_tx, i2c_val_tx );

	-- UART Com types
	type umd_state_t   	is ( umd_standby, umd_tx, umd_rx );

end global_types;
