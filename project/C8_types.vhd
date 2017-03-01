library ieee;
use ieee.std_logic_1164.all;
use work.C8_constants.all;

package C8_types is
	subtype line_t is std_logic_vector( 0 to ( FRAME_WIDTH - 1 ) );
	type frame_t is array( 0 to ( FRAME_HEIGHT - 1 ) ) of line_t;
	
	type density_map_t is record
		x_map : std_logic_vector( 0 to FRAME_WIDTH  - 1 );
		y_map : std_logic_vector( 0 to FRAME_HEIGHT - 1 );
	end record density_map_t;
	
	type convolve_result_t is array ( 0 to FRAME_WIDTH ) of integer;
	
--	type density_map_t is record
--		x_map : std_logic_vector( 0 to FRAME_WIDTH  - 1 );
--		y_map : std_logic_vector( 0 to FRAME_HEIGHT - 1 );
--	end record density_map_t;

	type x_peaks_t is array( 0 to MAX_PEAKS_X - 1 ) of integer range 0 to FRAME_WIDTH;
	type y_peaks_t is array( 0 to MAX_PEAKS_Y - 1 ) of integer range 0 to FRAME_HEIGHT;

	type peaks_t is record
		x_peaks  : x_peaks_t;
		x_length : integer;
		y_peaks  : y_peaks_t;
		y_length : integer;
	end record peaks_t;
	
	
end C8_types;
