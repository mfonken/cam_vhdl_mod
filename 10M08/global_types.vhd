library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ora_constants.all;

package global_types is

	-- System state type
	type system_states_t is ( startup, activate, active, deactivate, standby, shutdown );
	
	-- SIO state type
	type sio_tx_states_t is ( sio_standby, sio_reg_tx, sio_val_tx );

	-- UART Com types
	type umd_state_t   is ( umd_standby, umd_tx, umd_rx );

end global_types;
