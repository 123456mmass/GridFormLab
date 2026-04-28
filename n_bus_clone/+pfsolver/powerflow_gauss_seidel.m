function results = powerflow_gauss_seidel(case_data, options)
%POWERFLOW_GAUSS_SEIDEL Generic Gauss-Seidel power flow solver.
%   Supports Slack, PV, and PQ buses. PV buses use scheduled real-power net
%   injection and update reactive injection from the current network state,
%   then enforce the specified voltage magnitude.

if nargin < 1 || isempty(case_data)
    case_data = case_ieee5bus();
end
if nargin < 2
    options = struct();
end

pf_init_paths();

model = pf_prepare_case(case_data);

max_iter = pf_get_option(options, 'max_iter', 200);
tolerance = pf_get_option(options, 'tolerance', 1e-6);
acceleration = pf_get_option(options, 'acceleration', 1.4);
plot_results = pf_get_option(options, 'plot_results', true);
verbose = pf_get_option(options, 'verbose', true);

if max_iter < 1
    error('max_iter must be at least 1.');
end

if verbose
    print_header(model, acceleration);
end

Vc = model.V_spec .* exp(1i * deg2rad(model.angle_spec_deg));
mismatch_history = zeros(max_iter, 1);
converged = false;

for iter = 1:max_iter
    for bus_i = 1:model.num_buses
        if model.bus_type(bus_i) == 1
            continue;
        end

        sum_yv = model.Ybus(bus_i, :) * Vc - model.Ybus(bus_i, bus_i) * Vc(bus_i);

        if model.bus_type(bus_i) == 2
            S_calc = Vc(bus_i) * conj(model.Ybus(bus_i, :) * Vc);
            Q_iter = imag(S_calc);
            S_spec = model.P_net(bus_i) + 1i * Q_iter;
        else
            S_spec = model.P_net(bus_i) + 1i * model.Q_net(bus_i);
        end

        V_raw = (conj(S_spec) / conj(Vc(bus_i)) - sum_yv) / model.Ybus(bus_i, bus_i);
        V_new = Vc(bus_i) + acceleration * (V_raw - Vc(bus_i));

        if model.bus_type(bus_i) == 2
            V_new = model.V_spec(bus_i) * exp(1i * angle(V_new));
        end

        if abs(V_new) <= 0
            V_new = 0.1 * exp(1i * angle(Vc(bus_i)));
        end

        Vc(bus_i) = V_new;
    end

    V = abs(Vc);
    delta = angle(Vc);
    [P_calc, Q_calc] = pf_calculate_power_injections(V, delta, model.Ybus);
    mismatch = build_gs_mismatch(model, P_calc, Q_calc);
    max_mismatch = max(abs(mismatch));
    mismatch_history(iter) = max_mismatch;

    if verbose
        fprintf('Iteration %3d: Max Mismatch = %.6e\n', iter, max_mismatch);
    end

    if max_mismatch < tolerance
        converged = true;
        if verbose
            fprintf('\n*** CONVERGED in %d iterations ***\n\n', iter);
        end
        break;
    end
end

if ~converged && verbose
    fprintf('\n*** WARNING: Did not converge in %d iterations ***\n\n', max_iter);
end

V_final = abs(Vc);
delta_final = angle(Vc);
results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, converged, 'Gauss-Seidel');
results.acceleration = acceleration;

if verbose
    pf_print_powerflow_report(results);
end

if plot_results
    pf_plot_powerflow_results(results, tolerance);
end
end

function mismatch = build_gs_mismatch(model, P_calc, Q_calc)
mismatch = zeros(model.n_total, 1);
for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    mismatch(i) = model.P_net(bus_i) - P_calc(bus_i);
end
for i = 1:model.n_V
    bus_i = model.V_idx(i);
    mismatch(model.n_delta + i) = model.Q_net(bus_i) - Q_calc(bus_i);
end
end

function print_header(model, acceleration)
fprintf('============================================================\n');
fprintf('       %s\n', upper(model.system_name));
fprintf('       Gauss-Seidel Method\n');
fprintf('============================================================\n\n');
fprintf('System has %d buses and %d transmission lines\n', model.num_buses, model.num_lines);
fprintf('Slack buses: ');
disp(model.external_bus_ids(model.slack_buses).');
fprintf('PV buses: ');
disp(model.external_bus_ids(model.pv_buses).');
fprintf('PQ buses: ');
disp(model.external_bus_ids(model.pq_buses).');
fprintf('Acceleration factor: %.3f\n\n', acceleration);
fprintf('============================================================\n');
fprintf('  GAUSS-SEIDEL ITERATION\n');
fprintf('============================================================\n\n');
end
