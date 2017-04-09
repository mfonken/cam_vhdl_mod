library ieee;
use ieee.std_logic_1164.all;
use work.C8_constants.all;
use work.C8_types.all;

package C8_math is
-- Density mapper descriptor
  function density_mapper( F : frame_t );
            return M : density_map_t;
-- Convolution descriptor
  function convolve(
              X_l : unsigned;
              X   : std_logic_vector( 0 to X_l );
              H_l : KERNEL_LENGTH;
              H   : std_logic_vector( 0 to KERNEL_LENGTH )
            );
            return Y : std_logic_vector( 0 to X_l );
-- Maxima detection descriptor
  function maxima( M : density_map_t );
            return P : peaks_t ;
end C8_math;

package C8_math is
-- Density mapper body
  function density_mapper( F : frame_t );
            return M : density_map_t is
  begin
    for i in 0 to FRAME_WIDTH loop
      for j in 0 to FRAME_HEIGHT loop
        if ( M(i)(j) = '1' ) then
          M.x_map(j) := '1';
          M.y_map(i) := '1';
        end if;
      end loop;
    end loop;
  end density_mapper;

-- Convolution body
  function convolve(
              X_l : unsigned;
              X   : std_logic_vector( 0 to X_l );
              H_l : KERNEL_LENGTH;
              H   : std_logic_vector( 0 to KERNEL_LENGTH )
            );
            return Y : std_logic_vector( 0 to X_l ) is
  begin
    Y <= (others => '0');
    for i in 0 to X_l loop
      for j in 0 to H_l loop
        Y(i) := Y(i) + X(i - j) * H(j);
      end loop;
    end loop;
    return Y;
  end convolution;
-- Maxima detection body
  function maxima( M : density_map_t );
            return P : peaks_t is
    variable prev    : unsigned;
    variable diff    : signed;
    variable x_index : unsigned := '0';
    variable y_index : unsigned := '0';
  begin
-- Find X peaks
    prev := M.x_map(0);
    for i in 1 to FRAME_WIDTH loop
      diff := M.x_map(i) - prev;
      if( diff < 0 ) then
        P.x_peaks(x_index) <= i;
        x_index := x_index + 1;
      end if;
    end loop;
    M.x_length <= x_index - 1;
-- Find Y peaks
    prev := M.y_map(0);
    for j in 0 to FRAME_HEIGHT loop
      diff := M.y_map(i) - prev;
      if( diff < 0 ) then
        P.x_peaks(y_index) <= i;
        y_index := y_index + 1;
      end if;
    end loop;
    M.y_length <= y_index - 1;
    return M;
  end maxima;
end C8_math;
