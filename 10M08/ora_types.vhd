library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ora_types is

	-- Camera frame dimensions
	constant FRAME_WIDTH   	: integer := 1280;
	constant FRAME_HEIGHT  	: integer := 800;

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
	constant MAX_VALUE		: integer := 1;

	-- General array types
	type x_array is array( FRAME_WIDTH 	downto 0 ) of integer range 0 to MAX_VALUE;
	type y_array is array( FRAME_HEIGHT downto 0 ) of integer range 0 to MAX_VALUE;
	subtype k_array is std_logic_vector( ( KERNEL_LENGTH - 1 ) 	downto 0 );

	-- Packet types
	constant UART_BUFFER_LENGTH	: integer := MAX_PEAKS_X + MAX_PEAKS_Y;
	type packet_buffer_t is array( UART_BUFFER_LENGTH downto 0 ) of std_logic_vector( 7 downto 0 );

	-- Camera frame type
	type frame_t is array( FRAME_HEIGHT downto 0 ) of std_logic_vector( FRAME_WIDTH downto 0 );

	-- Density map tyoe
	type density_map_t is record
		x_map : x_array;
		y_map : y_array;
	end record density_map_t;

	-- Convolution output array type
	type convolve_result_t is array ( FRAME_WIDTH downto 0 ) of integer;

	-- Peaks array type
	type x_peaks_t is array( 0 to MAX_PEAKS_X ) of integer;
	type y_peaks_t is array( 0 to MAX_PEAKS_Y ) of integer;

		-- Peaks type
	type x_peaks_a is record
		peaks : x_peaks_t;
		l 		: integer;
	end record x_peaks_a;
	type y_peaks_a is record
		peaks : y_peaks_t;
		l 		: integer;
	end record y_peaks_a;

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

		-- Ora defaults
	constant DEFAULT_THRESH 			: integer 				:= 200;
	constant DEFAULT_KERNEL 			: kernel_t 			 	:= kernel.pulse_kernel;
	constant DEFAULT_AUTO_CORRECT 	: auto_correct_t 		:= auto_correct.auto_cor_none;

end ora_types;
