library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ora_constants.all;

package ora_types is

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
	type convolve_result_t is array ( FRAME_WIDTH downto 0) of integer;

-- Peaks array type
	type x_peaks_t is array( MAX_PEAKS_X downto 0 ) of integer;
	type y_peaks_t is array( MAX_PEAKS_Y downto 0 ) of integer;

-- Peaks type
	type peaks_t is record
		x_peaks  : x_peaks_t;
		x_length : integer;
		y_peaks  : y_peaks_t;
		y_length : integer;
	end record peaks_t;


end ora_types;
