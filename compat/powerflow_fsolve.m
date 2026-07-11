function results = powerflow_fsolve(case_data, options)
%POWERFLOW_FSOLVE Solve the project power-flow equations with FSOLVE.
%   This entry point uses the same case preparation, mismatch equations,
%   Jacobian convention, and result schema as the in-house Newton solver.
%   FSOLVE changes only the nonlinear root-finding algorithm.

if nargin < 1 || isempty(case_data)
    case_data = cases.case_ieee5bus();
end
if nargin < 2 || isempty(options)
    options = struct();
end

pf_init_paths();
if exist('fsolve', 'file') ~= 2
    error('powerflow_fsolve:missingFsolve', ...
        'fsolve is required for this power-flow entry point.');
end

tolerance = pf_get_option(options, 'tolerance', 1e-10);
max_iter = pf_get_option(options, 'max_iter', 200);
max_evals = pf_get_option(options, 'max_function_evaluations', 5000);
verbose = pf_get_option(options, 'verbose', false);
plot_results = pf_get_option(options, 'plot_results', false);

model = pf_prepare_case(case_data);
x0 = pf_initial_state(model);
history = zeros(max_evals, 1);
calls = 0;

solver_options = optimoptions('fsolve', ...
    'Display', ternary(verbose, 'iter', 'off'), ...
    'FunctionTolerance', tolerance, ...
    'OptimalityTolerance', tolerance, ...
    'StepTolerance', min(tolerance, 1e-12), ...
    'MaxIterations', max_iter, ...
    'MaxFunctionEvaluations', max_evals);

[x, fval, exitflag, output] = fsolve(@residual, x0, solver_options);
[delta, voltage] = pf_state_to_voltage_angle(x, model);
converged = exitflag > 0 && norm(fval, inf) <= max(10*tolerance, 1e-9);
iterations = output.iterations;
results = pf_build_results(model, voltage, delta, history(1:calls), ...
    iterations, converged, 'FSOLVE');
results.fsolve = struct('exitflag', exitflag, 'output', output, ...
    'residual_inf', norm(fval, inf));

if verbose
    pf_print_powerflow_report(results);
end
if plot_results
    pf_plot_powerflow_results(results, tolerance);
end

    function mismatch = residual(state)
        mismatch = pf_calculate_mismatch(state, model);
        calls = calls + 1;
        if calls <= numel(history)
            history(calls) = norm(mismatch, inf);
        end
    end
end

function value = ternary(condition, true_value, false_value)
if condition
    value = true_value;
else
    value = false_value;
end
end
