function tests = test_sauer_pai_ex83_reproduction()
%TEST_SAUER_PAI_EX83_REPRODUCTION Sauer-Pai Example 8.3 eigenvalue reproduction.
% Validates that the common multimachine_ssa engine, fed with analytical
% Jacobians for the Sauer-Pai WSCC 3-machine 9-bus system, reproduces
% Table 8.2 eigenvalues within 0.5% tolerance.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_sauer_pai_uses_common_engine(testCase)
    r = stability.sauer_pai_ex83_ssa();
    testCase.verifyEqual(r.metadata.engine, 'stability.multimachine_ssa');
    testCase.verifyEqual(r.metadata.jacobian, 'analytical');
    testCase.verifyEqual(numel(r.eigenvalues), 21, ...
        'Sauer-Pai full system should be 3 machines x 7 states');
end

function test_sauer_pai_all_modes_within_0_5_percent(testCase)
    r = stability.sauer_pai_ex83_ssa();
    lam = r.eigenvalues;
    ref = cases.sauer_pai_reference_catalog().example_8_3_table_8_1.eigenvalues;

    % Match computed to reference by nearest eigenvalue.
    used = false(numel(ref), 1);
    for k = 1:numel(lam)
        % Find nearest unused reference eigenvalue.
        dist = abs(lam(k) - ref);
        dist(used) = inf;
        [~, j] = min(dist);
        used(j) = true;

        % Compare real and imaginary parts.
        if abs(real(ref(j))) > 1e-6
            err_real = abs(real(lam(k)) - real(ref(j))) / abs(real(ref(j)));
        else
            err_real = abs(real(lam(k)) - real(ref(j)));
        end
        if abs(imag(ref(j))) > 1e-6
            err_imag = abs(imag(lam(k)) - imag(ref(j))) / abs(imag(ref(j)));
        else
            err_imag = abs(imag(lam(k)) - imag(ref(j)));
        end

        testCase.verifyLessThan(err_real, 0.005, ...
            sprintf('Eigenvalue %d (ref %.4f%+.4fj): real error %.3f%% exceeds 0.5%%', ...
                k, real(ref(j)), imag(ref(j)), err_real*100));
        testCase.verifyLessThan(err_imag, 0.005, ...
            sprintf('Eigenvalue %d (ref %.4f%+.4fj): imag error %.3f%% exceeds 0.5%%', ...
                k, real(ref(j)), imag(ref(j)), err_imag*100));
    end
end

function test_sauer_pai_damping_ratios(testCase)
    r = stability.sauer_pai_ex83_ssa();
    lam = r.eigenvalues;
    ref = cases.sauer_pai_reference_catalog().example_8_3_table_8_1.eigenvalues;

    % Check damping ratios of oscillatory modes.
    ref_osc = ref(abs(imag(ref)) > 0.1 & imag(ref) > 0);
    lam_osc = lam(abs(imag(lam)) > 0.1 & imag(lam) > 0);

    testCase.verifyEqual(numel(lam_osc), numel(ref_osc), ...
        'Should have same number of oscillatory modes');

    % Match by nearest frequency.
    used = false(numel(ref_osc), 1);
    for k = 1:numel(lam_osc)
        dist = abs(abs(imag(lam_osc(k))) - abs(imag(ref_osc)));
        dist(used) = inf;
        [~, j] = min(dist);
        used(j) = true;

        zeta_c = -real(lam_osc(k)) / abs(lam_osc(k));
        zeta_r = -real(ref_osc(j)) / abs(ref_osc(j));
        err = abs(zeta_c - zeta_r) / zeta_r;
        testCase.verifyLessThan(err, 0.005, ...
            sprintf('Mode f=%.3f Hz: damping ratio error %.3f%% exceeds 0.5%%', ...
                abs(imag(ref_osc(j)))/(2*pi), err*100));
    end
end
