library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ora_types.all;

package ora_math is
-- Density mapper descriptor
  function density_mapper( F : frame_t )
            return density_map_t;
-- Convolution descriptor
  function convolveX(
              X_l : integer;
              X   : x_array;
              H_l : integer;
              H   : k_array
            )
            return convolve_result_t;
-- Convolution descriptor
  function convolveY(
              X_l : integer;
              X   : x_array;
              H_l : integer;
              H   : k_array
            )
            return convolve_result_t;
-- Maxima detection descriptor
  function maxima(
              X : convolve_result_t;
              Y : convolve_result_t
            )
            return peaks_t;
end ora_math;

package body ora_math is
-- Density mapper body
  function density_mapper( F : frame_t )
            return density_map_t is
	variable M : density_map_t;
  begin
    for i in 0 to ( FRAME_HEIGHT - 1 ) loop
      for j in 0 to ( FRAME_WIDTH - 1 ) loop
        if ( F(i)(j) = '1' ) then
          M.x_map(j) := '1';
          M.y_map(i) := '1';
        end if;
      end loop;
    end loop;
	 return M;
  end density_mapper;

  -- Convolution body
  function convolveX(
              X_l : integer;
              X   : x_array;
              H_l : integer;
              H   : k_array
            )
            return convolve_result_t is
		variable Y : convolve_result_t;
		variable t : integer := 0;
  begin
    Y := ( others => 0 );
    for i in 0 to 31 loop
      for j in 0 to 3 loop
			t := i - j;
			if t >= 0 and X(t) = '1' and H(j) = '1' then
				Y(i) := Y(i) + 1;
			end if;
      end loop;
    end loop;
    return Y;
  end convolveX;
-- Convolution body
  function convolveY(
              X_l : integer;
              X   : y_array;
              H_l : integer;
              H   : k_array
            )
            return convolve_result_t is
		variable Y : convolve_result_t;
		variable t : integer := 0;
  begin
    Y := ( others => 0 );
    for i in 0 to 31 loop
      for j in 0 to 3 loop
			t := i - j;
			if t >= 0 and X(t) = '1' and H(j) = '1' then
				Y(i) := Y(i) + 1;
			end if;
      end loop;
    end loop;
    return Y;
  end convolveY;

-- Maxima detection body
  function maxima(
              X : convolve_result_t;
              Y : convolve_result_t
            )
            return peaks_t is
		variable P : peaks_t;
		variable prev    : integer;
		variable diff    : integer;
		variable x_index : integer range convolve_result_t'length downto 0 := 0;
		variable y_index : integer range convolve_result_t'length downto 0 := 0;
	begin

-- Find X peaks
    prev := X(0);
    for i in 1 to FRAME_WIDTH loop
      diff := X(i) - prev;
      if( diff < 0 ) then
        P.x_peaks(x_index) := i;
        x_index := x_index + 1;
      end if;
    end loop;
   P.x_length := x_index;

-- Find Y peaks
   prev := Y(0);
   for j in 1 to FRAME_HEIGHT loop
     diff := Y(j) - prev;
     if( diff < 0 ) then
       P.y_peaks(y_index) := j;
       y_index := y_index + 1;
     end if;
   end loop;
   P.y_length := y_index;
   return P;
  end maxima;
end ora_math;
