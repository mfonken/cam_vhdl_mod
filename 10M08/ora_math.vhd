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
              X   : y_array;
              H_l : integer;
              H   : k_array
            )
            return convolve_result_t;
-- Maxima detection descriptor
  function maximax(
              X : convolve_result_t
            )
            return x_peaks_a;
	function maximay(
              Y : convolve_result_t
            )
            return y_peaks_a;
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
          M.x_map(j) := M.x_map(j) + 1;
          M.y_map(i) := M.y_map(i) + 1;
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
		variable t : integer range -(KERNEL_LENGTH-1) to FRAME_WIDTH := 0;
  begin
    Y := ( others => 0 );
    for i in 0 to ( FRAME_WIDTH - 1 ) loop
      for j in 0 to ( KERNEL_LENGTH - 1 ) loop
			t := i - j;
			if t >= 0 and H(j) = '1' then
				Y(i) := Y(i) + X(t);
			end if;
      end loop;
    end loop;
    return Y;
  end convolveX;
  
  function convolveY(
              X_l : integer;
              X   : y_array;
              H_l : integer;
              H   : k_array
            )
            return convolve_result_t is
		variable Y : convolve_result_t;
		variable t : integer range -(KERNEL_LENGTH-1) to FRAME_WIDTH := 0;
  begin
    Y := ( others => 0 );
    for i in 0 to ( FRAME_HEIGHT - 1 ) loop
      for j in 0 to ( KERNEL_LENGTH - 1 ) loop
			t := i - j;
			if t >= 0 and H(j) = '1' then
				Y(i) := Y(i) + X(t);
			end if;
      end loop;
    end loop;
    return Y;
  end convolveY;

-- Maxima detection body
  function maximaX(
              X : convolve_result_t
            )
            return x_peaks_a is
		variable P : x_peaks_a;
		variable peak		:	std_logic := '1';
		variable prev    	: 	integer range 0 to MAX_VALUE;
		variable diff    	: 	integer range -MAX_VALUE to MAX_VALUE;
		variable x_index 	:	integer range 0 to MAX_PEAKS_X := 0;
	begin

	-- Find x peaks
	prev := X(0);
	for j in 1 to ( FRAME_HEIGHT - 1 ) loop
		diff := X(j) - prev;
		if peak = '1' then
			if diff < 0 and x_index /= MAX_PEAKS_X then
				peak := '0';
				P.peaks(x_index) := X(j);
				x_index := x_index + 1;
			end if;
			prev := X(j);
		else
			if diff > 0 then
				peak := '1';
			end if;
		end if;
	end loop;
	P.l := x_index;
	return P;
	end maximaX;
  
  function maximaY(
              Y : convolve_result_t
            )
            return y_peaks_a is
		variable P : y_peaks_a;
		variable peak		:	std_logic := '1';
		variable prev    	: 	integer range 0 to MAX_VALUE;
		variable diff    	: 	integer range -MAX_VALUE to MAX_VALUE;
		variable y_index 	: 	integer range 0 to MAX_PEAKS_Y := 0;
	begin

	-- Find Y peaks
	prev := Y(0);
	for j in 1 to ( FRAME_HEIGHT - 1 ) loop
		diff := Y(j) - prev;
		if peak = '1' then
			if diff < 0 and y_index /= MAX_PEAKS_Y then
				peak := '0';
				P.peaks(y_index) := Y(j);
				y_index := y_index + 1;
			end if;
			prev := Y(j);
		else
			if diff > 0 then
				peak := '1';
			end if;
		end if;
	end loop;
	P.l := y_index;
	return P;
	end maximaY;
end ora_math;
