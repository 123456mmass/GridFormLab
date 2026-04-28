function results = pf_build_results(model, V_final, delta_final, mismatch_history, iterations, converged, method_name)
%PF_BUILD_RESULTS Build a consistent result struct for all power-flow methods.

if nargin < 7 || isempty(method_name)
    method_name = 'Power Flow';
end

[P_final, Q_final] = pf_calculate_power_injections(V_final, delta_final, model.Ybus);

P_gen_actual = model.P_gen;
Q_gen_actual = model.Q_gen;
generator_buses = [model.slack_buses; model.pv_buses];
P_gen_actual(generator_buses) = P_final(generator_buses) + model.P_load(generator_buses);
Q_gen_actual(generator_buses) = Q_final(generator_buses) + model.Q_load(generator_buses);

[line_flow_P, line_flow_Q, line_loss_P, line_loss_Q] = calculate_line_flows(model, V_final, delta_final);

P_total_gen = sum(P_gen_actual);
Q_total_gen = sum(Q_gen_actual);
P_total_load = sum(model.P_load);
Q_total_load = sum(model.Q_load);
P_total_loss = sum(line_loss_P);
Q_total_loss = sum(line_loss_Q);
P_shunt_injected = -(V_final .^ 2) .* model.G_shunt;
Q_shunt_injected = (V_final .^ 2) .* model.B_shunt;
P_total_shunt_injected = sum(P_shunt_injected);
Q_total_shunt_injected = sum(Q_shunt_injected);

V_base = model.base_values.V_base_kV;
if V_base > 0
    V_display_kV = V_final * V_base;
else
    V_display_kV = nan(size(V_final));
end

results = struct();
results.system_name = model.system_name;
results.method = method_name;
results.external_bus_ids = model.external_bus_ids;
results.bus_type = model.bus_type;
results.bus_voltage = V_final;
results.bus_voltage_kV = V_display_kV;
results.bus_angle = delta_final;
results.bus_angle_deg = rad2deg(delta_final);
results.P_generation = P_gen_actual;
results.Q_generation = Q_gen_actual;
results.P_generation_specified = model.P_gen;
results.Q_generation_specified = model.Q_gen;
results.P_injection = P_final;
results.Q_injection = Q_final;
results.P_net_specified = model.P_net;
results.Q_net_specified = model.Q_net;
results.P_load = model.P_load;
results.Q_load = model.Q_load;
results.G_shunt = model.G_shunt;
results.B_shunt = model.B_shunt;
results.Q_min = model.Q_min;
results.Q_max = model.Q_max;
results.P_shunt_injected = P_shunt_injected;
results.Q_shunt_injected = Q_shunt_injected;
results.P_shunt_injected_total = P_total_shunt_injected;
results.Q_shunt_injected_total = Q_total_shunt_injected;
results.line_endpoints = model.line_data(:, 1:2);
results.line_B_half = model.line_data(:, 5);
results.line_tap_ratio = model.line_data(:, 6);
results.line_phase_shift_deg = model.line_data(:, 7);
results.line_flow_P = line_flow_P;
results.line_flow_Q = line_flow_Q;
results.line_loss_P = line_loss_P;
results.line_loss_Q = line_loss_Q;
results.P_loss_total = P_total_loss;
results.Q_loss_total = Q_total_loss;
results.P_total_gen = P_total_gen;
results.Q_total_gen = Q_total_gen;
results.P_total_load = P_total_load;
results.Q_total_load = Q_total_load;
results.base_values = model.base_values;
results.mismatch_history = mismatch_history(1:max(0, iterations));
results.iterations = iterations;
results.converged = converged;
results.Ybus = model.Ybus;
results.metadata = struct( ...
    'num_buses', model.num_buses, ...
    'num_lines', model.num_lines, ...
    'slack_bus_ids', model.external_bus_ids(model.slack_buses), ...
    'pv_bus_ids', model.external_bus_ids(model.pv_buses), ...
    'pq_bus_ids', model.external_bus_ids(model.pq_buses));
end

function [line_flow_P, line_flow_Q, line_loss_P, line_loss_Q] = calculate_line_flows(model, V_final, delta_final)
line_flow_P = zeros(model.num_lines, 1);
line_flow_Q = zeros(model.num_lines, 1);
line_loss_P = zeros(model.num_lines, 1);
line_loss_Q = zeros(model.num_lines, 1);

for i = 1:model.num_lines
    from = model.line_from_idx(i);
    to = model.line_to_idx(i);
    R = model.line_data(i, 3);
    X = model.line_data(i, 4);
    B_half = model.line_data(i, 5);
    tap_ratio = model.line_data(i, 6);
    phase_shift_deg = model.line_data(i, 7);

    V_from = V_final(from) * exp(1i * delta_final(from));
    V_to = V_final(to) * exp(1i * delta_final(to));
    y_series = 1 / (R + 1i * X);
    y_shunt = 1i * B_half;
    tap = tap_ratio * exp(1i * deg2rad(phase_shift_deg));

    I_from = ((y_series + y_shunt) / (tap * conj(tap))) * V_from - (y_series / conj(tap)) * V_to;
    I_to = (y_series + y_shunt) * V_to - (y_series / tap) * V_from;

    S_from = V_from * conj(I_from);
    S_to = V_to * conj(I_to);

    line_flow_P(i) = real(S_from);
    line_flow_Q(i) = imag(S_from);
    line_loss_P(i) = real(S_from + S_to);
    line_loss_Q(i) = imag(S_from + S_to);
end
end
