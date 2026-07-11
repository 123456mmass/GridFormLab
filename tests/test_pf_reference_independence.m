function tests = test_pf_reference_independence()
%TEST_PF_REFERENCE_INDEPENDENCE  Falsification tests proving that published
%   comparison/reference data NEVER drives the power-flow solution. Only
%   COMPARISON-ONLY fields are corrupted; physical inputs (bus types, V/P
%   setpoints, line params, shunts, taps, phase shifts, base values) are
%   NEVER touched. A deterministic solver with unchanged inputs must return
%   identical results to machine precision (AbsTol 1e-12).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function pf_opt = pf_opts()
    pf_opt = struct('verbose', false, 'plot_results', false, ...
        'enforce_q_limits', false, 'tolerance', 1e-11);
end

function tol = repeat_tol()
    % Deterministic solver + unchanged inputs => results identical to
    % machine precision. Tolerance declared upfront, never relaxed.
    tol = 1e-12;
end

function test_padiyar_printed_data_does_not_drive_pf(testCase)
% Corrupt ALL Padiyar comparison fields (printed_V/angle/Pg/Qg) and the
% Table 9.5 eigenvalue reference; the PF result must be unchanged.
    c = cases.case_padiyar_two_area_4m_avr();
    r1 = pfsolver.powerflow_newton_raphson(c, pf_opts());

    c2 = c;
    c2.operating_point.printed_V        = (0.5:0.1:1.4).';
    c2.operating_point.printed_angle_deg = (-50:5:-5).';
    c2.operating_point.printed_Pg       = rand(10,1) * 10;
    c2.operating_point.printed_Qg       = rand(10,1) * 5;
    c2.reference.table95_eigenvalues    = (101:120).' + 1i*(201:220).';
    r2 = pfsolver.powerflow_newton_raphson(c2, pf_opts());

    assert_pf_identical(testCase, r1, r2, 'Padiyar printed_* corruption');
end

function test_case14_reference_solution_does_not_drive_pf(testCase)
% Case14: corrupt the reference_solution comparison metadata; PF unchanged.
    c = case_ieee14bus();
    r1 = pfsolver.powerflow_newton_raphson(c, pf_opts());

    c2 = c;
    if isfield(c2, 'reference_solution')
        rs = c2.reference_solution;
        fn = fieldnames(rs);
        for k = 1:numel(fn)
            v = rs.(fn{k});
            if isnumeric(v)
                rs.(fn{k}) = rand(size(v)) * 100;
            end
        end
        c2.reference_solution = rs;
    end
    r2 = pfsolver.powerflow_newton_raphson(c2, pf_opts());
    assert_pf_identical(testCase, r1, r2, 'Case14 reference_solution corruption');
end

function test_case14_matpower6_reference_does_not_drive_pf(testCase)
% Same for the MATPOWER6 Case14 loader which stores reference_solution
% from mpc.bus(:,8:9).
    c = cases.case_matpower6_case14();
    r1 = pfsolver.powerflow_newton_raphson(c, pf_opts());

    c2 = c;
    if isfield(c2, 'reference_solution')
        rs = c2.reference_solution;
        fn = fieldnames(rs);
        for k = 1:numel(fn)
            v = rs.(fn{k});
            if isnumeric(v)
                rs.(fn{k}) = rand(size(v)) * 100;
            end
        end
        c2.reference_solution = rs;
    end
    r2 = pfsolver.powerflow_newton_raphson(c2, pf_opts());
    assert_pf_identical(testCase, r1, r2, 'Case14-MATPOWER6 reference corruption');
end

function test_rts24_pgaz_metadata_does_not_drive_pf(testCase)
% RTS-24: corrupt the case_data.pgaz provenance matrices and any reference
% fields; PF unchanged. PGAz data is a DATA SOURCE copy, not a physical input.
    c = cases.case_ieee_rts24_pgaz();
    r1 = pfsolver.powerflow_newton_raphson(c, pf_opts());

    c2 = c;
    if isfield(c2, 'pgaz')
        pg = c2.pgaz;
        fn = fieldnames(pg);
        for k = 1:numel(fn)
            v = pg.(fn{k});
            if isnumeric(v) && ~isscalar(v)
                pg.(fn{k}) = rand(size(v)) * 1000;
            end
        end
        c2.pgaz = pg;
    end
    if isfield(c2, 'reference')
        rf = c2.reference;
        fn = fieldnames(rf);
        for k = 1:numel(fn)
            v = rf.(fn{k});
            if isnumeric(v)
                rf.(fn{k}) = rand(size(v)) * 100;
            end
        end
        c2.reference = rf;
    end
    r2 = pfsolver.powerflow_newton_raphson(c2, pf_opts());
    assert_pf_identical(testCase, r1, r2, 'RTS-24 pgaz/reference corruption');
end

function test_production_pf_dirs_have_no_reference_targets(testCase)
% Recursive guard: the PF SOLVER path (+pfsolver/, internal/, solve_case.m,
% run_powerflow.m, pf_init_paths.m) must not read comparison/reference
% targets (table95_eigenvalues, printed_*, saved PSAT .mat, validation
% artifacts, PGAz results). Comparison data lives in +cases/ manifests by
% design (that is where it is STORED); the guard checks it is not READ on
% the solver path.
    root = fileparts(fileparts(mfilename('fullpath')));
    prod_dirs = { ...
        fullfile(root, '+pfsolver'), ...
        fullfile(root, 'internal'), ...
        fullfile(root, 'solve_case.m'), ...
        fullfile(root, 'run_powerflow.m'), ...
        fullfile(root, 'pf_init_paths.m')};
    forbidden_refs = {'table95_eigenvalues', 'printed_V', 'printed_angle_deg', ...
        'printed_Pg', 'printed_Qg', 'psat_case14_ts_raw.mat', ...
        'rts24_psat_raw.mat', 'psat_kundur6_ts_raw.mat'};
    hits = strings(0,2);
    for d = 1:numel(prod_dirs)
        files = gather_m_files(prod_dirs{d});
        for k = 1:numel(files)
            src = fileread(files{k});
            for q = 1:numel(forbidden_refs)
                if ~isempty(regexp(src, forbidden_refs{q}, 'once'))
                    hits(end+1,:) = {files{k}, forbidden_refs{q}}; %#ok<AGROW>
                end
            end
        end
    end
    if isempty(hits)
        msg = 'PF solver path must not reference comparison/reference targets.';
    else
        lines = cellfun(@(r) sprintf('  %s: %s', char(r{1}), char(r{2})), ...
            num2cell(hits, 2), 'UniformOutput', false);
        msg = sprintf('PF solver path must not reference comparison/reference targets. Hits:\n%s', ...
            strjoin(lines, newline));
    end
    testCase.verifyEmpty(hits, msg);
end

function assert_pf_identical(testCase, r1, r2, label)
% Deterministic-solver identity check. Convergence flag, iterations,
% mismatch history, Ybus, final V/angle, P/Q generation all unchanged.
    tol = repeat_tol();
    testCase.verifyEqual(r2.converged, r1.converged, ...
        sprintf('%s: convergence flag must be unchanged', label));
    testCase.verifyEqual(r2.iterations, r1.iterations, ...
        sprintf('%s: iteration count must be unchanged', label));
    if isfield(r1, 'mismatch_history') && isfield(r2, 'mismatch_history')
        testCase.verifyEqual(r2.mismatch_history, r1.mismatch_history, 'AbsTol', tol, ...
            sprintf('%s: mismatch history must be unchanged', label));
    end
    testCase.verifyEqual(r2.Ybus, r1.Ybus, 'AbsTol', tol, ...
        sprintf('%s: Ybus must be unchanged', label));
    testCase.verifyEqual(r2.bus_voltage, r1.bus_voltage, 'AbsTol', tol, ...
        sprintf('%s: bus voltage must be unchanged', label));
    testCase.verifyEqual(r2.bus_angle_deg, r1.bus_angle_deg, 'AbsTol', tol, ...
        sprintf('%s: bus angle must be unchanged', label));
    testCase.verifyEqual(r2.P_generation, r1.P_generation, 'AbsTol', tol, ...
        sprintf('%s: P generation must be unchanged', label));
    testCase.verifyEqual(r2.Q_generation, r1.Q_generation, 'AbsTol', tol, ...
        sprintf('%s: Q generation must be unchanged', label));
end

function files = gather_m_files(path_entry)
    files = strings(0,1);
    if isfolder(path_entry)
        fl = dir(fullfile(path_entry, '**', '*.m'));
        for k = 1:numel(fl)
            files(end+1,1) = string(fullfile(fl(k).folder, fl(k).name)); %#ok<AGROW>
        end
    elseif exist(path_entry, 'file') == 2
        files = string(path_entry);
    end
end
