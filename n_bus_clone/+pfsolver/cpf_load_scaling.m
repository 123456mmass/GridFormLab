function cpf = cpf_load_scaling(case_data, options)
%CPF_LOAD_SCALING Continuation-style load scaling using repeated NR solves.
%   Load is scaled as Pload(lambda)=Pload_base+lambda*dP and
%   Qload(lambda)=Qload_base+lambda*dQ. By default, dP/dQ are the base
%   loads at PQ buses only.

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
min_voltage = pf_get_option(options, 'min_voltage', 0.65);
max_steps = pf_get_option(options, 'max_steps', 80);
tolerance = pf_get_option(options, 'tolerance', 1e-6);
nr_max_iter = pf_get_option(options, 'nr_max_iter', 30);
plot_results = pf_get_option(options, 'plot_results', true);
verbose = pf_get_option(options, 'verbose', true);

if lambda_step <= 0
    error('lambda_step must be positive.');
end
if min_lambda_step <= 0 || max_lambda_step < min_lambda_step
    error('min_lambda_step must be positive and no larger than max_lambda_step.');
end

[P_direction, Q_direction] = default_load_direction(base_model, options);

lambda_values = [];
bus_voltage = [];
bus_angle_deg = [];
target_voltage = [];
point_results = {};
step_history = [];
stop_reason = 'lambda_max reached';
previous_result = [];

lambda = 0;
current_step = min(lambda_step, max_lambda_step);
step_count = 0;
while lambda <= lambda_max + 1e-12 && step_count <= max_steps
    scaled_case = apply_load_scaling(base_model.case_data, base_model, P_direction, Q_direction, lambda, previous_result);
    nr_options = struct('max_iter', nr_max_iter, 'tolerance', tolerance, 'plot_results', false, 'verbose', false);
    result = powerflow_newton_raphson(scaled_case, nr_options);

    if ~result.converged
        if current_step / 2 >= min_lambda_step && lambda > 0
            current_step = current_step / 2;
            lambda = lambda_values(end) + current_step;
            if verbose
                fprintf('CPF load-scaling reducing lambda step to %.5f after failed solve.\n', current_step);
            end
            continue;
        end
        stop_reason = sprintf('NR did not converge at lambda %.4f', lambda);
        if verbose
            fprintf('CPF load-scaling stopped: %s\n', stop_reason);
        end
        break;
    end

    lambda_values(end + 1, 1) = lambda; %#ok<AGROW>
    bus_voltage(:, end + 1) = result.bus_voltage; %#ok<AGROW>
    bus_angle_deg(:, end + 1) = result.bus_angle_deg; %#ok<AGROW>
    target_voltage(end + 1, 1) = result.bus_voltage(target_idx); %#ok<AGROW>
    point_results{end + 1, 1} = result; %#ok<AGROW>
    step_history(end + 1, 1) = current_step; %#ok<AGROW>
    previous_result = result;

    if verbose
        fprintf('CPF load-scaling step %3d: lambda = %.4f, V(target bus %g) = %.4f pu\n', ...
            step_count, lambda, target_bus, result.bus_voltage(target_idx));
    end

    if min(result.bus_voltage) < min_voltage
        stop_reason = sprintf('minimum voltage %.4f pu below %.4f pu', min(result.bus_voltage), min_voltage);
        break;
    end

    if lambda >= lambda_max - 1e-12
        break;
    end

    current_step = min(max_lambda_step, max(min_lambda_step, current_step * 1.2));
    lambda = min(lambda + current_step, lambda_max);
    step_count = step_count + 1;
end

[lowest_voltage, lowest_idx] = min(target_voltage);
if isempty(lowest_idx)
    nose_idx = 0;
    nose_lambda = NaN;
    nose_voltage = NaN;
    lowest_lambda = NaN;
    lowest_voltage = NaN;
else
    [nose_lambda, nose_idx] = max(lambda_values);
    nose_voltage = target_voltage(nose_idx);
    lowest_lambda = lambda_values(lowest_idx);
end
nose_detected = contains(stop_reason, 'did not converge') || contains(stop_reason, 'minimum voltage');

cpf = struct();
cpf.method = 'CPF Load Scaling';
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
cpf.converged = ~isempty(lambda_values);
cpf.results = point_results;
cpf.load_direction_P = P_direction;
cpf.load_direction_Q = Q_direction;
cpf.external_bus_ids = base_model.external_bus_ids;
cpf.step_history = step_history;

if plot_results && ~isempty(lambda_values)
    plot_cpf_curve(cpf);
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

function scaled_case = apply_load_scaling(base_case, model, P_direction, Q_direction, lambda, previous_result)
scaled_case = base_case;
scaled_case.bus_data(:, 7) = model.P_load + lambda * P_direction;
scaled_case.bus_data(:, 8) = model.Q_load + lambda * Q_direction;

if ~isempty(previous_result)
    scaled_case.bus_data(:, 4) = previous_result.bus_angle_deg;
    scaled_case.bus_data(model.pq_buses, 3) = previous_result.bus_voltage(model.pq_buses);
    scaled_case.bus_data(model.slack_buses, 3) = model.V_spec(model.slack_buses);
    scaled_case.bus_data(model.pv_buses, 3) = model.V_spec(model.pv_buses);
end
end

function plot_cpf_curve(cpf)
pf_plot_cpf_results(cpf);
end
