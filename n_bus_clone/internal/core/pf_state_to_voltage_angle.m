function [delta, V] = pf_state_to_voltage_angle(x, model)
%PF_STATE_TO_VOLTAGE_ANGLE Convert the NR state vector into full bus states.

delta = zeros(model.num_buses, 1);
V = zeros(model.num_buses, 1);

delta(model.slack_buses) = deg2rad(model.angle_spec_deg(model.slack_buses));
V(model.slack_buses) = model.V_spec(model.slack_buses);

for i = 1:numel(model.pv_buses)
    bus_i = model.pv_buses(i);
    delta_position = find(model.delta_idx == bus_i, 1);
    delta(bus_i) = x(delta_position);
    V(bus_i) = model.V_spec(bus_i);
end

for i = 1:numel(model.pq_buses)
    bus_i = model.pq_buses(i);
    delta_position = find(model.delta_idx == bus_i, 1);
    V_position = model.n_delta + find(model.V_idx == bus_i, 1);
    delta(bus_i) = x(delta_position);
    V(bus_i) = x(V_position);
end
end
