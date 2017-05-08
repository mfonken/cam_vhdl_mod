library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ora_types is

	-- Camera frame dimensions
	constant FRAME_WIDTH   	: integer := 1280;
	constant FRAME_HEIGHT  	: integer := 800;
	constant MAX_ARRAY_L   	: integer := FRAME_WIDTH;

	constant MAX_CONV_V    	: integer := 1000;
	constant MAX_DIFF_V    	: integer := 60;

	-- Number of convolutions
	constant N_CONVOLVE    	: integer := 4;

	-- Number of peaks (solutions)
	constant MAX_PEAKS_X   	: integer := 30;
	constant MAX_PEAKS_Y   	: integer := MAX_PEAKS_X;

	-- System/Controller communication
	constant PACKET_HEADER 	: std_logic_vector( 7 downto 0 ) := x"EE";
	constant MAX_PACKETS	 	: integer := 8;

	-- Kernel
	constant KERNEL_LENGTH 	: integer := 4;
	constant NUM_KERNELS	 	: integer := 1;

	-- Pixel threshold
	constant PIXEL_THRESH  	: integer := 200;

	-- Max integer value
	constant MAX_VALUE		: integer := 1000;

	-- General array types
	subtype x_array is std_logic_vector( FRAME_WIDTH 				downto 0 );
	subtype y_array is std_logic_vector( FRAME_HEIGHT 				downto 0 );
	subtype k_array is std_logic_vector( ( KERNEL_LENGTH - 1 ) 	downto 0 );

	-- Packet types
	type packet_buffer_t is array( MAX_PACKETS-1 downto 0 ) of std_logic_vector( 7 downto 0 );

	-- Camera frame type
	type frame_t is array( FRAME_HEIGHT downto 0 ) of x_array;

	-- Density map tyoe
	type density_map_t is record
		x_map : x_array;
		y_map : y_array;
	end record density_map_t;

	-- Convolution output array type
	type convolve_result_t is array ( FRAME_WIDTH downto 0) of integer;

	-- Peaks array type
	type x_peaks_t is array( MAX_PEAKS_X downto 0 ) of integer;
	type y_peaks_t is array( MAX_PEAKS_Y downto 0 ) of integer;

	-- Kernel type
	subtype kernel_t is std_logic_vector( KERNEL_LENGTH-1 downto 0 );
	type kernel_l is record
		pulse_kernel : kernel_t;
		gaus_kernel  : kernel_t;
	end record kernel_l;
	constant kernel : kernel_l :=
	(
		pulse_kernel => "1111",
		gaus_kernel  => "0110"
	);

	subtype auto_correct_t is std_logic_vector( 1 downto 0 );
	type auto_correct_l is record
		auto_cor_none : auto_correct_t;
		auto_cor_low  : auto_correct_t;
		auto_cor_med  : auto_correct_t;
		auto_cor_high : auto_correct_t;
	end record auto_correct_l;
	constant auto_correct : auto_correct_l :=
	(
		auto_cor_none  => "00",
		auto_cor_low   => "01",
		auto_cor_med   => "10",
		auto_cor_high  => "11"
	);

	-- Peaks type
	type peaks_t is record
		x_peaks  : x_peaks_t;
		x_length : integer;
		y_peaks  : y_peaks_t;
		y_length : integer;
	end record peaks_t;

		-- Ora defaults
	constant DEFAULT_THRESH 			: integer 				:= 200;
	constant DEFAULT_KERNEL 			: kernel_t 			 	:= kernel.pulse_kernel;
	constant DEFAULT_AUTO_CORRECT 	: auto_correct_t 		:= auto_correct.auto_cor_none;

end ora_types;
