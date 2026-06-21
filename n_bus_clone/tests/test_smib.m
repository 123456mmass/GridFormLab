function tests = test_smib()
%TEST_SMIB Unit tests for SMIB small-signal stability analysis.
%   Validates the classical (Model A, Kundur Example 12.2) and field-circuit
%   (Model B, Kundur Example 12.3) models against the textbook golden values.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% ===================== Model A - classical (Ex 12.2) =====================

function test_classical_operating_point(testCase)
    c = cases.case_kundur_smib_classical();
    op = smib.smib_classical_init(c.machine, c.network, c.operating);
    g = c.reference_solution;
    testCase.verifyEqual(op.delta0_deg, g.delta0_deg, 'RelTol', 0.01, ...
        'delta0 should match Kundur Ex 12.2');
    testCase.verifyEqual(op.Ep_mag, g.Ep_mag, 'RelTol', 0.01, '|E''| mismatch');
    testCase.verifyEqual(op.XT, g.XT, 'RelTol', 1e-3, 'XT mismatch');
    testCase.verifyEqual(op.Ks, g.Ks, 'RelTol', 0.01, 'Ks mismatch');
end

function test_classical_eigenvalues(testCase)
    c = cases.case_kundur_smib_classical();
    op = smib.smib_classical_init(c.machine, c.network, c.operating);
    w0 = 2 * pi * c.base_values.frequency_Hz;
    g = c.reference_solution;

    % KD = 0: undamped, eigenvalues +-j*wn
    sysA0 = smib.smib_build_state_matrix('A', ...
        struct('H', c.machine.H, 'KD', 0, 'Ks', op.Ks, 'w0', w0));
    r0 = smib.smib_analyze(sysA0);
    testCase.verifyEqual(max(r0.freq_Hz), g.fn_Hz, 'RelTol', 0.01, ...
        'Natural frequency (KD=0) mismatch');
    testCase.verifyLessThan(abs(max(real(r0.eigenvalues))), 1e-6, ...
        'KD=0 eigenvalues should be purely imaginary');

    % KD = 10: stable, zeta ~ 0.112
    sysA10 = smib.smib_build_state_matrix('A', ...
        struct('H', c.machine.H, 'KD', 10, 'Ks', op.Ks, 'w0', w0));
    r10 = smib.smib_analyze(sysA10);
    testCase.verifyTrue(r10.is_stable, 'KD=10 system should be stable');
    testCase.verifyEqual(max(r10.damping), g.zeta_KD10, 'RelTol', 0.02, ...
        'Damping ratio (KD=10) mismatch');

    % KD = -10: unstable (negative damping)
    sysAn10 = smib.smib_build_state_matrix('A', ...
        struct('H', c.machine.H, 'KD', -10, 'Ks', op.Ks, 'w0', w0));
    rn10 = smib.smib_analyze(sysAn10);
    testCase.verifyFalse(rn10.is_stable, 'KD=-10 system should be unstable');
end

% =================== Model B - field circuit (Ex 12.3) ===================

function test_detailed_operating_point(testCase)
    c = cases.case_kundur_smib_detailed();
    op = smib.smib_dq_init(c.machine, c.network, c.operating);
    g = c.reference_solution;
    testCase.verifyEqual(op.Ksd, g.Ksd_total, 'RelTol', 0.01, 'Ksd mismatch');
    testCase.verifyEqual(op.delta_i_deg, g.delta_i_deg, 'RelTol', 0.01, 'delta_i mismatch');
    testCase.verifyEqual(op.id0, g.id0, 'RelTol', 0.01, 'id0 mismatch');
    testCase.verifyEqual(op.iq0, g.iq0, 'RelTol', 0.01, 'iq0 mismatch');
    testCase.verifyEqual(op.delta0_deg, g.delta0_deg, 'RelTol', 0.01, 'delta0 mismatch');
    testCase.verifyEqual(op.Efd0, g.Efd0, 'RelTol', 0.01, 'Efd0 mismatch');
end

function test_detailed_k_constants(testCase)
    c = cases.case_kundur_smib_detailed();
    op = smib.smib_dq_init(c.machine, c.network, c.operating);
    w0 = 2 * pi * c.base_values.frequency_Hz;
    K = smib.smib_k_constants(c.machine, c.network, op, w0);
    g = c.reference_solution;
    testCase.verifyEqual(K.m1, g.m1, 'RelTol', 0.01, 'm1 mismatch');
    testCase.verifyEqual(K.n1, g.n1, 'RelTol', 0.01, 'n1 mismatch');
    testCase.verifyEqual(K.m2, g.m2, 'RelTol', 0.01, 'm2 mismatch');
    testCase.verifyEqual(K.K1, g.K1, 'RelTol', 0.01, 'K1 mismatch');
    testCase.verifyEqual(K.K2, g.K2, 'RelTol', 0.01, 'K2 mismatch');
    testCase.verifyEqual(K.K4, g.K4, 'RelTol', 0.01, 'K4 mismatch');
    testCase.verifyEqual(K.T3, g.T3, 'RelTol', 0.02, 'T3 mismatch');
end

function test_detailed_eigenvalues(testCase)
    c = cases.case_kundur_smib_detailed();
    op = smib.smib_dq_init(c.machine, c.network, c.operating);
    w0 = 2 * pi * c.base_values.frequency_Hz;
    K = smib.smib_k_constants(c.machine, c.network, op, w0);
    g = c.reference_solution;

    sysB = smib.smib_build_state_matrix('B', struct( ...
        'H', c.machine.H, 'KD', c.machine.KD, 'w0', w0, ...
        'K1', K.K1, 'K2', K.K2, 'a32', K.a32, 'a33', K.a33, 'b3', K.b3));
    r = smib.smib_analyze(sysB);

    % Identify the oscillatory (swing) mode
    osc = r.eigenvalues(abs(imag(r.eigenvalues)) > 1e-3);
    testCase.verifyNotEmpty(osc, 'Expected an oscillatory mode');
    lam = osc(imag(osc) > 0);

    testCase.verifyEqual(real(lam(1)), real(g.eig_osc(1)), 'AbsTol', 0.02, ...
        'Swing mode real part mismatch');
    testCase.verifyEqual(imag(lam(1)), imag(g.eig_osc(1)), 'AbsTol', 0.05, ...
        'Swing mode imaginary part mismatch');

    % Non-oscillatory field mode near -0.204
    realmode = r.eigenvalues(abs(imag(r.eigenvalues)) <= 1e-3);
    testCase.verifyEqual(min(real(realmode)), g.eig_real, 'AbsTol', 0.02, ...
        'Field (non-oscillatory) mode mismatch');

    testCase.verifyTrue(r.is_stable, 'Detailed model should be stable (KD=0, AVR off)');
end

% ===================== Model C - exciter/AVR (Table 12.1) ================

function test_avr_torque_components(testCase)
    c = cases.case_kundur_smib_avr();
    g = c.reference_solution;
    H = c.machine.H; w0 = 2 * pi * c.base_values.frequency_Hz;
    for i = 1:numel(g.KA_list)
        ex = struct('KA', g.KA_list(i), 'TR', c.exciter.TR);
        td = smib.smib_torque_components(c.k_constants, ex, H, w0, g.omega_eval);
        testCase.verifyEqual(td.Ks_dpsifd, g.Ks_dpsifd_list(i), 'AbsTol', 0.005, ...
            sprintf('Ks(dpsifd) mismatch at KA=%d', g.KA_list(i)));
        testCase.verifyEqual(td.KD_dpsifd, g.KD_dpsifd_list(i), 'AbsTol', 0.02, ...
            sprintf('KD(dpsifd) mismatch at KA=%d', g.KA_list(i)));
    end
end

function test_avr_high_gain_unstable(testCase)
    % Example 12.6 condition: AVR only (KA=200, K5<0) drives the swing
    % mode unstable.
    c = cases.case_kundur_smib_pss();
    H = c.machine.H; w0 = 2 * pi * c.base_values.frequency_Hz;
    K = c.k_constants; ex = c.exciter;
    sysC = smib.smib_build_state_matrix('C', struct('H', H, 'KD', c.machine.KD, ...
        'w0', w0, 'K1', K.K1, 'K2', K.K2, 'K3', K.K3, 'K4', K.K4, ...
        'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA));
    r = smib.smib_analyze(sysC);
    testCase.verifyFalse(r.is_stable, 'AVR-only (KA=200, K5<0) should be unstable');
    osc = r.eigenvalues(imag(r.eigenvalues) > 1e-3);
    g = c.reference_solution;
    testCase.verifyEqual(real(osc(1)), real(g.avr_only_eig_osc(1)), 'AbsTol', 0.02);
    testCase.verifyEqual(imag(osc(1)), imag(g.avr_only_eig_osc(1)), 'AbsTol', 0.05);
end

% ===================== Model D - AVR + PSS (Ex 12.6) =====================

function test_pss_stabilizes(testCase)
    c = cases.case_kundur_smib_pss();
    H = c.machine.H; w0 = 2 * pi * c.base_values.frequency_Hz;
    K = c.k_constants; ex = c.exciter; pss = c.pss;
    g = c.reference_solution;

    sysD = smib.smib_build_state_matrix('D', struct('H', H, 'KD', c.machine.KD, ...
        'w0', w0, 'K1', K.K1, 'K2', K.K2, 'K3', K.K3, 'K4', K.K4, ...
        'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA, ...
        'KSTAB', pss.KSTAB, 'Tw', pss.Tw, 'T1', pss.T1, 'T2', pss.T2));
    r = smib.smib_analyze(sysD);

    testCase.verifyTrue(r.is_stable, 'PSS should stabilize the system');

    % Swing mode near -1.005 +- j6.607, zeta ~ 0.15
    osc = r.eigenvalues(imag(r.eigenvalues) > 1e-3);
    [~, idx] = min(abs(imag(osc) - 6.607));
    swing = osc(idx);
    testCase.verifyEqual(real(swing), real(g.pss_eig_swing(1)), 'AbsTol', 0.05, ...
        'Swing-mode real part mismatch');
    testCase.verifyEqual(imag(swing), imag(g.pss_eig_swing(1)), 'AbsTol', 0.1, ...
        'Swing-mode frequency mismatch');
    sw_zeta = -real(swing) / abs(swing);
    testCase.verifyEqual(sw_zeta, g.pss_swing_zeta, 'AbsTol', 0.02, ...
        'Swing-mode damping ratio mismatch');
end

