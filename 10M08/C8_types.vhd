library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.C8_constants.all;

package C8_types is

-- General array types
	subtype x_array is std_logic_vector( FRAME_WIDTH 				downto 0 );
	subtype y_array is std_logic_vector( FRAME_HEIGHT 				downto 0 );
	subtype k_array is std_logic_vector( ( KERNEL_LENGTH - 1 ) 	downto 0 );

-- Camera frame type
	type frame_t is array( FRAME_HEIGHT downto 0 ) of x_array;

-- Density map tyoe
	type density_map_t is record
		x_map : x_array;
		y_map : y_array;
	end record density_map_t;

-- Convolution output array type
	type convolve_result_t is array ( MAX_ARRAY_L downto 0) of unsigned( MAX_VALUE downto 0 );

-- Peaks array type
	type x_peaks_t is array( MAX_PEAKS_X downto 0 ) of unsigned( FRAME_WIDTH  downto 0 );
	type y_peaks_t is array( MAX_PEAKS_Y downto 0 ) of unsigned( FRAME_HEIGHT downto 0 );

-- Peaks type
	type peaks_t is record
		x_peaks  : x_peaks_t;
		x_length : unsigned( MAX_PEAKS_X downto 0 );
		y_peaks  : y_peaks_t;
		y_length : unsigned( MAX_PEAKS_Y downto 0 );
	end record peaks_t;


end C8_types;
