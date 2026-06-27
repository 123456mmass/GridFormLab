function [P_calc, Q_calc] = pf_calculate_power_injections(V, delta, Ybus)
%PF_CALCULATE_POWER_INJECTIONS Calculate bus injections from voltage state.

Gbus = real(Ybus);
Bbus = imag(Ybus);
num_buses = numel(V);
P_calc = zeros(num_buses, 1);
Q_calc = zeros(num_buses, 1);

for i = 1:num_buses
    sum_P = 0;
    sum_Q = 0;
    for j = 1:num_buses
        delta_ij = delta(i) - delta(j);
        sum_P = sum_P + V(j) * (Gbus(i, j) * cos(delta_ij) + Bbus(i, j) * sin(delta_ij));
        sum_Q = sum_Q + V(j) * (Gbus(i, j) * sin(delta_ij) - Bbus(i, j) * cos(delta_ij));
    end
    P_calc(i) = V(i) * sum_P;
    Q_calc(i) = V(i) * sum_Q;
end
end
