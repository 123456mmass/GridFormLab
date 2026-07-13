function results = powerflow_fdpf(case_data, options, variant)
%POWERFLOW_FDPF  Shared Fast Decoupled Power Flow solver (CORE_ONLY, NOT_ROUTED).
%   RESULTS = POWERFLOW_FDPF(CASE_DATA, OPTIONS, VARIANT) solves the power flow
%   using the fast decoupled load flow method (Stott-Alsac 1974 + van Amerongen
%   1989 variants).
%
%   Sources (VERIFIED):
%     Stott & Alsac (1974), IEEE Trans. PAS-93, pp.859-869, DOI 10.1109/TPAS.1974.293985.
%       Equations (8) [dP/V]=[B'][dtheta] and (9) [dQ/V]=[B''][dV]; construction
%       items (a)-(d) p.863; convergence: max|dP|, max|dQ| (power mismatch).
%     van Amerongen (1989), IEEE Trans. Power Systems 4(2), pp.760-766.
%       Variant definitions (BB/XB/BX/XX) p.761.
%
%   VARIANT: 'XB' (default, Stott-Alsac original; remove R in B') or
%            'BX' (van Amerongen proposed; remove R in B'').
%
%   P1 scope (package-only, per plan §2 ownership route):
%   This solver is CORE_ONLY / NOT_ROUTED. solve_case.m is NOT modified to
%   route through it. Tested by direct calls. Production routing readiness
%   NOT_READY until the single-owner integration files are separately resolved.
%
%   FULL AC MISMATCH RECOMPUTATION (binding, per user correction 3): the full
%   nonlinear AC mismatch is recomputed at THREE points per iteration:
%     (1) initially (start of iteration, current V, theta);
%     (2) after the P/theta update (recompute dP AND dQ with the new theta);
%     (3) after the Q/|V| update (final convergence check).
%   The Q mismatch is NEVER reused stale after theta changes.
%
%   Q-LIMITS (binding, per user correction 3): uses the shared helper
%   internal/core/pf_find_q_limit_violations.m (parity-tested against NR's
%   private function). NR is NOT modified. The Q-limit switching loop follows
%   the same pattern as NR (powerflow_newton_raphson.m:37-80): detect
%   violations, switch bus_data(bus_i,2)=3 (PV->PQ), fix Qgen, re-prepare,
%   re-solve. B'' is re-factorized on PV->PQ (B' is unchanged since PV buses
%   are already excluded from B' unknowns).
%
%   No inv/pinv. Factorization via lu; reuse across iterations.

pf_init_paths();
if nargin < 1 || isempty(case_data)
    case_data = cases.case_ieee5bus();
end
if nargin < 2 || isempty(options), options = struct(); end
if nargin < 3 || isempty(variant), variant = 'XB'; end
variant = upper(variant);

max_iter = pf_get_option(options, 'max_iter', 50);
tolerance = pf_get_option(options, 'tolerance', 1e-10);
verbose = pf_get_option(options, 'verbose', true);
enforce_q_limits = pf_get_option(options, 'enforce_q_limits', true);
q_limit_tolerance = pf_get_option(options, 'q_limit_tolerance', 1e-6);
max_q_limit_switches = pf_get_option(options, 'max_q_limit_switches', 20);

working_case = case_data;
q_events = struct('round',{},'bus_id',{},'from_type',{},'to_type',{}, ...
    'Q_generation_before',{},'Q_fixed',{},'limit_type',{});
q_switch_round = 0;
mismatch_history = [];
iterations_total = 0;

while true
    model = pf_prepare_case(working_case);
    [Bp_full, Bpp_full] = pf_build_b_matrices(model, variant);

    % Reduced matrices: B' on delta_idx (REF excluded); B'' on V_idx (PV excluded).
    Bp_red  = Bp_full(model.delta_idx, model.delta_idx);
    Bpp_red = Bpp_full(model.V_idx, model.V_idx);

    % Factorize once per Q-limit round (constant within a round).
    [Lp, Up, Pp] = lu(Bp_red);
    [Lpp, Upp, Ppp] = lu(Bpp_red);

    % Initial state: V from V_spec, theta from angle_spec (radians).
    theta = deg2rad(model.angle_spec_deg);
    Vmag = model.V_spec;

    iter = 0;
    converged = false;
    for iter = 1:max_iter
        % (1) INITIAL full AC mismatch (current V, theta).
        [mismatch, P_calc, Q_calc, V_cur, theta_cur] = full_ac_mismatch(model, Vmag, theta);
        max_mismatch = max(abs(mismatch));
        mismatch_history(end+1, 1) = max_mismatch; %#ok<AGROW>
        if max_mismatch < tolerance
            converged = true; break;
        end

        % P-theta half: [dP/V] = [B'][dtheta].
        dP = mismatch(1:model.n_delta);
        V_at_delta = Vmag(model.delta_idx);
        rhs_P = dP ./ V_at_delta;
        dtheta_red = Up \ (Lp \ (Pp * rhs_P));
        theta(model.delta_idx) = theta(model.delta_idx) + dtheta_red;

        % (2) AFTER P/theta update: recompute full AC mismatch (dP AND dQ with
        % the new theta). Do NOT reuse stale Q.
        [mismatch2, ~, ~, ~, ~] = full_ac_mismatch(model, Vmag, theta);

        % Q-V half: [dQ/V] = [B''][dV].
        dQ = mismatch2(model.n_delta + (1:model.n_V));
        V_at_V = Vmag(model.V_idx);
        rhs_Q = dQ ./ V_at_V;
        dV_red = Upp \ (Lpp \ (Ppp * rhs_Q));
        Vmag(model.V_idx) = Vmag(model.V_idx) + dV_red;

        % (3) AFTER Q/V update: final convergence check uses the full AC mismatch
        % recomputed with the new V (and the updated theta). This is checked at
        % the TOP of the next iteration (the initial mismatch recomputation).
    end
    iterations_total = iterations_total + iter;

    % Build a results-like struct for Q-limit checking.
    [P_final, Q_final] = pf_calculate_power_injections(Vmag, theta, model.Ybus);
    results_tmp = struct('bus_voltage', Vmag, 'bus_angle_deg', rad2deg(theta), ...
        'Q_generation', Q_final, 'P_generation', P_final);

    if ~converged || ~enforce_q_limits || q_switch_round >= max_q_limit_switches
        break;
    end

    [violated_buses, fixed_Q, limit_type] = pf_find_q_limit_violations(model, results_tmp, q_limit_tolerance);
    if isempty(violated_buses)
        break;
    end

    q_switch_round = q_switch_round + 1;
    working_case = model.case_data;
    working_case.bus_data(:, 3) = Vmag;
    working_case.bus_data(:, 4) = rad2deg(theta);
    for i = 1:numel(violated_buses)
        bus_i = violated_buses(i);
        q_events(end+1, 1) = struct('round', q_switch_round, ...
            'bus_id', model.external_bus_ids(bus_i), ...
            'from_type', 'PV', 'to_type', 'PQ', ...
            'Q_generation_before', Q_final(bus_i), ...
            'Q_fixed', fixed_Q(i), 'limit_type', limit_type{i}); %#ok<AGROW>
        working_case.bus_data(bus_i, 2) = 3;   % PV -> PQ
        working_case.bus_data(bus_i, 6) = fixed_Q(i);
    end
end

% Final results via the shared result builder (same schema as NR).
results = pf_build_results(model, Vmag, theta, mismatch_history, iterations_total, converged, ...
    sprintf('FDPF-%s', variant));
results.q_limit_switching = struct('enabled', enforce_q_limits, 'events', q_events, ...
    'rounds', q_switch_round, 'q_limit_tolerance', q_limit_tolerance);
results.method_variant = variant;
results.metadata.method_requested = variant;
results.metadata.method_executed = variant;
results.metadata.method_source = 'in-house FDPF (Stott-Alsac 1974 + van Amerongen 1989)';
results.metadata.capability = 'production';
results.metadata.fallback_used = false;
results.metadata.full_ac_mismatch = max(abs(full_ac_mismatch(model, Vmag, theta)));
if verbose
    fprintf('FDPF-%s: converged=%d, iterations=%d, max_mismatch=%.3e\n', ...
        variant, converged, iterations_total, results.metadata.full_ac_mismatch);
end
end

% =========================================================================
function [mismatch, P_calc, Q_calc, V, delta] = full_ac_mismatch(model, Vmag, theta)
%FULL_AC_MISMATCH  Recompute the full nonlinear AC mismatch (current V, theta).
%   Uses pf_calculate_power_injections + the project P_net/Q_net convention.
[P_calc, Q_calc] = pf_calculate_power_injections(Vmag, theta, model.Ybus);
mismatch = zeros(model.n_total, 1);
for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    mismatch(i) = model.P_net(bus_i) - P_calc(bus_i);
end
for i = 1:model.n_V
    bus_i = model.V_idx(i);
    mismatch(model.n_delta + i) = model.Q_net(bus_i) - Q_calc(bus_i);
end
V = Vmag; delta = theta;
end
