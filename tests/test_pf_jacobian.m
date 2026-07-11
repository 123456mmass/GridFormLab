function tests = test_pf_jacobian()
%TEST_PF_JACOBIAN  Analytic-vs-finite-difference cross-check of the Newton
%   power-flow Jacobian. The FD reference is built from the mismatch residual
%   (pf_calculate_mismatch), which is an INDEPENDENT implementation from the
%   analytic Jacobian (pf_build_jacobian). No call to pf_build_jacobian is
%   made inside the FD reference.
%
%   Sign convention (declared upfront): mismatch = P_spec - P_calc, so
%       d(mismatch)/dx = -d(P_calc)/dx = -J_analytic
%   Hence  J_analytic = -J_fd(mismatch).
%
%   Tolerances are declared BEFORE running. The h-sweep reports per-block
%   metrics for every h; acceptance is enforced only at h=1e-5 (optimal for
%   central differences: truncation O(h^2) ~ 1e-10, roundoff O(eps/h) ~ 1e-11).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% --- Predeclared tolerances (declared BEFORE running, not tuned after) ---
% MAX_ABS_DIFF_TOL  max |J_analytic - J_fd| per block at h=1e-5
% REL_FROB_TOL      relative Frobenius diff at h=1e-5
% H_VALUES          FD steps swept (report all, accept only at ACCEPT_H)
% ACCEPT_H          acceptance step (optimal central-FD step)

function test_jacobian_5bus_analytic_fd_agree(testCase)
    c = case_ieee5bus();
    [pass, report] = check_jacobian_fd(testCase, c, 'IEEE 5-bus');
    testCase.verifyTrue(pass, report);
end

function test_jacobian_case14_analytic_fd_agree(testCase)
    c = case_ieee14bus();
    [pass, report] = check_jacobian_fd(testCase, c, 'IEEE Case14');
    testCase.verifyTrue(pass, report);
end

function test_jacobian_padiyar_analytic_fd_agree(testCase)
    % Padiyar two-area has non-contiguous external bus IDs
    % [1 2 11 12 101 102 111 112 3 13] -- exercises external-ID mapping.
    c = cases.case_padiyar_two_area_4m_avr();
    [pass, report] = check_jacobian_fd(testCase, c, 'Padiyar two-area');
    testCase.verifyTrue(pass, report);
end

function test_jacobian_dimensions_match(testCase)
    c = case_ieee14bus();
    model = pf_prepare_case(c);
    x = pf_initial_state(model);
    [~, P_calc, Q_calc, V, delta] = pf_calculate_mismatch(x, model);
    J = pf_build_jacobian(V, delta, P_calc, Q_calc, model);
    testCase.verifyEqual(size(J), [model.n_total, model.n_total], ...
        'Jacobian must be square n_total x n_total');
    testCase.verifyEqual(size(J, 1), model.n_delta + model.n_V, ...
        'Jacobian rows must equal n_delta + n_V');
end

function test_jacobian_2bus_flat_start_fd_agree(testCase)
    % Minimal 2-bus hand-checkable case: bus 1 = REF, bus 2 = PQ, one line.
    c = build_2bus_case();
    [pass, report] = check_jacobian_fd(testCase, c, '2-bus analytic');
    testCase.verifyTrue(pass, report);
end

function [pass, report] = check_jacobian_fd(testCase, c, label)
% Evaluate the analytic Jacobian at a non-trivial operating point and
% compare against a central-FD reference of the mismatch residual.
    MAX_ABS_DIFF_TOL = 1e-6;
    REL_FROB_TOL     = 1e-6;
    H_VALUES         = [1e-4, 1e-5, 1e-6, 1e-7];
    ACCEPT_H         = 1e-5;

    model = pf_prepare_case(c);
    x = pf_initial_state(model);

    % Advance a few NR iterations so the Jacobian is evaluated at a
    % realistic (non-flat-start) operating point.
    for it = 1:3
        [mismatch, P_calc, Q_calc, V, delta] = pf_calculate_mismatch(x, model);
        if max(abs(mismatch), [], 'all') < 1e-12
            break;
        end
        J = pf_build_jacobian(V, delta, P_calc, Q_calc, model);
        x = x + (J \ mismatch);
        for i = 1:model.n_V
            pos = model.n_delta + i;
            if x(pos) <= 0, x(pos) = 0.1; end
        end
    end

    [~, P_calc, Q_calc, V, delta] = pf_calculate_mismatch(x, model);
    J_analytic = pf_build_jacobian(V, delta, P_calc, Q_calc, model);

    testCase.verifyTrue(all(isfinite(J_analytic(:))), ...
        sprintf('%s: analytic Jacobian must be finite at operating point', label));

    nd = model.n_delta;
    report = sprintf('%s Jacobian FD cross-check:\n', label);
    pass = true;

    for hi = 1:numel(H_VALUES)
        h = H_VALUES(hi);
        J_fd = compute_fd_jacobian(x, model, h);
        J_fd = -J_fd;  % d(mismatch)/dx = -J_analytic

        H_diff = max(abs(J_analytic(1:nd, 1:nd)       - J_fd(1:nd, 1:nd)),       [], 'all');
        N_diff = max(abs(J_analytic(1:nd, nd+1:end)   - J_fd(1:nd, nd+1:end)),   [], 'all');
        M_diff = max(abs(J_analytic(nd+1:end, 1:nd)   - J_fd(nd+1:end, 1:nd)),   [], 'all');
        L_diff = max(abs(J_analytic(nd+1:end, nd+1:end) - J_fd(nd+1:end, nd+1:end)), [], 'all');
        max_abs = max([H_diff, N_diff, M_diff, L_diff]);
        rel_frob = norm(J_analytic(:) - J_fd(:)) / max(norm(J_analytic(:)), 1);
        all_finite = all(isfinite(J_fd(:)));

        report = sprintf('%s  h=%.0e  H=%.2e N=%.2e M=%.2e L=%.2e  max_abs=%.2e  rel_frob=%.2e  finite=%d\n', ...
            report, h, H_diff, N_diff, M_diff, L_diff, max_abs, rel_frob, all_finite);

        if h == ACCEPT_H
            if max_abs >= MAX_ABS_DIFF_TOL, pass = false; end
            if rel_frob >= REL_FROB_TOL, pass = false; end
            if ~all_finite, pass = false; end
            testCase.verifyLessThan(max_abs, MAX_ABS_DIFF_TOL, ...
                sprintf('%s: per-block max abs diff at h=%g', label, h));
            testCase.verifyLessThan(rel_frob, REL_FROB_TOL, ...
                sprintf('%s: relative Frobenius diff at h=%g', label, h));
            testCase.verifyTrue(all_finite, sprintf('%s: FD Jacobian finite', label));
        end
    end
end

function J_fd = compute_fd_jacobian(x, model, h)
% Central finite-difference Jacobian of the mismatch residual.
% Does NOT call pf_build_jacobian. Perturbs each state component by +/-h
% (absolute step) and differences the mismatch residual.
    n = model.n_total;
    J_fd = zeros(n, n);
    x0 = x(:);
    for k = 1:n
        xp = x0; xm = x0;
        xp(k) = xp(k) + h;
        xm(k) = xm(k) - h;
        mp = pf_calculate_mismatch(xp, model);
        mm = pf_calculate_mismatch(xm, model);
        J_fd(:, k) = (mp - mm) / (2 * h);
    end
end

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
