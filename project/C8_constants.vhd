library ieee;
use ieee.std_logic_1164.all;

package C8_constants is
  -- Camera frame dimensions
    constant FRAME_WIDTH   : integer := 1280;
    constant FRAME_HEIGHT  : integer := 800;
    constant MAX_ARRAY_L   : integer := FRAME_WIDTH;

  -- Number of convolutions
    constant N_CONVOLVE    : integer := 4;

  -- Number of peaks (solutions)
    constant MAX_PEAKS_X   : integer := 30;
    constant MAX_PEAKS_Y   : integer := MAX_PEAKS_X;

  -- System/Controller communication
    constant PACKET_HEADER : std_logic_vector( 0 to 7 ) := x"EE";

  -- Kernel
    constant KERNEL_LENGTH : integer := 4;
    constant PULSE_KERNEL  : std_logic_vector( 0 to 3 )  := "1111";

  -- MCLK divider
    constant MCLK_DIVIDER  : integer := 4;

  -- Pixel threshold
    constant PIXEL_THRESH  : integer := 200;

end C8_constants;
