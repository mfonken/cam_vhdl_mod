library ieee;
use ieee.std_logic_1164.all;

package C8_constants is
  -- Camera frame dimensions
    constant FRAME_WIDTH   : unsigned := 1280;
    constant FRAME_HEIGHT  : unsigned := 800;

  -- Number of convolutions
    constant N_CONVOLVE    : unsigned := 4;

  -- Number of peaks (solutions)
    constant MAX_PEAKS_X   : unsigned := 30;
    constant MAX_PEAKS_Y   : unsigned := MAX_PEAKS_X;

  -- System/Controller communication
    constant PACKET_HEADER : std_logic_vector( 0 to 15 ) := x"EE";

  -- Kernel
    constant KERNEL_LENGTH : unsigned := 4;
    constant PULSE_KERNEL  : std_logic_vector( 0 to 3 )  := "1111";

  -- MCLK divider
    constant MCLK_DIVIDER  : unsigned := 4;

  -- Pixel threshold
    constant PIXEL_THRESH  : unsigned := 200;

end C8_constants;
