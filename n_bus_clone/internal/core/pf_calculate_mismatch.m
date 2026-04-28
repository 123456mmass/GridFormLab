function [mismatch, P_calc, Q_calc, V, delta] = pf_calculate_mismatch(x, model, P_spec, Q_spec)
%PF_CALCULATE_MISMATCH Build the NR mismatch vector for scheduled injections.

if nargin < 3 || isempty(P_spec)
    P_spec = model.P_net;
end
if nargin < 4 || isempty(Q_spec)
    Q_spec = model.Q_net;
end

[delta, V] = pf_state_to_voltage_angle(x, model);
[P_calc, Q_calc] = pf_calculate_power_injections(V, delta, model.Ybus);

mismatch = zeros(model.n_total, 1);
for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    mismatch(i) = P_spec(bus_i) - P_calc(bus_i);
end
for i = 1:model.n_V
    bus_i = model.V_idx(i);
    mismatch(model.n_delta + i) = Q_spec(bus_i) - Q_calc(bus_i);
end
end
