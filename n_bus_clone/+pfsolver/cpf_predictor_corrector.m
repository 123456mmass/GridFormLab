function cpf = cpf_predictor_corrector(case_data, options)
%CPF_PREDICTOR_CORRECTOR Pseudo-arclength CPF using NR Jacobian helpers.

if nargin < 1 || isempty(case_data)
    case_data = case_ieee5bus();
end
if nargin < 2
    options = struct();
end

pf_init_paths();

base_model = pf_prepare_case(case_data);
target_bus = pf_get_option(options, 'target_bus', default_target_bus(base_model));
target_idx = find(base_model.external_bus_ids == target_bus, 1);
if isempty(target_idx)
    error('target_bus %g does not exist in case_data.bus_data.', target_bus);
end

lambda_step = pf_get_option(options, 'lambda_step', 0.05);
lambda_max = pf_get_option(options, 'lambda_max', 1.5);
min_lambda_step = pf_get_option(options, 'min_lambda_step', lambda_step / 16);
max_lambda_step = pf_get_option(options, 'max_lambda_step', lambda_step);
adaptive_steps = pf_get_option(options, 'adaptive_steps', true);
min_voltage = pf_get_option(options, 'min_voltage', 0.65);
max_steps = pf_get_option(options, 'max_steps', 80);
tolerance = pf_get_option(options, 'tolerance', 1e-6);
max_corrector_iter = pf_get_option(options, 'max_corrector_iter', 12);
plot_results = pf_get_option(options, 'plot_results', true);
verbose = pf_get_option(options, 'verbose', true);

if lambda_step <= 0
    error('lambda_step must be positive.');
end
if min_lambda_step <= 0 || max_lambda_step < min_lambda_step
    error('min_lambda_step must be positive and no larger than max_lambda_step.');
end

[P_direction, Q_direction] = default_load_direction(base_model, options);

base_nr = powerflow_newton_raphson(base_model.case_data, ...
    struct('max_iter', 30, 'tolerance', tolerance, 'plot_results', false, 'verbose', false));
if ~base_nr.converged
    error('Base case did not converge; CPF cannot start.');
end

x = result_to_state(base_model, base_nr);
lambda = 0;
z = [x; lambda];

lambda_values = 0;
bus_voltage = base_nr.bus_voltage;
bus_angle_deg = base_nr.bus_angle_deg;
target_voltage = base_nr.bus_voltage(target_idx);
point_results = {base_nr};
stop_reason = 'lambda_max reached';
step_history = 0;
tangent_lambda_history = [];
previous_tangent = [];
current_step = min(lambda_step, max_lambda_step);
nose_detected = false;
nose_index_from_tangent = 0;

for step = 1:max_steps
    [mismatch, P_calc, Q_calc, V, delta] = cpf_mismatch(z(1:end - 1), z(end), base_model, P_direction, Q_direction);
    if max(abs(mismatch)) > max(1e-5, tolerance * 10)
        stop_reason = sprintf('current continuation point mismatch %.3e is too large', max(abs(mismatch)));
        break;
    end

    J = pf_build_jacobian(V, delta, P_calc, Q_calc, base_model);
    lambda_derivative = cpf_lambda_derivative(base_model, P_direction, Q_direction);
    tangent_x = J \ lambda_derivative;
    tangent = [tangent_x; 1];
    tangent = tangent / norm(tangent);
    if isempty(previous_tangent) && tangent(end) < 0
        tangent = -tangent;
    elseif ~isempty(previous_tangent) && dot(tangent, previous_tangent) < 0
        tangent = -tangent;
    end

    if ~isempty(previous_tangent) && previous_tangent(end) > 0 && tangent(end) < 0 && ~nose_detected
        nose_detected = true;
        nose_index_from_tangent = numel(lambda_values);
    end

    attempt_step = current_step;
    ok = false;
    while ~ok
        z_pred = z + attempt_step * tangent;
        [z_corr, ok, correction_iterations, correction_mismatch] = corrector(z_pred, tangent, base_model, P_direction, Q_direction, tolerance, max_corrector_iter);
        if ok || ~adaptive_steps || attempt_step / 2 < min_lambda_step
            break;
        end
        attempt_step = attempt_step / 2;
        if verbose
            fprintf('CPF predictor-corrector reducing arclength step to %.5f after failed correction.\n', attempt_step);
        end
    end

    if ~ok
        stop_reason = sprintf('corrector did not converge at predicted lambda %.4f (mismatch %.3e)', ...
            z_pred(end), max(abs(correction_mismatch)));
        break;
    end

    if z_corr(end) > lambda_max + 1e-10 && tangent(end) > 0
        stop_reason = 'lambda_max reached';
        break;
    end

    [~, ~, ~, V_corr, delta_corr] = cpf_mismatch(z_corr(1:end - 1), z_corr(end), base_model, P_direction, Q_direction);
    scaled_model = pf_prepare_case(apply_load_scaling(base_model.case_data, base_model, P_direction, Q_direction, z_corr(end)));
    point_result = pf_build_results(scaled_model, V_corr, delta_corr, correction_mismatch, correction_iterations, true, 'CPF Predictor-Corrector Point');

    z = z_corr;
    lambda_values(end + 1, 1) = z(end); %#ok<AGROW>
    bus_voltage(:, end + 1) = V_corr; %#ok<AGROW>
    bus_angle_deg(:, end + 1) = rad2deg(delta_corr); %#ok<AGROW>
    target_voltage(end + 1, 1) = V_corr(target_idx); %#ok<AGROW>
    point_results{end + 1, 1} = point_result; %#ok<AGROW>
    step_history(end + 1, 1) = attempt_step; %#ok<AGROW>
    tangent_lambda_history(end + 1, 1) = tangent(end); %#ok<AGROW>
    previous_tangent = tangent;
    current_step = min(max_lambda_step, max(min_lambda_step, attempt_step * 1.2));

    if verbose
        fprintf('CPF predictor-corrector step %3d: lambda = %.4f, V(target bus %g) = %.4f pu, corrector iters = %d\n', ...
            step, z(end), target_bus, V_corr(target_idx), correction_iterations);
    end

    if min(V_corr) < min_voltage
        stop_reason = sprintf('minimum voltage %.4f pu below %.4f pu', min(V_corr), min_voltage);
        break;
    end
end

[lowest_voltage, lowest_idx] = min(target_voltage);
if isempty(lowest_idx)
    nose_idx = 0;
    nose_lambda = NaN;
    nose_voltage = NaN;
    lowest_lambda = NaN;
    lowest_voltage = NaN;
elseif nose_detected && nose_index_from_tangent > 0
    nose_idx = nose_index_from_tangent;
    nose_lambda = lambda_values(nose_idx);
    nose_voltage = target_voltage(nose_idx);
    lowest_lambda = lambda_values(lowest_idx);
else
    [nose_lambda, nose_idx] = max(lambda_values);
    nose_voltage = target_voltage(nose_idx);
    lowest_lambda = lambda_values(lowest_idx);
end

cpf = struct();
cpf.method = 'CPF Predictor-Corrector';
cpf.system_name = base_model.system_name;
cpf.target_bus = target_bus;
cpf.target_bus_index = target_idx;
cpf.lambdas = lambda_values;
cpf.bus_voltage = bus_voltage;
cpf.bus_angle_deg = bus_angle_deg;
cpf.target_voltage = target_voltage;
cpf.nose_index = nose_idx;
cpf.nose_lambda = nose_lambda;
cpf.nose_voltage = nose_voltage;
cpf.nose_detected = nose_detected;
cpf.lowest_index = lowest_idx;
cpf.lowest_lambda = lowest_lambda;
cpf.lowest_voltage = lowest_voltage;
cpf.stop_reason = stop_reason;
cpf.converged = numel(lambda_values) > 1;
cpf.results = point_results;
cpf.load_direction_P = P_direction;
cpf.load_direction_Q = Q_direction;
cpf.external_bus_ids = base_model.external_bus_ids;
cpf.step_history = step_history;
cpf.tangent_lambda_history = tangent_lambda_history;

if plot_results && ~isempty(lambda_values)
    plot_cpf_curve(cpf);
end
end

function [mismatch, P_calc, Q_calc, V, delta] = cpf_mismatch(x, lambda, model, P_direction, Q_direction)
P_spec = model.P_gen - (model.P_load + lambda * P_direction);
Q_spec = model.Q_gen - (model.Q_load + lambda * Q_direction);
[mismatch, P_calc, Q_calc, V, delta] = pf_calculate_mismatch(x, model, P_spec, Q_spec);
end

function lambda_derivative = cpf_lambda_derivative(model, P_direction, Q_direction)
lambda_derivative = zeros(model.n_total, 1);
for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    lambda_derivative(i) = -P_direction(bus_i);
end
for i = 1:model.n_V
    bus_i = model.V_idx(i);
    lambda_derivative(model.n_delta + i) = -Q_direction(bus_i);
end
end

function [z, ok, iter, mismatch_history] = corrector(z_pred, tangent, model, P_direction, Q_direction, tolerance, max_iter)
z = z_pred;
ok = false;
mismatch_history = zeros(max_iter, 1);

for iter = 1:max_iter
    x = z(1:end - 1);
    lambda = z(end);
    [mismatch, P_calc, Q_calc, V, delta] = cpf_mismatch(x, lambda, model, P_direction, Q_direction);
    arc_error = tangent' * (z - z_pred);
    mismatch_history(iter) = max(abs([mismatch; arc_error]));

    if mismatch_history(iter) < tolerance
        ok = true;
        mismatch_history = mismatch_history(1:iter);
        return;
    end

    if any(V <= 0) || ~isfinite(lambda)
        mismatch_history = mismatch_history(1:iter);
        return;
    end

    J = pf_build_jacobian(V, delta, P_calc, Q_calc, model);
    lambda_derivative = cpf_lambda_derivative(model, P_direction, Q_direction);
    augmented = [J, -lambda_derivative; tangent'];
    rhs = [mismatch; -arc_error];
    dz = augmented \ rhs;
    z = z + dz;
end

mismatch_history = mismatch_history(1:max_iter);
end

function x = result_to_state(model, result)
x = zeros(model.n_total, 1);
for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    x(i) = result.bus_angle(bus_i);
end
for i = 1:model.n_V
    bus_i = model.V_idx(i);
    x(model.n_delta + i) = result.bus_voltage(bus_i);
end
end

function target_bus = default_target_bus(model)
if any(model.external_bus_ids == 5)
    target_bus = 5;
elseif ~isempty(model.pq_buses)
    target_bus = model.external_bus_ids(model.pq_buses(end));
else
    target_bus = model.external_bus_ids(end);
end
end

function [P_direction, Q_direction] = default_load_direction(model, options)
P_direction = zeros(model.num_buses, 1);
Q_direction = zeros(model.num_buses, 1);

load_buses = pf_get_option(options, 'load_buses', model.external_bus_ids(model.pq_buses));
for i = 1:numel(load_buses)
    idx = find(model.external_bus_ids == load_buses(i), 1);
    if isempty(idx)
        error('load_buses contains unknown bus %g.', load_buses(i));
    end
    P_direction(idx) = model.P_load(idx);
    Q_direction(idx) = model.Q_load(idx);
end

if isfield(options, 'P_direction') && ~isempty(options.P_direction)
    P_direction = options.P_direction(:);
end
if isfield(options, 'Q_direction') && ~isempty(options.Q_direction)
    Q_direction = options.Q_direction(:);
end

if numel(P_direction) ~= model.num_buses || numel(Q_direction) ~= model.num_buses
    error('P_direction and Q_direction must have one value per bus.');
end
end

function scaled_case = apply_load_scaling(base_case, model, P_direction, Q_direction, lambda)
scaled_case = base_case;
scaled_case.bus_data(:, 7) = model.P_load + lambda * P_direction;
scaled_case.bus_data(:, 8) = model.Q_load + lambda * Q_direction;
end

function plot_cpf_curve(cpf)
pf_plot_cpf_results(cpf);
end
