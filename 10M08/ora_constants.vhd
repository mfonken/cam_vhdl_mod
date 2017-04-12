library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ora_constants is
	-- Ora defaults
	constant DEFAULT_THRESH 				: integer 				:= 200;
	constant DEFAULT_KERNEL 				: kernel_l 			 	:= pulse_kernel;
	constant DEFAULT_AUTO_CORRECT 	: auto_correct_l 	:= auto_cor_high;

	-- Camera frame dimensions
	constant FRAME_WIDTH   : integer := 1280;
	constant FRAME_HEIGHT  : integer := 800;
	constant MAX_ARRAY_L   : integer := FRAME_WIDTH;

	constant MAX_CONV_V    : integer := 1000;
	constant MAX_DIFF_V    : integer := 60;

	-- Number of convolutions
	constant N_CONVOLVE    : integer := 4;

	-- Number of peaks (solutions)
	constant MAX_PEAKS_X   : integer := 30;
	constant MAX_PEAKS_Y   : integer := MAX_PEAKS_X;

	-- System/Controller communication
	constant PACKET_HEADER : std_logic_vector( 7 downto 0 ) := x"EE";
	constant MAX_PACKETS	 : integer := 8;

	-- Kernel
	constant KERNEL_LENGTH : integer := 4;
	constant PULSE_KERNEL  : kernel_t  := "1111";
	constant NUM_KERNELS	 : integer := 1;

	-- MCLK divider
	constant MCLK_DIV      : integer := 4;
	constant MCLK_DIV_HALF : integer := MCLK_DIV / 2;

	-- Pixel threshold
	constant PIXEL_THRESH  : integer := 200;

	-- Max integer value
	constant MAX_VALUE		: integer := 1000;

end ora_constants;
