function tests = test_multimachine_machine_count_ladder()
%TEST_MULTIMACHINE_MACHINE_COUNT_LADDER Validate common engine over 2..6 machines.
% Published references cover 3-machine Sauer-Pai and 4-machine Kundur.
% Synthetic equilibrium cases cover 2, 5, and 6 machines as scalability and
% generalization guardrails for the same Sauer-Pai-family model plugin.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_two_machine_synthetic_case(testCase)
    verifySyntheticMachineCount(testCase, 2);
end

function test_three_machine_published_sauer_pai(testCase)
    r = stability.sauer_pai_ex83_ssa();
    testCase.verifyEqual(r.metadata.engine, 'stability.multimachine_ssa');
    testCase.verifyEqual(numel(r.eigenvalues), 21);
    ref = cases.sauer_pai_reference_catalog().example_8_3_table_8_1.eigenvalues;
    testCase.verifyLessThan(maxNearestEigenError(r.eigenvalues, ref), 0.005);
end

function test_four_machine_kundur_emf6(testCase)
    % Four-machine Kundur 12.6 via the operational EMF6 model (single
    % equation set shared with TS).
    r = stability.synchronous_emf6_ssa(cases.kundur_ex126_book_case(), ...
        struct('load_model','cc_p_cz_q'));
    testCase.verifyEqual(r.metadata.engine, 'stability.multimachine_ssa');
    testCase.verifyEqual(numel(r.eigenvalues),24);
    testCase.verifyLessThan(r.newton_residual,1e-8);
    testCase.verifyTrue(all(isfinite(r.eigenvalues)));
end

function test_five_machine_synthetic_case(testCase)
    verifySyntheticMachineCount(testCase, 5);
end

function test_six_machine_synthetic_case(testCase)
    verifySyntheticMachineCount(testCase, 6);
end

function verifySyntheticMachineCount(testCase, ng)
    c = cases.synthetic_sauer_pai_case(ng);
    lin = stability.sauer_pai_linearization(c);
    ns = 7;
    testCase.verifySize(lin.A, [ng*ns ng*ns]);
    testCase.verifyTrue(all(isfinite(lin.A(:))), 'A matrix must be finite.');
    model = struct();
    model.x0 = lin.x0;
    model.y0 = 0;
    model.f = @(x,y) zeros(ng*ns,1);
    model.g = @(x,y) 0;
    model.Jxx = lin.A;
    model.Jxy = zeros(ng*ns,1);
    model.Jyx = zeros(1,ng*ns);
    model.Jyy = 1;
    model.free_y = 1;
    model.reduction = 'coi';
    model.ng = ng;
    model.states_per_machine = ns;
    model.angle_state_index = 1;
    model.speed_state_index = 2;
    model.inertia = c.H;
    model.metadata = struct('engine','stability.multimachine_ssa', 'jacobian','analytical', 'benchmark','synthetic');
    r = stability.multimachine_ssa(model);
    testCase.verifyEqual(r.metadata.engine, 'stability.multimachine_ssa');
    testCase.verifyEqual(numel(r.eigenvalues), ng*ns);
    testCase.verifyTrue(all(isfinite(r.eigenvalues)), 'Eigenvalues must be finite.');
end

function maxerr = maxNearestEigenError(lam, ref)
    used = false(numel(ref),1);
    maxerr = 0;
    for k = 1:numel(lam)
        dist = abs(lam(k)-ref); dist(used)=inf; [~,j]=min(dist); used(j)=true;
        er = abs(real(lam(k))-real(ref(j))); ei = abs(imag(lam(k))-imag(ref(j)));
        if abs(real(ref(j))) > 1e-6, er = er/abs(real(ref(j))); end
        if abs(imag(ref(j))) > 1e-6, ei = ei/abs(imag(ref(j))); end
        maxerr = max(maxerr, max(er,ei));
    end
end
