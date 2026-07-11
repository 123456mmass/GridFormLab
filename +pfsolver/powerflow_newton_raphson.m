function results = powerflow_newton_raphson(case_data, options)
%POWERFLOW_NEWTON_RAPHSON Generic Newton-Raphson power flow solver.
%   RESULTS = POWERFLOW_NEWTON_RAPHSON(CASE_DATA, OPTIONS) solves an
%   n-bus power-flow case with bus types 1=Slack, 2=PV, and 3=PQ.
%
%   CASE_DATA.bus_data columns:
%     [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]
%     [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh]
%     [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh Qmin Qmax]
%
%   For PV and PQ buses that contain both generation and load, scheduled
%   injection is handled by net injection: Pgen-Pload and Qgen-Qload.
%   If finite Qmin/Qmax limits are supplied, PV buses that violate limits
%   are switched to PQ buses with Q generation fixed at the violated limit.

if nargin < 1 || isempty(case_data)
    case_data = case_ieee5bus();
end
if nargin < 2
    options = struct();
end

pf_init_paths();

max_iter = pf_get_option(options, 'max_iter', 20);
tolerance = pf_get_option(options, 'tolerance', 1e-6);
plot_results = pf_get_option(options, 'plot_results', true);
verbose = pf_get_option(options, 'verbose', true);
enforce_q_limits = pf_get_option(options, 'enforce_q_limits', true);
q_limit_tolerance = pf_get_option(options, 'q_limit_tolerance', 1e-6);
max_q_limit_switches = pf_get_option(options, 'max_q_limit_switches', 20);

working_case = case_data;
q_events = empty_q_event();
q_switch_round = 0;

while true
    model = pf_prepare_case(working_case);

    if verbose
        print_header(model, 'Newton-Raphson Method', q_switch_round);
    end

    results = solve_model(model, max_iter, tolerance, verbose);

    if ~results.converged || ~enforce_q_limits || q_switch_round >= max_q_limit_switches
        break;
    end

    [violated_buses, fixed_Q, limit_type] = find_q_limit_violations(model, results, q_limit_tolerance);
    if isempty(violated_buses)
        break;
    end

    q_switch_round = q_switch_round + 1;
    working_case = model.case_data;
    working_case.bus_data(:, 3) = results.bus_voltage;
    working_case.bus_data(:, 4) = results.bus_angle_deg;

    for i = 1:numel(violated_buses)
        bus_i = violated_buses(i);
        event = struct( ...
            'round', q_switch_round, ...
            'bus_id', model.external_bus_ids(bus_i), ...
            'from_type', 'PV', ...
            'to_type', 'PQ', ...
            'Q_generation_before', results.Q_generation(bus_i), ...
            'Q_fixed', fixed_Q(i), ...
            'limit_type', limit_type{i});
        q_events(end + 1, 1) = event; %#ok<AGROW>

        working_case.bus_data(bus_i, 2) = 3;
        working_case.bus_data(bus_i, 6) = fixed_Q(i);

        if verbose
            fprintf('Q-limit switching: Bus %d PV -> PQ, Qg %.6f pu fixed at %s %.6f pu\n', ...
                model.external_bus_ids(bus_i), results.Q_generation(bus_i), limit_type{i}, fixed_Q(i));
        end
    end
end

if enforce_q_limits && q_switch_round >= max_q_limit_switches && verbose
    fprintf('Q-limit switching stopped after max_q_limit_switches=%d.\n', max_q_limit_switches);
end

results.q_limit_switching = struct( ...
    'enabled', enforce_q_limits, ...
    'events', q_events, ...
    'rounds', q_switch_round, ...
    'q_limit_tolerance', q_limit_tolerance);

if verbose
    pf_print_powerflow_report(results);
end

if plot_results
    pf_plot_powerflow_results(results, tolerance);
end

if verbose
    fprintf('Results saved to variable ''results'' in workspace.\n');
    fprintf('You can also save them with: save(''powerflow_results.mat'', ''results'')\n');
end
end

function results = solve_model(model, max_iter, tolerance, verbose)
%SOLVE_MODEL Newton-Raphson iteration with strict failure semantics.
%   Failure semantics contract (Phase B):
%     C1 invalid input/schema failures are thrown by pf_prepare_case BEFORE
%        entering solve_model (stable error identifiers, bus/index reported).
%     C2 numerical-solve failures return a non-converged result with:
%          converged = false
%          reason         in {singular_jacobian, nonfinite_system,
%                              nonfinite_newton_step, nonfinite_state,
%                              max_iterations}
%          max_mismatch   (final max|mismatch|, finite when available)
%          iterations     (count at point of return)
%          finite_status  (string: 'all_finite' or 'nonfinite_at_index_N')
%     The converged path is UNCHANGED: the new checks are dead on convergence
%     (rcond(J) >> 1e-13, all states finite) so iterations/mismatch/result
%     are bit-for-bit identical to the pre-hardening solver.
%
%   Newton iteration order (Phase B contract, mandatory correction D):
%     1. compute mismatch
%     2. check mismatch finite
%     3. check convergence (breaks before Jacobian on the final iteration,
%        so the new guards below are dead on a converging case)
%     4. compute analytic Jacobian
%     5. check Jacobian finite
%     6. check conditioning (rcond >= 1e-13)
%     7. solve Newton step
%     8. check Newton step finite
%     9. update state
%    10. check updated state finite
%    11. enforce fixed REF/PV quantities (non-positive V reset)
rcond_threshold = 1e-13;   % declared upfront; matches nonlinear_newton.m:28

x = pf_initial_state(model);
mismatch_history = zeros(max_iter, 1);
converged = false;
iter = 0;
reason = '';
finite_status = 'all_finite';

while iter < max_iter
    iter = iter + 1;

    [mismatch, P_calc, Q_calc, V, delta] = pf_calculate_mismatch(x, model);
    max_mismatch = max(abs(mismatch));
    mismatch_history(iter) = max_mismatch;

    if verbose
        fprintf('Iteration %2d: Max Mismatch = %.6e\n', iter, max_mismatch);
    end

    % (2) Mismatch finiteness -- nonfinite mismatch means the system is
    % already broken (e.g. NaN propagating from a prior diverged step).
    if any(~isfinite(mismatch))
        reason = 'nonfinite_system';
        finite_status = finite_status_string(mismatch);
        if verbose
            fprintf('\n*** FAILURE: non-finite mismatch at iteration %d ***\n\n', iter);
        end
        [delta_final, V_final] = pf_state_to_voltage_angle(x, model);
        results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, false, 'Newton-Raphson');
        results = attach_failure_fields(results, reason, max_mismatch, finite_status);
        return;
    end

    if max_mismatch < tolerance
        converged = true;
        reason = 'converged';
        if verbose
            fprintf('\n*** CONVERGED in %d iterations ***\n\n', iter);
        end
        break;
    end

    % (3) Analytic Jacobian.
    J = pf_build_jacobian(V, delta, P_calc, Q_calc, model);

    % (4) Jacobian finiteness -- a nonfinite Jacobian is a numerical failure,
    % not a singular one.
    if any(~isfinite(J(:)))
        reason = 'nonfinite_system';
        finite_status = 'nonfinite_jacobian';
        if verbose
            fprintf('\n*** FAILURE: non-finite Jacobian at iteration %d ***\n\n', iter);
        end
        [delta_final, V_final] = pf_state_to_voltage_angle(x, model);
        results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, false, 'Newton-Raphson');
        results = attach_failure_fields(results, reason, max_mismatch, finite_status);
        return;
    end

    % (5) Conditioning -- rcond(J) < 1e-13 means the Jacobian is singular or
    % numerically rank-deficient (e.g. islanded bus -> zero Ybus row).
    rc = rcond(J);
    if ~isfinite(rc) || rc < rcond_threshold
        reason = 'singular_jacobian';
        finite_status = sprintf('rcond_%.2e', rc);
        if verbose
            fprintf('\n*** FAILURE: singular Jacobian (rcond=%.2e) at iteration %d ***\n\n', rc, iter);
        end
        [delta_final, V_final] = pf_state_to_voltage_angle(x, model);
        results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, false, 'Newton-Raphson');
        results = attach_failure_fields(results, reason, max_mismatch, finite_status);
        return;
    end

    % (6) Newton step.
    delta_x = J \ mismatch;

    % (7) Newton step finiteness.
    if any(~isfinite(delta_x))
        reason = 'nonfinite_newton_step';
        finite_status = finite_status_string(delta_x);
        if verbose
            fprintf('\n*** FAILURE: non-finite Newton step at iteration %d ***\n\n', iter);
        end
        [delta_final, V_final] = pf_state_to_voltage_angle(x, model);
        results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, false, 'Newton-Raphson');
        results = attach_failure_fields(results, reason, max_mismatch, finite_status);
        return;
    end

    % (8) Update state.
    x = x + delta_x;

    % (9) Updated state finiteness.
    if any(~isfinite(x))
        reason = 'nonfinite_state';
        finite_status = finite_status_string(x);
        if verbose
            fprintf('\n*** FAILURE: non-finite state at iteration %d ***\n\n', iter);
        end
        [delta_final, V_final] = pf_state_to_voltage_angle(x, model);
        results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, false, 'Newton-Raphson');
        results = attach_failure_fields(results, reason, max_mismatch, finite_status);
        return;
    end

    % (10) Enforce fixed REF/PV quantities (non-positive V reset). Runs only
    % when x is finite, which is now guaranteed by step (9).
    for i = 1:model.n_V
        v_pos = model.n_delta + i;
        if x(v_pos) <= 0
            x(v_pos) = 0.1;
            if verbose
                fprintf('  Warning: |V| at bus %d was non-positive, reset to 0.1 pu\n', ...
                    model.external_bus_ids(model.V_idx(i)));
            end
        end
    end
end

if ~converged
    reason = 'max_iterations';
    finite_status = finite_status_string(x);
    if verbose
        fprintf('\n*** WARNING: Did not converge in %d iterations ***\n\n', max_iter);
    end
end

[delta_final, V_final] = pf_state_to_voltage_angle(x, model);
results = pf_build_results(model, V_final, delta_final, mismatch_history, iter, converged, 'Newton-Raphson');
results = attach_failure_fields(results, reason, max_mismatch, finite_status);
end

function results = attach_failure_fields(results, reason, max_mismatch, finite_status)
% Attach the Phase B failure-semantics fields to a result struct. These are
% additive: existing field consumers (CPF, Q-limit loop, solve_case) read
% r.converged, which is unchanged. solve_case.m:177 already guards max_mismatch
% with isfield.
results.reason = reason;
results.max_mismatch = max_mismatch;
results.finite_status = finite_status;
end

function s = finite_status_string(v)
%FINITE_STATUS_STRING  Compact finite-status tag for failure reporting.
if all(isfinite(v(:)))
    s = 'all_finite';
else
    bad = find(~isfinite(v(:)), 1);
    s = sprintf('nonfinite_at_index_%d', bad);
end
end

function [violated_buses, fixed_Q, limit_type] = find_q_limit_violations(model, results, tolerance)
violated_buses = [];
fixed_Q = [];
limit_type = {};

for i = 1:numel(model.pv_buses)
    bus_i = model.pv_buses(i);
    Qg = results.Q_generation(bus_i);
    if isfinite(model.Q_max(bus_i)) && Qg > model.Q_max(bus_i) + tolerance
        violated_buses(end + 1, 1) = bus_i; %#ok<AGROW>
        fixed_Q(end + 1, 1) = model.Q_max(bus_i); %#ok<AGROW>
        limit_type{end + 1, 1} = 'Qmax'; %#ok<AGROW>
    elseif isfinite(model.Q_min(bus_i)) && Qg < model.Q_min(bus_i) - tolerance
        violated_buses(end + 1, 1) = bus_i; %#ok<AGROW>
        fixed_Q(end + 1, 1) = model.Q_min(bus_i); %#ok<AGROW>
        limit_type{end + 1, 1} = 'Qmin'; %#ok<AGROW>
    end
end
end

function q_events = empty_q_event()
q_events = struct( ...
    'round', {}, ...
    'bus_id', {}, ...
    'from_type', {}, ...
    'to_type', {}, ...
    'Q_generation_before', {}, ...
    'Q_fixed', {}, ...
    'limit_type', {});
end

function print_header(model, method_name, q_switch_round)
fprintf('============================================================\n');
fprintf('       %s\n', upper(model.system_name));
fprintf('       %s\n', method_name);
if q_switch_round > 0
    fprintf('       Q-Limit Switch Round %d\n', q_switch_round);
end
fprintf('============================================================\n\n');

fprintf('System Base Values:\n');
fprintf('  S_base = %.2f MVA\n', model.base_values.S_base_MVA);
if model.base_values.V_base_kV > 0
    fprintf('  V_base = %.2f kV\n', model.base_values.V_base_kV);
else
    fprintf('  V_base = N/A\n');
end
fprintf('  Frequency = %.2f Hz\n\n', model.base_values.frequency_Hz);

fprintf('Bus Data:\n');
fprintf('  Number of buses: %d\n', model.num_buses);
fprintf('  Slack buses: %d\n', numel(model.slack_buses));
fprintf('  PV buses: %d\n', numel(model.pv_buses));
fprintf('  PQ buses: %d\n\n', numel(model.pq_buses));

fprintf('Transmission Line Data:\n');
fprintf('  Number of lines: %d\n\n', model.num_lines);

fprintf('Y-bus matrix constructed successfully.\n');
fprintf('  System has %d buses and %d transmission lines\n\n', model.num_buses, model.num_lines);

fprintf('Bus Classification:\n');
fprintf('  Slack buses: ');
disp(model.external_bus_ids(model.slack_buses).');
fprintf('  PV buses: ');
disp(model.external_bus_ids(model.pv_buses).');
fprintf('  PQ buses: ');
disp(model.external_bus_ids(model.pq_buses).');
fprintf('\n');

fprintf('Number of unknowns:\n');
fprintf('  Voltage angles (delta): %d\n', model.n_delta);
fprintf('  Voltage magnitudes (|V|): %d\n', model.n_V);
fprintf('  Total unknowns: %d\n\n', model.n_total);

fprintf('============================================================\n');
fprintf('  NEWTON-RAPHSON ITERATION\n');
fprintf('============================================================\n\n');
end
