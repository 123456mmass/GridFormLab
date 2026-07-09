function tests = test_sauer_pai_inhouse_linearization()
%TEST_SAUER_PAI_INHOUSE_LINEARIZATION Guardrails for in-house Sauer-Pai model plugin.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_inhouse_linearization_is_self_contained(testCase)
    source = fileread(which('stability.sauer_pai_ex83_ssa'));
    testCase.verifyFalse(contains(source, 'sauer_pai_ref_linearization'), ...
        'Sauer-Pai wrapper must use the in-house analytical linearization, not the reference-code port.');
    testCase.verifyTrue(contains(source, 'sauer_pai_ex83_linearization_inhouse'), ...
        'Sauer-Pai wrapper should explicitly call the in-house analytical model plugin.');
end

function test_inhouse_matrix_dimensions_and_all_non_generator_buses(testCase)
    lin = stability.sauer_pai_ex83_linearization_inhouse();
    testCase.verifySize(lin.A, [21 21]);
    testCase.verifySize(lin.blocks.D1, [6 6]);      % 3 machines x (Id,Iq)
    testCase.verifySize(lin.blocks.D4, [6 6]);      % generator bus equations
    testCase.verifySize(lin.blocks.D5, [6 12]);     % 6 non-generator buses, not only 3 loaded buses
    testCase.verifySize(lin.blocks.D6, [12 6]);
    testCase.verifySize(lin.blocks.D7, [12 12]);
end

function test_generic_linearizer_accepts_perturbed_case(testCase)
    c = cases.sauer_pai_ex83_case();
    base = stability.sauer_pai_linearization(c);
    c.H = 1.01 * c.H;
    pert = stability.sauer_pai_linearization(c);
    testCase.verifySize(pert.A, [21 21]);
    testCase.verifyTrue(all(isfinite(pert.A(:))));
    testCase.verifyGreaterThan(norm(pert.A - base.A, 'fro'), 1e-6, ...
        'Perturbing case data should change the generic linearized model.');
end

function test_inhouse_reproduces_corrected_table_8_2(testCase)
    r = stability.sauer_pai_ex83_ssa();
    ref = cases.sauer_pai_reference_catalog().example_8_3_table_8_1.eigenvalues;
    lam = r.eigenvalues;
    used = false(numel(ref), 1);
    maxerr = 0;
    for k = 1:numel(lam)
        dist = abs(lam(k) - ref); dist(used) = inf;
        [~, j] = min(dist); used(j) = true;
        er = abs(real(lam(k))-real(ref(j)));
        ei = abs(imag(lam(k))-imag(ref(j)));
        if abs(real(ref(j))) > 1e-6, er = er/abs(real(ref(j))); end
        if abs(imag(ref(j))) > 1e-6, ei = ei/abs(imag(ref(j))); end
        maxerr = max(maxerr, max(er, ei));
    end
    testCase.verifyLessThan(maxerr, 0.005, 'All Sauer-Pai eigenvalues must be within 0.5%%.');
end
