function Ig = kundur_book_network_current(Id,Iq,delta)
%KUNDUR_BOOK_NETWORK_CURRENT Kundur d-q current to network phasor.
% Generator current is positive from machine into the network.
Ig = complex(sin(delta).*Id + cos(delta).*Iq, ...
    -cos(delta).*Id + sin(delta).*Iq);
end
