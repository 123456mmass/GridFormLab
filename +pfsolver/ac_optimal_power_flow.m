function results = ac_optimal_power_flow(case_data, options)
%AC_OPTIMAL_POWER_FLOW Full-network AC OPF with a self-written optimizer.
%   The solver uses the project's Newton-Raphson power-flow routine to satisfy
%   AC P/Q balance, then searches over controllable generator P setpoints and
%   generator voltage setpoints with a custom coordinate pattern search.
%
%   No MATLAB Optimization Toolbox or OPF/PF toolbox solvers are used.

if nargin < 1 || isempty(case_data)
    case_data = case_ieee5bus();
end
if nargin < 2
    options = struct();
end

pf_init_paths();

model = pf_prepare_case(case_data);
opf = prepare_ac_opf_data(case_data, model, options);

tolerance = pf_get_option(options, 'tolerance', 1e-6);
max_iter = pf_get_option(options, 'max_iter', 80);
plot_results = pf_get_option(options, 'plot_results', true);
verbose = pf_get_option(options, 'verbose', true);

if verbose
    fprintf('============================================================\n');
    fprintf('       %s\n', upper(model.system_name));
    fprintf('       AC Optimal Power Flow\n');
    fprintf('============================================================\n\n');
    fprintf('Custom optimizer: coordinate pattern search + internal NR power flow\n');
    fprintf('Buses: %d, lines: %d, generators: %d\n\n', model.num_buses, model.num_lines, opf.num_generators);
end

[best, search] = run_pattern_search(model, opf, options, tolerance, max_iter, verbose);
results = build_ac_opf_results(best, model, opf, search, tolerance);

if verbose
    print_ac_opf_report(results);
end

if plot_results
    plot_ac_opf_results(results);
end
end

function opf = prepare_ac_opf_data(case_data, model, options)
opf = struct();
opf.S_base_MVA = model.base_values.S_base_MVA;
if opf.S_base_MVA <= 0
    error('base_values.S_base_MVA must be positive for AC OPF.');
end

ac = struct();
if isfield(case_data, 'opf_data') && isstruct(case_data.opf_data) && isfield(case_data.opf_data, 'ac')
    ac = case_data.opf_data.ac;
elseif isfield(case_data, 'ac_opf_data') && isstruct(case_data.ac_opf_data)
    ac = case_data.ac_opf_data;
end

if isfield(ac, 'generator_bus_ids') && ~isempty(ac.generator_bus_ids)
    generator_bus_ids = ac.generator_bus_ids(:);
else
    generator_bus_ids = model.external_bus_ids([model.slack_buses; model.pv_buses]);
end

[ok, generator_bus_idx] = ismember(generator_bus_ids, model.external_bus_ids);
if any(~ok)
    error('AC OPF generator_bus_ids contains bus numbers not present in bus_data.');
end
if isempty(generator_bus_idx)
    error('AC OPF requires at least one generator bus.');
end

ng = numel(generator_bus_idx);
if isfield(ac, 'generator_ids') && ~isempty(ac.generator_ids)
    generator_ids = ac.generator_ids(:);
else
    generator_ids = generator_bus_ids;
end
if numel(generator_ids) ~= ng
    error('AC OPF generator_ids must match generator_bus_ids.');
end

total_load_MW = sum(model.P_load) * opf.S_base_MVA;
default_cost = [zeros(ng, 1), 12 + (0:ng - 1).' * 0.8, 0.010 + (0:ng - 1).' * 0.003];
cost = get_value_or_default(ac, 'cost', default_cost);
if size(cost, 1) ~= ng || size(cost, 2) ~= 3
    error('AC OPF cost must be ng-by-3 [alpha beta gamma], using P in MW.');
end
if any(cost(:, 3) < 0)
    error('AC OPF quadratic cost gamma values must be non-negative.');
end

default_Pmax = max(total_load_MW, 1) * ones(ng, 1);
default_Qmax = max(total_load_MW, 1) * ones(ng, 1);

opf.generator_ids = generator_ids;
opf.generator_bus_ids = generator_bus_ids;
opf.generator_bus_idx = generator_bus_idx(:);
opf.num_generators = ng;
opf.cost = cost;
opf.P_min_MW = get_column_or_default(ac, 'P_min_MW', zeros(ng, 1), ng);
opf.P_max_MW = get_column_or_default(ac, 'P_max_MW', default_Pmax, ng);
opf.Q_min_MVAr = get_column_or_default(ac, 'Q_min_MVAr', -default_Qmax, ng);
opf.Q_max_MVAr = get_column_or_default(ac, 'Q_max_MVAr', default_Qmax, ng);
opf.V_min = get_limit_vector(ac, options, 'V_min', 'v_min', 0.95, model.num_buses);
opf.V_max = get_limit_vector(ac, options, 'V_max', 'v_max', 1.10, model.num_buses);
opf.S_line_max_MVA = get_optional_line_limits(ac, model.num_lines);

opf.slack_gen_pos = find(opf.generator_bus_idx == model.slack_buses, 1);
if isempty(opf.slack_gen_pos)
    error('AC OPF requires the slack bus to be included as a generator.');
end

if any(opf.P_min_MW > opf.P_max_MW) || any(opf.Q_min_MVAr > opf.Q_max_MVAr)
    error('AC OPF generator min limits must be <= max limits.');
end
if any(opf.V_min > opf.V_max)
    error('AC OPF voltage V_min must be <= V_max.');
end
end

function value = get_value_or_default(s, field_name, default_value)
if isfield(s, field_name) && ~isempty(s.(field_name))
    value = s.(field_name);
else
    value = default_value;
end
end

function values = get_column_or_default(s, field_name, default_value, expected_count)
values = get_value_or_default(s, field_name, default_value);
values = values(:);
if numel(values) ~= expected_count
    error('AC OPF %s must contain one value per generator.', field_name);
end
end

function limits = get_limit_vector(ac, options, ac_field, option_field, default_value, n)
if isfield(options, option_field) && ~isempty(options.(option_field))
    raw = options.(option_field);
elseif isfield(ac, ac_field) && ~isempty(ac.(ac_field))
    raw = ac.(ac_field);
else
    raw = default_value;
end
if isscalar(raw)
    limits = raw * ones(n, 1);
else
    limits = raw(:);
end
if numel(limits) ~= n
    error('AC OPF %s must be scalar or contain one value per bus.', ac_field);
end
end

function limits = get_optional_line_limits(ac, num_lines)
limits = [];
if isfield(ac, 'S_line_max_MVA') && ~isempty(ac.S_line_max_MVA)
    limits = ac.S_line_max_MVA(:);
elseif isfield(ac, 'line_MVA_max') && ~isempty(ac.line_MVA_max)
    limits = ac.line_MVA_max(:);
end
if ~isempty(limits) && numel(limits) ~= num_lines
    error('AC OPF line MVA limits must contain one value per line.');
end
end

function [best, search] = run_pattern_search(model, opf, options, tolerance, max_iter, verbose)
[x, lb, ub, steps, min_steps, var_info] = initial_decision(model, opf, options, tolerance);
best = evaluate_decision(x, model, opf, options, tolerance);
evaluations = 1;
history = zeros(max_iter, 4);

for iter = 1:max_iter
    improved = false;
    for k = 1:numel(x)
        directions = [1; -1];
        for d = 1:numel(directions)
            candidate_x = x;
            candidate_x(k) = min(max(candidate_x(k) + directions(d) * steps(k), lb(k)), ub(k));
            if abs(candidate_x(k) - x(k)) < eps
                continue;
            end

            candidate = evaluate_decision(candidate_x, model, opf, options, tolerance);
            evaluations = evaluations + 1;
            if candidate.score < best.score - max(1e-7, 1e-8 * abs(best.score))
                best = candidate;
                x = candidate_x;
                improved = true;
                if verbose
                    fprintf('AC OPF iter %3d improved %-10s score %.6f cost %.6f violation %.3e\n', ...
                        iter, var_info(k).name, best.score, best.cost, best.max_violation);
                end
                break;
            end
        end
    end

    history(iter, :) = [iter, best.score, best.cost, best.max_violation];
    if ~improved
        steps = steps / 2;
    end
    if all(steps <= min_steps)
        history = history(1:iter, :);
        break;
    end
end

search = struct();
search.iterations = size(history, 1);
search.evaluations = evaluations;
search.history = history;
search.final_steps = steps;
search.min_steps = min_steps;
search.variable_info = var_info;
end

function [x, lb, ub, steps, min_steps, var_info] = initial_decision(model, opf, options, tolerance)
base = base_power_flow(model, tolerance);
economic_P = economic_initial_dispatch(model, opf, base);

x = [];
lb = [];
ub = [];
steps = [];
min_steps = [];
var_info = struct('kind', {}, 'generator_pos', {}, 'bus_idx', {}, 'name', {});

for k = 1:opf.num_generators
    if k == opf.slack_gen_pos
        continue;
    end
    if opf.P_max_MW(k) - opf.P_min_MW(k) <= 1e-9
        continue;
    end
    x(end + 1, 1) = economic_P(k); %#ok<AGROW>
    lb(end + 1, 1) = opf.P_min_MW(k); %#ok<AGROW>
    ub(end + 1, 1) = opf.P_max_MW(k); %#ok<AGROW>
    span = max(opf.P_max_MW(k) - opf.P_min_MW(k), 1);
    steps(end + 1, 1) = min(25, max(span / 6, 1)); %#ok<AGROW>
    min_steps(end + 1, 1) = max(0.01, pf_get_option(options, 'opf_min_p_step_MW', 0.05)); %#ok<AGROW>
    var_info(end + 1, 1) = struct('kind', 'P', 'generator_pos', k, ...
        'bus_idx', opf.generator_bus_idx(k), 'name', sprintf('P_G%d', opf.generator_ids(k))); %#ok<AGROW>
end

for k = 1:opf.num_generators
    bus_i = opf.generator_bus_idx(k);
    x(end + 1, 1) = min(max(base.bus_voltage(bus_i), opf.V_min(bus_i)), opf.V_max(bus_i)); %#ok<AGROW>
    lb(end + 1, 1) = opf.V_min(bus_i); %#ok<AGROW>
    ub(end + 1, 1) = opf.V_max(bus_i); %#ok<AGROW>
    steps(end + 1, 1) = pf_get_option(options, 'opf_initial_v_step', 0.01); %#ok<AGROW>
    min_steps(end + 1, 1) = max(1e-5, pf_get_option(options, 'opf_min_v_step', 1e-4)); %#ok<AGROW>
    var_info(end + 1, 1) = struct('kind', 'V', 'generator_pos', k, ...
        'bus_idx', bus_i, 'name', sprintf('V_bus%d', opf.generator_bus_ids(k))); %#ok<AGROW>
end
end

function base = base_power_flow(model, tolerance)
pf_options = struct('max_iter', 60, 'tolerance', tolerance, ...
    'plot_results', false, 'verbose', false, 'enforce_q_limits', false);
base = powerflow_newton_raphson(model.case_data, pf_options);
if ~base.converged
    error('Base case did not converge; AC OPF cannot start.');
end
end

function P = economic_initial_dispatch(model, opf, base)
P = zeros(opf.num_generators, 1);
dispatch_gens = find(opf.P_max_MW > opf.P_min_MW + 1e-9);
if isempty(dispatch_gens)
    error('AC OPF needs at least one generator with P range.');
end

target_demand = sum(model.P_load) * opf.S_base_MVA + max(base.P_loss_total, 0) * opf.S_base_MVA;
fixed = false(numel(dispatch_gens), 1);
P_dispatch = zeros(numel(dispatch_gens), 1);

for guard = 1:numel(dispatch_gens) + 5
    free = ~fixed;
    remaining = target_demand - sum(P_dispatch(fixed));
    gens = dispatch_gens(free);
    beta = opf.cost(gens, 2);
    gamma = max(opf.cost(gens, 3), 1e-9);
    lambda = (remaining + sum(beta ./ (2 .* gamma))) / sum(1 ./ (2 .* gamma));
    P_dispatch(free) = (lambda - beta) ./ (2 .* gamma);

    low = free & P_dispatch < opf.P_min_MW(dispatch_gens) - 1e-9;
    high = free & P_dispatch > opf.P_max_MW(dispatch_gens) + 1e-9;
    if ~any(low | high)
        break;
    end
    P_dispatch(low) = opf.P_min_MW(dispatch_gens(low));
    P_dispatch(high) = opf.P_max_MW(dispatch_gens(high));
    fixed = fixed | low | high;
end

P(dispatch_gens) = min(max(P_dispatch, opf.P_min_MW(dispatch_gens)), opf.P_max_MW(dispatch_gens));
end

function evaluation = evaluate_decision(x, model, opf, options, tolerance)
case_data = decision_to_case(x, model, opf);
pf_options = struct('max_iter', pf_get_option(options, 'opf_pf_max_iter', 60), ...
    'tolerance', tolerance, 'plot_results', false, 'verbose', false, ...
    'enforce_q_limits', false);

try
    pf_result = powerflow_newton_raphson(case_data, pf_options);
catch err
    evaluation = failed_evaluation(x, sprintf('PF error: %s', err.message));
    return;
end

if ~pf_result.converged || any(~isfinite(pf_result.bus_voltage))
    evaluation = failed_evaluation(x, 'PF did not converge');
    return;
end

Pg_MW = pf_result.P_generation(opf.generator_bus_idx) * opf.S_base_MVA;
Qg_MVAr = pf_result.Q_generation(opf.generator_bus_idx) * opf.S_base_MVA;
cost = generator_cost(Pg_MW, opf);
[line_from_MVA, line_to_MVA] = line_apparent_power_MVA(pf_result, model.base_values.S_base_MVA);
[penalty, max_violation] = constraint_penalty(pf_result, Pg_MW, Qg_MVAr, line_from_MVA, line_to_MVA, opf);

evaluation = struct();
evaluation.x = x;
evaluation.case_data = case_data;
evaluation.pf_result = pf_result;
evaluation.Pg_MW = Pg_MW;
evaluation.Qg_MVAr = Qg_MVAr;
evaluation.cost = cost;
evaluation.penalty = penalty;
evaluation.score = cost + penalty;
evaluation.max_violation = max_violation;
evaluation.line_from_MVA = line_from_MVA;
evaluation.line_to_MVA = line_to_MVA;
evaluation.message = '';
end

function evaluation = failed_evaluation(x, message)
evaluation = struct();
evaluation.x = x;
evaluation.case_data = struct();
evaluation.pf_result = struct();
evaluation.Pg_MW = [];
evaluation.Qg_MVAr = [];
evaluation.cost = Inf;
evaluation.penalty = Inf;
evaluation.score = Inf;
evaluation.max_violation = Inf;
evaluation.line_from_MVA = [];
evaluation.line_to_MVA = [];
evaluation.message = message;
end

function case_data = decision_to_case(x, model, opf)
case_data = model.case_data;
case_data.bus_data(:, 2) = 3;
case_data.bus_data(model.slack_buses, 2) = 1;
non_slack_gens = opf.generator_bus_idx(opf.generator_bus_idx ~= model.slack_buses);
case_data.bus_data(non_slack_gens, 2) = 2;

case_data.bus_data(:, 5) = 0;
case_data.bus_data(:, 6) = 0;
case_data.bus_data(:, 11) = -Inf;
case_data.bus_data(:, 12) = Inf;

p_values = opf.P_min_MW;
cursor = 1;
for k = 1:opf.num_generators
    if k == opf.slack_gen_pos
        continue;
    end
    if opf.P_max_MW(k) - opf.P_min_MW(k) <= 1e-9
        p_values(k) = opf.P_min_MW(k);
        continue;
    end
    p_values(k) = x(cursor);
    cursor = cursor + 1;
end

for k = 1:opf.num_generators
    bus_i = opf.generator_bus_idx(k);
    case_data.bus_data(bus_i, 3) = x(cursor);
    cursor = cursor + 1;
    if k ~= opf.slack_gen_pos
        case_data.bus_data(bus_i, 5) = p_values(k) / opf.S_base_MVA;
    end
    case_data.bus_data(bus_i, 11) = opf.Q_min_MVAr(k) / opf.S_base_MVA;
    case_data.bus_data(bus_i, 12) = opf.Q_max_MVAr(k) / opf.S_base_MVA;
end
end

function cost = generator_cost(P_MW, opf)
cost = sum(opf.cost(:, 1) + opf.cost(:, 2) .* P_MW + opf.cost(:, 3) .* P_MW .^ 2);
end

function [penalty, max_violation] = constraint_penalty(result, Pg_MW, Qg_MVAr, line_from_MVA, line_to_MVA, opf)
violations = [];
violations = [violations; opf.P_min_MW - Pg_MW; Pg_MW - opf.P_max_MW]; %#ok<AGROW>
violations = [violations; opf.Q_min_MVAr - Qg_MVAr; Qg_MVAr - opf.Q_max_MVAr]; %#ok<AGROW>
violations = [violations; 100 * (opf.V_min - result.bus_voltage); 100 * (result.bus_voltage - opf.V_max)]; %#ok<AGROW>
if ~isempty(opf.S_line_max_MVA)
    violations = [violations; line_from_MVA - opf.S_line_max_MVA; line_to_MVA - opf.S_line_max_MVA]; %#ok<AGROW>
end
violations = max(violations, 0);
max_violation = max([violations; 0]);
penalty = 1e5 * sum(violations .^ 2);
end

function results = build_ac_opf_results(best, model, opf, search, tolerance)
if isempty(fieldnames(best.pf_result))
    error('AC OPF failed before a feasible power-flow point was found: %s', best.message);
end

results = best.pf_result;
results.method = 'AC Optimal Power Flow';
results.iterations = search.iterations;
results.opf_type = 'AC';
results.opf_solver = 'Custom coordinate pattern search';
results.generator_ids = opf.generator_ids;
results.generator_bus_ids = opf.generator_bus_ids;
results.equivalent_bus_count = model.num_buses;
results.P_demand_MW = sum(model.P_load) * opf.S_base_MVA;
results.Q_demand_MVAr = sum(model.Q_load) * opf.S_base_MVA;
results.P_generation_MW = best.Pg_MW;
results.Q_generation_MVAr = best.Qg_MVAr;
results.P_min_MW = opf.P_min_MW;
results.P_max_MW = opf.P_max_MW;
results.Q_min_MVAr = opf.Q_min_MVAr;
results.Q_max_MVAr = opf.Q_max_MVAr;
results.cost_coefficients = opf.cost;
results.generator_cost = opf.cost(:, 1) + opf.cost(:, 2) .* best.Pg_MW + opf.cost(:, 3) .* best.Pg_MW .^ 2;
results.incremental_cost = opf.cost(:, 2) + 2 .* opf.cost(:, 3) .* best.Pg_MW;
results.total_cost = best.cost;
results.lambda = mean(results.incremental_cost);
results.lambda_note = 'Mean generator incremental cost; AC OPF is solved by network-feasible search.';
results.active_limits = active_limit_labels(best.Pg_MW, best.Qg_MVAr, opf, tolerance);
results.V_min = opf.V_min;
results.V_max = opf.V_max;
results.line_from_MVA = best.line_from_MVA;
results.line_to_MVA = best.line_to_MVA;
results.S_line_max_MVA = opf.S_line_max_MVA;
if isempty(opf.S_line_max_MVA)
    results.line_loading_percent = [];
else
    results.line_loading_percent = 100 * max(best.line_from_MVA, best.line_to_MVA) ./ opf.S_line_max_MVA;
end
results.max_power_balance_mismatch = abs(results.mismatch_history(end));
results.max_constraint_violation = best.max_violation;
results.search_evaluations = search.evaluations;
results.search_history = search.history;
results.converged = results.converged && best.max_violation <= max(1e-3, 10 * tolerance);
end

function labels = active_limit_labels(P_MW, Q_MVAr, opf, tolerance)
labels = strings(opf.num_generators, 1);
labels(:) = "free";
tol = max(1e-4, tolerance * opf.S_base_MVA * 10);
for k = 1:opf.num_generators
    parts = strings(0, 1);
    if abs(P_MW(k) - opf.P_min_MW(k)) <= tol
        parts(end + 1, 1) = "Pmin"; %#ok<AGROW>
    elseif abs(P_MW(k) - opf.P_max_MW(k)) <= tol
        parts(end + 1, 1) = "Pmax"; %#ok<AGROW>
    end
    if abs(Q_MVAr(k) - opf.Q_min_MVAr(k)) <= tol
        parts(end + 1, 1) = "Qmin"; %#ok<AGROW>
    elseif abs(Q_MVAr(k) - opf.Q_max_MVAr(k)) <= tol
        parts(end + 1, 1) = "Qmax"; %#ok<AGROW>
    end
    if ~isempty(parts)
        labels(k) = strjoin(parts, "+");
    end
end
end

function [line_from_MVA, line_to_MVA] = line_apparent_power_MVA(results, S_base_MVA)
S_from = results.line_flow_P(:) + 1i * results.line_flow_Q(:);
S_to = (results.line_loss_P(:) - results.line_flow_P(:)) + ...
    1i * (results.line_loss_Q(:) - results.line_flow_Q(:));
line_from_MVA = abs(S_from) * S_base_MVA;
line_to_MVA = abs(S_to) * S_base_MVA;
end

function print_ac_opf_report(results)
fprintf('============================================================\n');
fprintf('       AC OPTIMAL POWER FLOW RESULTS\n');
fprintf('============================================================\n');
fprintf('Converged: %d, search iterations: %d, evaluations: %d\n', ...
    results.converged, results.iterations, results.search_evaluations);
fprintf('Total cost: %.4f $/h\n', results.total_cost);
fprintf('Max power-flow mismatch: %.6e pu\n', results.max_power_balance_mismatch);
fprintf('Max OPF constraint violation: %.6e\n', results.max_constraint_violation);
fprintf('Demand: %.4f MW, %.4f MVAr\n\n', results.P_demand_MW, results.Q_demand_MVAr);
fprintf('%-8s %-8s %-12s %-12s %-12s %-12s\n', 'Gen', 'Bus', 'P_MW', 'Q_MVAr', 'IncCost', 'Limit');
for k = 1:numel(results.generator_ids)
    fprintf('%-8g %-8g %-12.4f %-12.4f %-12.4f %-12s\n', ...
        results.generator_ids(k), results.generator_bus_ids(k), ...
        results.P_generation_MW(k), results.Q_generation_MVAr(k), ...
        results.incremental_cost(k), char(results.active_limits(k)));
end
fprintf('\n');
end

function plot_ac_opf_results(results)
figure('Name', sprintf('%s - AC OPF', results.system_name), ...
    'Color', 'w', 'Position', [130 90 1080 600]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(results.external_bus_ids, results.bus_voltage, 0.65, 'FaceColor', [0.16 0.45 0.55], 'EdgeColor', 'none');
hold on;
plot(results.external_bus_ids, results.V_min, 'r--');
plot(results.external_bus_ids, results.V_max, 'r--');
hold off;
xlabel('Bus');
ylabel('|V| (pu)');
title('Voltage Profile');
grid on;

nexttile;
bar(results.generator_ids, results.P_generation_MW, 0.65, 'FaceColor', [0.79 0.45 0.14], 'EdgeColor', 'none');
xlabel('Generator');
ylabel('P (MW)');
title('Optimal Dispatch');
grid on;

nexttile;
bar(results.generator_ids, results.generator_cost, 0.65, 'FaceColor', [0.31 0.53 0.24], 'EdgeColor', 'none');
xlabel('Generator');
ylabel('Cost ($/h)');
title(sprintf('Total Cost %.2f $/h', results.total_cost));
grid on;

nexttile;
if isempty(results.line_loading_percent)
    bar(max(results.line_from_MVA, results.line_to_MVA), 0.65, 'FaceColor', [0.38 0.38 0.46], 'EdgeColor', 'none');
    ylabel('MVA');
    title('Line Apparent Flow');
else
    bar(results.line_loading_percent, 0.65, 'FaceColor', [0.38 0.38 0.46], 'EdgeColor', 'none');
    yline(100, 'r--');
    ylabel('Loading (%)');
    title('Line Loading');
end
xlabel('Line');
grid on;
end
