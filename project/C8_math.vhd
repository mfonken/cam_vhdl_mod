library ieee;
use ieee.std_logic_1164.all;
use work.C8_constants.all;
use work.C8_types.all;

package C8_math is
-- Density mapper descriptor
  function density_mapper( F : frame_t )
            return density_map_t;
-- Convolution descriptor
  function convolve(
              X_l : integer;
              X   : std_logic_vector( 0 to FRAME_WIDTH );
              H_l : integer;
              H   : std_logic_vector( 0 to KERNEL_LENGTH )
            )
            return convolve_result_t;
-- Maxima detection descriptor
  function maxima( M : convolve_result_t )
            return peaks_t;
end C8_math;

package body C8_math is
-- Density mapper body
  function density_mapper( F : frame_t )
            return density_map_t is
	variable M : density_map_t;
  begin
    for i in 0 to FRAME_WIDTH loop
      for j in 0 to FRAME_HEIGHT loop
        if ( F(i)(j) = '1' ) then
          M.x_map(j) := '1';
          M.y_map(i) := '1';
        end if;
      end loop;
    end loop;
	 return M;
  end density_mapper;

-- Convolution body
  function convolve(
              X_l : integer;
              X   : std_logic_vector( 0 to FRAME_WIDTH );
              H_l : integer;
              H   : std_logic_vector( 0 to KERNEL_LENGTH )
            )
            return convolve_result_t is
	
	variable Y : convolve_result_t;
  begin
    Y := (others => 0);
    for i in 0 to X_l loop
      for j in 0 to H_l loop
			if( X(i - j) = '1' and H(j) = '1' ) then
				Y(i) := Y(i) + 1;
			end if;
      end loop;
    end loop;
    return Y;
  end convolve;
-- Maxima detection body
  function maxima( M : convolve_result_t )
            return peaks_t is
		variable P : peaks_t;
		variable prev    : integer;
		variable diff    : integer;
		variable x_index : integer := 0;
		variable y_index : integer := 0;
	begin	
-- Find X peaks
    prev := M(0);
    for i in 1 to FRAME_WIDTH loop
      diff := M(i) - prev;
      if( diff < 0 ) then
        P.x_peaks(x_index) := i;
        x_index := x_index + 1;
      end if;
    end loop;
--    M.x_length <= x_index - 1;
---- Find Y peaks
--    prev := M.y_map(0);
--    for j in 0 to FRAME_HEIGHT loop
--      diff := M.y_map(i) - prev;
--      if( diff < 0 ) then
--        P.y_peaks(y_index) <= i;
--        y_index := y_index + 1;
--      end if;
--    end loop;
--    M.y_length <= y_index - 1;
    return P;
  end maxima;
end C8_math;