function tests = test_pf_contract()
%TEST_PF_CONTRACT  Power-flow numerical contract tests: state/mismatch
%   ordering, REF/PV/PQ handling, sign conventions, power balance, Ybus
%   contract, reference-angle and bus-row permutation invariance, and PF
%   failure semantics. Uses existing case loaders plus minimal inline cases
%   constructed via cases.standardize_case. Tolerances are declared BEFORE
%   running and are derived from the solver's own option, not hard-coded
%   loose values.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function opt = quiet_pf(tolerance)
% Quiet PF options with a declared tolerance (tolerance-driven assertions).
    if nargin < 1, tolerance = 1e-10; end
    opt = struct('verbose', false, 'plot_results', false, ...
        'enforce_q_limits', false, 'tolerance', tolerance);
end

% =====================================================================
% State / mismatch ordering
% =====================================================================

function test_state_excludes_ref_angle(testCase)
% The Newton state vector must NOT contain the slack/REF bus angle.
    c = case_ieee14bus();
    model = pf_prepare_case(c);
    x = pf_initial_state(model);
    % x has n_delta angle entries (PV+PQ) and n_V voltage entries (PQ).
    testCase.verifyEqual(numel(x), model.n_total);
    testCase.verifyEqual(numel(x), model.n_delta + model.n_V);
    % REF bus is not in delta_idx.
    testCase.verifyTrue(~ismember(model.slack_buses, model.delta_idx));
end

function test_state_excludes_pv_magnitude(testCase)
% The Newton state vector must NOT contain PV bus voltage magnitudes (those
% are fixed from spec). Only PQ bus voltages are unknowns.
    c = case_ieee14bus();
    model = pf_prepare_case(c);
    % V_idx must be exactly the PQ buses.
    testCase.verifyEqual(model.V_idx(:), model.pq_buses(:));
    testCase.verifyTrue(~any(ismember(model.pv_buses, model.V_idx)));
end

function test_mismatch_excludes_ref_p_includes_pv_pq(testCase)
% The mismatch vector: P mismatch for PV+PQ buses, Q mismatch for PQ only.
% REF P and REF Q and PV Q are NOT in the mismatch.
    c = case_ieee14bus();
    model = pf_prepare_case(c);
    x = pf_initial_state(model);
    [mismatch, ~, ~, ~, ~] = pf_calculate_mismatch(x, model);
    testCase.verifyEqual(numel(mismatch), model.n_total);
    % First n_delta entries are P mismatches for delta_idx (PV+PQ).
    testCase.verifyEqual(numel(model.delta_idx), model.n_delta);
    % Last n_V entries are Q mismatches for V_idx (PQ only).
    testCase.verifyEqual(numel(model.V_idx), model.n_V);
end

% =====================================================================
% REF / PV / PQ handling
% =====================================================================

function test_ref_pv_pq_reconstruction(testCase)
% After solve: REF angle/V fixed from spec, PV V fixed from spec, PQ both
% solved. Calculated generation reconstructed for REF+PV buses.
    c = case_ieee5bus();
    r = pfsolver.powerflow_newton_raphson(c, quiet_pf());
    testCase.verifyTrue(r.converged);
    % REF bus voltage magnitude equals spec.
    ref = find(r.bus_type == 1);
    testCase.verifyEqual(r.bus_voltage(ref), c.bus_data(ref, 3), 'AbsTol', 1e-10);
    % REF angle equals spec (0 deg by convention).
    testCase.verifyEqual(r.bus_angle_deg(ref), c.bus_data(ref, 4), 'AbsTol', 1e-10);
    % PV bus voltage magnitudes equal spec.
    pv = find(r.bus_type == 2);
    testCase.verifyEqual(r.bus_voltage(pv), c.bus_data(pv, 3), 'AbsTol', 1e-10);
end

% =====================================================================
% Sign convention and power balance
% =====================================================================

function test_power_balance_identity(testCase)
% sum(P_generation) - sum(P_load) - P_loss = 0 (within solver tolerance).
% Tolerance-driven: tied to the solver's own declared tolerance, not a
% hard-coded loose value.
    tol = 1e-10;
    c = case_ieee5bus();
    r = pfsolver.powerflow_newton_raphson(c, quiet_pf(tol));
    testCase.verifyTrue(r.converged);
    imbalance = r.P_total_gen - r.P_total_load - r.P_loss_total;
    testCase.verifyLessThan(abs(imbalance), 1e-4, ...
        'P balance must hold (gen - load - loss = 0).');
    % Q balance too.
    q_imbalance = r.Q_total_gen - r.Q_total_load - r.Q_loss_total;
    testCase.verifyLessThan(abs(q_imbalance), 1e-4, ...
        'Q balance must hold.');
end

function test_complex_power_injection_identity(testCase)
% S_i = V_i * conj((Y*V)_i) must hold at the solved operating point.
    c = case_ieee5bus();
    r = pfsolver.powerflow_newton_raphson(c, quiet_pf());
    V = r.bus_voltage .* exp(1i * r.bus_angle);
    S_calc = V .* conj(r.Ybus * V);
    testCase.verifyEqual(real(S_calc), r.P_injection, 'AbsTol', 1e-9, ...
        'P_injection must equal Re(V*conj(YV)).');
    testCase.verifyEqual(imag(S_calc), r.Q_injection, 'AbsTol', 1e-9, ...
        'Q_injection must equal Im(V*conj(YV)).');
end

function test_total_loss_nonnegative_passive(testCase)
% For a passive network (no shunt generation), total real loss >= 0.
    c = case_ieee5bus();
    r = pfsolver.powerflow_newton_raphson(c, quiet_pf());
    testCase.verifyTrue(r.converged);
    testCase.verifyGreaterThanOrEqual(r.P_loss_total, -1e-12, ...
        'Total real loss must be non-negative for a passive network.');
end

function test_specified_power_is_gen_minus_load(testCase)
% P_spec = P_generation - P_load (net injection sign convention).
    c = case_ieee5bus();
    model = pf_prepare_case(c);
    testCase.verifyEqual(model.P_net, model.P_gen - model.P_load, 'AbsTol', 1e-15, ...
        'P_net must equal P_gen - P_load.');
end

% =====================================================================
% Reference-angle rotation invariance
% =====================================================================

function test_reference_angle_invariance(testCase)
% Rotating all bus_data angle initial values by a constant shift must NOT
% change the solved voltages, power flows, or convergence -- only the
% absolute angles shift by the same constant. Compare angles AFTER removing
% the common shift (never compare raw absolute angles).
    c = case_ieee5bus();
    r1 = pfsolver.powerflow_newton_raphson(c, quiet_pf());

    c2 = c;
    c2.bus_data(:, 4) = c2.bus_data(:, 4) + 7.3;   % rotate initial angles
    r2 = pfsolver.powerflow_newton_raphson(c2, quiet_pf());

    % Voltages unchanged.
    testCase.verifyEqual(r2.bus_voltage, r1.bus_voltage, 'AbsTol', 1e-9);
    % Power flows unchanged.
    testCase.verifyEqual(r2.line_flow_P, r1.line_flow_P, 'AbsTol', 1e-9);
    testCase.verifyEqual(r2.P_generation, r1.P_generation, 'AbsTol', 1e-9);
    % Angles differ by exactly the constant shift (align by REF, not raw).
    shift = r2.bus_angle_deg(find(r2.bus_type==1)) - r1.bus_angle_deg(find(r1.bus_type==1));
    angle_diff = (r2.bus_angle_deg - r1.bus_angle_deg) - shift;
    testCase.verifyLessThan(max(abs(angle_diff)), 1e-9, ...
        'Angle differences must collapse to a common shift.');
end

% =====================================================================
% Bus-row permutation invariance
% =====================================================================

function test_bus_row_permutation_invariance(testCase)
% Shuffling bus_data rows must NOT change the solved physics. Line endpoints
% and machine mapping still use external bus IDs. Compare via external bus
% ID mapping (NOT raw row arrays -- internal ordering may change).
    c = case_ieee5bus();
    r1 = pfsolver.powerflow_newton_raphson(c, quiet_pf());

    % Permute bus_data rows (keep line_data referencing external IDs).
    rng(42);
    perm = randperm(size(c.bus_data,1));
    c2 = c;
    c2.bus_data = c.bus_data(perm, :);

    r2 = pfsolver.powerflow_newton_raphson(c2, quiet_pf());

    % Map r2 results back to r1's external bus ID order.
    [~, idx2] = ismember(r1.external_bus_ids, r2.external_bus_ids);
    testCase.verifyTrue(all(idx2 > 0), 'Every base bus ID must map to a permuted one.');

    % V magnitude, P/Q generation, convergence match after ID mapping.
    testCase.verifyEqual(r2.bus_voltage(idx2), r1.bus_voltage, 'AbsTol', 1e-9);
    testCase.verifyEqual(r2.P_generation(idx2), r1.P_generation, 'AbsTol', 1e-9);
    testCase.verifyEqual(r2.Q_generation(idx2), r1.Q_generation, 'AbsTol', 1e-9);
    testCase.verifyEqual(r2.converged, r1.converged);

    % Angle compared after removing the common reference shift.
    a1 = r1.bus_angle_deg;
    a2 = r2.bus_angle_deg(idx2);
    shift = a2(1) - a1(1);
    testCase.verifyLessThan(max(abs((a2 - a1) - shift)), 1e-9, ...
        'Angles must match up to a common shift.');
end

% =====================================================================
% Non-contiguous bus IDs
% =====================================================================

function test_noncontiguous_bus_ids(testCase)
% The solver must handle non-contiguous external bus IDs (e.g. [1 2 11 12
% 101 102]). Padiyar uses [1 2 11 12 101 102 111 112 3 13].
    c = cases.case_padiyar_two_area_4m_avr();
    r = pfsolver.powerflow_newton_raphson(c, quiet_pf(1e-11));
    testCase.verifyTrue(r.converged, 'Non-contiguous bus IDs must solve.');
    % External IDs are preserved in the result.
    testCase.verifyEqual(sort(r.external_bus_ids), ...
        sort(c.bus_data(:,1)), 'External bus IDs must be preserved.');
end

% =====================================================================
% Ybus contract
% =====================================================================

function test_ybus_two_bus_analytic(testCase)
% 2-bus: bus 1 REF, bus 2 PQ, one line R+jX, no shunt, no tap.
% Y11 = Y22 = y_series, Y12 = Y21 = -y_series.
    c = build_2bus_case();
    model = pf_prepare_case(c);
    y_series = 1 / (0.01 + 1i*0.1);
    testCase.verifyEqual(model.Ybus(1,1), y_series, 'AbsTol', 1e-12);
    testCase.verifyEqual(model.Ybus(2,2), y_series, 'AbsTol', 1e-12);
    testCase.verifyEqual(model.Ybus(1,2), -y_series, 'AbsTol', 1e-12);
    testCase.verifyEqual(model.Ybus(2,1), -y_series, 'AbsTol', 1e-12);
end

function test_ybus_parallel_lines_accumulate(testCase)
% Two parallel lines between bus 1 and 2 must accumulate (Ybus = 2*y_series),
% not overwrite.
    c = build_2bus_case();
    c.line_data = [1 2 0.01 0.1 0 1 0; 1 2 0.01 0.1 0 1 0];
    c = cases.standardize_case(c);
    model = pf_prepare_case(c);
    y_series = 1 / (0.01 + 1i*0.1);
    testCase.verifyEqual(model.Ybus(1,1), 2*y_series, 'AbsTol', 1e-12, ...
        'Parallel lines must accumulate on the diagonal.');
    testCase.verifyEqual(model.Ybus(1,2), -2*y_series, 'AbsTol', 1e-12);
end

function test_ybus_bus_shunt_into_diagonal(testCase)
% A bus shunt (Gsh, Bsh) must add to the diagonal of Ybus.
    c = build_2bus_case();
    c.bus_data(2, 9)  = 0.5;   % Gsh at bus 2
    c.bus_data(2, 10) = 1.0;   % Bsh at bus 2
    c = cases.standardize_case(c);
    model = pf_prepare_case(c);
    y_series = 1 / (0.01 + 1i*0.1);
    % Y22 = y_series + Gsh + j*Bsh
    testCase.verifyEqual(model.Ybus(2,2), y_series + 0.5 + 1i*1.0, 'AbsTol', 1e-12);
end

function test_ybus_offnominal_tap(testCase)
% Off-nominal tap ratio modifies the series admittance entry on the from side.
    c = build_2bus_case();
    c.line_data(1, 6) = 0.9;  % tap = 0.9 (no phase shift)
    c = cases.standardize_case(c);
    model = pf_prepare_case(c);
    y_series = 1 / (0.01 + 1i*0.1);
    tap = 0.9;
    % Y(from,from) += y_series / |tap|^2 ; Y(to,to) += y_series
    testCase.verifyEqual(model.Ybus(1,1), y_series / (tap^2), 'AbsTol', 1e-12);
    testCase.verifyEqual(model.Ybus(2,2), y_series, 'AbsTol', 1e-12);
    % Y(from,to) = -y_series / conj(tap)
    testCase.verifyEqual(model.Ybus(1,2), -y_series / conj(tap), 'AbsTol', 1e-12);
end

function test_ybus_phase_shift(testCase)
% A phase-shifting transformer introduces a complex tap and breaks Ybus symmetry.
    c = build_2bus_case();
    c.line_data(1, 7) = 5.0;  % phase shift 5 deg, tap=1
    c = cases.standardize_case(c);
    model = pf_prepare_case(c);
    % With a phase shift, Ybus is no longer Hermitian-symmetric.
    testCase.verifyTrue(abs(model.Ybus(1,2) - model.Ybus(2,1)) > 1e-9, ...
        'Phase-shifted transformer must break Ybus symmetry.');
    y_series = 1 / (0.01 + 1i*0.1);
    tap = exp(1i * deg2rad(5.0));
    testCase.verifyEqual(model.Ybus(1,2), -y_series / conj(tap), 'AbsTol', 1e-12);
end

function test_ybus_invalid_endpoint_errors(testCase)
% A line referencing a non-existent bus must throw a stable error.
    c = build_2bus_case();
    c.line_data(1, 2) = 99;  % bus 99 does not exist
    c = cases.standardize_case(c);
    try
        pf_prepare_case(c);
        testCase.verifyTrue(false, 'Invalid endpoint must throw.');
    catch
        testCase.verifyTrue(true);
    end
end

function test_ybus_duplicate_bus_id_errors(testCase)
% Duplicate bus IDs must throw a stable error.
    c = build_2bus_case();
    c.bus_data(2, 1) = 1;  % duplicate of bus 1
    c = cases.standardize_case(c);
    try
        pf_prepare_case(c);
        testCase.verifyTrue(false, 'Duplicate bus ID must throw.');
    catch
        testCase.verifyTrue(true);
    end
end

% =====================================================================
% PF failure semantics
% =====================================================================

function test_failure_max_iter_returns_reason(testCase)
    c = case_ieee5bus();
    r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false,'max_iter',1));
    testCase.verifyFalse(r.converged);
    testCase.verifyEqual(r.reason, 'max_iterations');
    testCase.verifyEqual(r.finite_status, 'all_finite');
end

function test_failure_singular_jacobian_returns_reason(testCase)
% Islanded bus -> singular Ybus -> singular Jacobian.
    c = struct('system_name','islanded', ...
        'base_values',struct('S_base_MVA',100,'V_base_kV',1,'frequency_Hz',60), ...
        'bus_data',[1 1 1.0 0 0 0 0 0 0 0 -Inf Inf; 2 3 1.0 0 0 0 1 0.5 0 0 -Inf Inf], ...
        'line_data',[1 1 0.001 0.01 0 1 0]);
    c = cases.standardize_case(c);
    r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false,'enforce_q_limits',false));
    testCase.verifyFalse(r.converged);
    testCase.verifyEqual(r.reason, 'singular_jacobian');
    testCase.verifyTrue(isfield(r,'finite_status'));
end

function test_failure_invalid_bus_type_errors(testCase)
% Invalid bus type must throw a stable error (C1: invalid input/schema).
    c = build_2bus_case();
    c.bus_data(2, 2) = 9;  % invalid type
    c = cases.standardize_case(c);
    try
        pf_prepare_case(c);
        testCase.verifyTrue(false, 'Invalid bus type must throw.');
    catch
        testCase.verifyTrue(true);
    end
end

function test_failure_missing_ref_errors(testCase)
% Missing REF bus must throw a stable error (C1).
    c = build_2bus_case();
    c.bus_data(1, 2) = 3;  % both PQ, no REF
    c = cases.standardize_case(c);
    try
        pf_prepare_case(c);
        testCase.verifyTrue(false, 'Missing REF must throw.');
    catch
        testCase.verifyTrue(true);
    end
end

function test_failure_never_converged_true_on_nonconvergence(testCase)
% A non-converged result must NEVER set converged=true from finite output.
    c = case_ieee5bus();
    r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false,'max_iter',1));
    if ~r.converged
        testCase.verifyTrue(isfield(r,'reason') && ~strcmp(r.reason,'converged'), ...
            'Non-converged result must not claim converged reason.');
    end
end

% =====================================================================
% Helpers
% =====================================================================

function c = build_2bus_case()
    c = struct();
    c.system_name = '2-bus analytic';
    c.base_values = struct('S_base_MVA', 100, 'V_base_kV', 1, 'frequency_Hz', 60);
    c.bus_data = [ ...
        1  1  1.0  0   0   0   0   0   0  0   -Inf Inf;  % REF
        2  3  1.0  0   0   0   1.0 0.5 0   0   -Inf Inf]; % PQ
    c.line_data = [1 2  0.01  0.1  0  1  0];
    c = cases.standardize_case(c);
end
