function [d,q] = kundur_book_dq(z,delta)
%KUNDUR_BOOK_DQ Network phasor to Kundur d-q components.
% The q axis leads the d axis by 90 degrees.  z is a complex network-frame
% phasor and delta is the q-axis electrical angle.
d = sin(delta).*real(z) - cos(delta).*imag(z);
q = cos(delta).*real(z) + sin(delta).*imag(z);
end
