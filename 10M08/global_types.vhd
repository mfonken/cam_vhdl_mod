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
  type ucom_states_t   is ( ucom_standby, ucom_tx, ucom_rx );
  type ucom_commands   is ( wake, sleep, shutoff );

  type ucom_cmd_t     is std_logic_vector(7 downto 0);
  type ucom_cmds_t is record
  	wake     : ucom_cmd_t;
  	sleep    : ucom_cmd_t;
    shutoff  : ucom_cmd_t;
    ack      : ucom_cmd_t
  end record ucom_cmds_t;
  constant ucom_cmds_l : ucom_cmds_t :=
  (
    wake    => "00000001",
    sleep   => "00000010",
    shutoff => "00000011"
    ack     => "11111111"
  );

end global_types;
