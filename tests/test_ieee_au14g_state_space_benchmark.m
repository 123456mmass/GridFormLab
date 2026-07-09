function tests = test_ieee_au14g_state_space_benchmark()
%TEST_IEEE_AU14G_STATE_SPACE_BENCHMARK External IEEE/PES 14-generator benchmark.
% Uses published MATLAB state-space and eigenvalue files from the IEEE PES
% benchmark system archive. This validates the common engine eigen pipeline
% on a large published multimachine state-space model. It is not counted as
% an in-house model-linearizer accuracy test because the A matrix is supplied
% by the benchmark archive.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_case1_pss_off_state_space_eigenvalues(testCase)
    root = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'docs', 'benchmark_sources', 'ieee_au14g', 'extracted', 'AU14GenModel_StateSpaceAndEigen_Matlab_Ver04');
    Afile = fullfile(root, 'Case1_PSSs_Off_ABCD_Rev3_Matlab.mat');
    Efile = fullfile(root, 'Case1_PSSs_Off_Eigs_Rev3_Matlab.mat');
    testCase.assumeTrue(isfile(Afile) && isfile(Efile), ...
        'IEEE AU14G benchmark files are not present in docs/benchmark_sources.');
    Adata = load(Afile, 'AA');
    Edata = load(Efile, 'E');
    A = Adata.AA;
    ref = Edata.E;

    model = struct();
    nx = size(A,1);
    model.x0 = zeros(nx,1);
    model.y0 = 0;
    model.f = @(x,y) A*x;
    model.g = @(x,y) 0;
    model.Jxx = A;
    model.Jxy = zeros(nx,1);
    model.Jyx = zeros(1,nx);
    model.Jyy = 1;
    model.free_y = 1;
    model.reduction = 'none';
    model.metadata = struct('engine','stability.multimachine_ssa', ...
        'benchmark','IEEE PES AU14G Case1 PSSs Off published state-space');
    r = stability.multimachine_ssa(model);

    testCase.verifyEqual(numel(r.eigenvalues), numel(ref));
    testCase.verifyLessThan(maxNearestAbsError(r.eigenvalues, ref), 1e-7, ...
        'Engine eigenvalues should match the IEEE published state-space eigenvalues to numerical precision.');
end

function e = maxNearestAbsError(lam, ref)
    used = false(numel(ref),1);
    e = 0;
    for k = 1:numel(lam)
        d = abs(lam(k)-ref); d(used) = inf;
        [mn,j] = min(d); used(j) = true;
        e = max(e, mn);
    end
end
