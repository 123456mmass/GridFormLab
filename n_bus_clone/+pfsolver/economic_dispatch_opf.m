function results = economic_dispatch_opf(case_data, options)
%ECONOMIC_DISPATCH_OPF Economic dispatch OPF following Saadat Chapter 7.
%   This is the classical real-power dispatch model used in Saadat's
%   "Optimal Dispatch of Generation" chapter. It minimizes
%       C_i = alpha_i + beta_i P_i + gamma_i P_i^2
%   subject to sum(P_i)=P_demand, with optional generator MW limits.

if nargin < 1 || isempty(case_data)
    case_data = case_saadat_opf_example_7_4();
end
if nargin < 2
    options = struct();
end

pf_init_paths();

verbose = pf_get_option(options, 'verbose', true);
plot_results = pf_get_option(options, 'plot_results', true);
tolerance = pf_get_option(options, 'tolerance', 1e-6);

opf = validate_opf_case(case_data);
[P, lambda, iterations, active_limits] = solve_dispatch(opf.cost, opf.P_demand_MW, opf.P_min_MW, opf.P_max_MW, tolerance);

alpha = opf.cost(:, 1);
beta = opf.cost(:, 2);
gamma = opf.cost(:, 3);
generator_cost = alpha + beta .* P + gamma .* P .^ 2;
incremental_cost = beta + 2 .* gamma .* P;

results = struct();
results.system_name = char(case_data.system_name);
results.method = 'OPF Economic Dispatch';
results.generator_ids = opf.generator_ids(:);
results.equivalent_bus_count = opf.equivalent_bus_count;
results.P_demand_MW = opf.P_demand_MW;
results.P_generation_MW = P;
results.lambda = lambda;
results.incremental_cost = incremental_cost;
results.generator_cost = generator_cost;
results.total_cost = sum(generator_cost);
results.cost_coefficients = opf.cost;
results.P_min_MW = opf.P_min_MW;
results.P_max_MW = opf.P_max_MW;
results.active_limits = active_limits;
results.iterations = iterations;
results.converged = abs(sum(P) - opf.P_demand_MW) <= tolerance;
results.reference = get_optional_field(case_data, 'reference', struct());
if isfield(case_data, 'reference_solution')
    results.reference_solution = case_data.reference_solution;
end

if verbose
    print_opf_report(results);
end

if plot_results
    plot_opf_results(results);
end
end

function opf = validate_opf_case(case_data)
if ~isstruct(case_data) || ~isfield(case_data, 'opf_data')
    error('Selected case does not contain opf_data. Choose a Saadat OPF case for OPF Economic Dispatch.');
end

opf = case_data.opf_data;
required = {'cost', 'P_demand_MW'};
for i = 1:numel(required)
    if ~isfield(opf, required{i}) || isempty(opf.(required{i}))
        error('opf_data.%s is required.', required{i});
    end
end

if size(opf.cost, 2) ~= 3
    error('opf_data.cost must be [alpha beta gamma] per generator.');
end
num_generators = size(opf.cost, 1);
if any(opf.cost(:, 3) <= 0)
    error('All quadratic gamma coefficients must be positive.');
end

if ~isfield(opf, 'generator_ids') || isempty(opf.generator_ids)
    opf.generator_ids = (1:num_generators).';
end
if ~isfield(opf, 'P_min_MW') || isempty(opf.P_min_MW)
    opf.P_min_MW = -Inf(num_generators, 1);
end
if ~isfield(opf, 'P_max_MW') || isempty(opf.P_max_MW)
    opf.P_max_MW = Inf(num_generators, 1);
end
if ~isfield(opf, 'equivalent_bus_count') || isempty(opf.equivalent_bus_count)
    opf.equivalent_bus_count = 1;
end

opf.generator_ids = opf.generator_ids(:);
opf.P_min_MW = opf.P_min_MW(:);
opf.P_max_MW = opf.P_max_MW(:);

if numel(opf.generator_ids) ~= num_generators || numel(opf.P_min_MW) ~= num_generators || numel(opf.P_max_MW) ~= num_generators
    error('OPF generator_ids, P_min_MW, and P_max_MW must match the number of cost rows.');
end
if any(opf.P_min_MW > opf.P_max_MW)
    error('Each OPF P_min_MW must be <= P_max_MW.');
end
finite_sum_min = sum(opf.P_min_MW(isfinite(opf.P_min_MW)));
finite_sum_max = sum(opf.P_max_MW(isfinite(opf.P_max_MW)));
if opf.P_demand_MW < finite_sum_min && all(isfinite(opf.P_min_MW))
    error('OPF demand %.6g MW is below minimum possible generation (sum Pmin = %.6g MW).', ...
        opf.P_demand_MW, finite_sum_min);
end
if opf.P_demand_MW > finite_sum_max && all(isfinite(opf.P_max_MW))
    error('OPF demand %.6g MW exceeds maximum possible generation (sum Pmax = %.6g MW).', ...
        opf.P_demand_MW, finite_sum_max);
end
end

function [P, lambda, iterations, active_limits] = solve_dispatch(cost, P_demand, P_min, P_max, tolerance)
num_generators = size(cost, 1);
beta = cost(:, 2);
gamma = cost(:, 3);
P = zeros(num_generators, 1);
fixed = false(num_generators, 1);
active_limits = strings(num_generators, 1);
active_limits(:) = "free";
iterations = 0;

while true
    iterations = iterations + 1;
    free = ~fixed;
    remaining_demand = P_demand - sum(P(fixed));
    denom = sum(1 ./ (2 .* gamma(free)));
    numer = remaining_demand + sum(beta(free) ./ (2 .* gamma(free)));
    lambda = numer / denom;
    P(free) = (lambda - beta(free)) ./ (2 .* gamma(free));

    low = free & P < P_min - tolerance;
    high = free & P > P_max + tolerance;
    if ~any(low | high)
        P(free) = min(max(P(free), P_min(free)), P_max(free));
        break;
    end

    P(low) = P_min(low);
    P(high) = P_max(high);
    fixed = fixed | low | high;
    active_limits(low) = "min";
    active_limits(high) = "max";

    if ~any(~fixed)
        break;
    end
    if iterations > num_generators + 5
        error('Economic dispatch did not converge while applying generator limits.');
    end
end

active_limits(active_limits == "free" & abs(P - P_min) <= tolerance) = "min";
active_limits(active_limits == "free" & abs(P - P_max) <= tolerance) = "max";
end

function print_opf_report(results)
fprintf('============================================================\n');
fprintf('       %s\n', upper(results.system_name));
fprintf('       OPF Economic Dispatch\n');
fprintf('============================================================\n\n');
fprintf('Equivalent buses: %d\n', results.equivalent_bus_count);
fprintf('Generators: %d\n', numel(results.generator_ids));
fprintf('Demand: %.4f MW\n\n', results.P_demand_MW);
fprintf('Incremental cost of delivered power (system lambda) = %.4f $/MWh\n', results.lambda);
fprintf('Optimal Dispatch of Generation:\n');
fprintf('%-8s %-12s %-12s %-12s %-12s\n', 'Gen', 'P_MW', 'IncCost', 'Cost_$/h', 'Limit');
for i = 1:numel(results.generator_ids)
    fprintf('%-8g %-12.4f %-12.4f %-12.4f %-12s\n', results.generator_ids(i), ...
        results.P_generation_MW(i), results.incremental_cost(i), ...
        results.generator_cost(i), char(results.active_limits(i)));
end
fprintf('\nTotal generation cost = %.4f $/h\n', results.total_cost);
fprintf('Power balance residual = %.6e MW\n\n', sum(results.P_generation_MW) - results.P_demand_MW);
end

function plot_opf_results(results)
figure('Name', sprintf('%s - OPF Economic Dispatch', results.system_name), ...
    'Color', 'w', 'Position', [120 90 950 520]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(results.generator_ids, results.P_generation_MW, 0.65, 'FaceColor', [0.13 0.43 0.57], 'EdgeColor', 'none');
xlabel('Generator');
ylabel('P generation (MW)');
title('Optimal Dispatch');
grid on;

nexttile;
bar(results.generator_ids, results.generator_cost, 0.65, 'FaceColor', [0.82 0.44 0.17], 'EdgeColor', 'none');
xlabel('Generator');
ylabel('Cost ($/h)');
title(sprintf('Total Cost = %.2f $/h', results.total_cost));
grid on;
end

function value = get_optional_field(s, field_name, default_value)
if isfield(s, field_name)
    value = s.(field_name);
else
    value = default_value;
end
end
