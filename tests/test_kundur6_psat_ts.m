function tests = test_kundur6_psat_ts()
%TEST_KUNDUR6_PSAT_TS Guardrail for 6th-order Kundur TS vs PSAT.
%   Uses the PSAT TD result saved by run_psat_kundur_ts. Skips if the PSAT
%   raw data is absent (PSAT not installed / not run).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    projroot = fileparts(fileparts(mfilename('fullpath')));
    addpath(projroot);
    pf_init_paths();
end

function test_6th_order_matches_psat_coi(testCase)
    projroot = fileparts(fileparts(mfilename('fullpath')));
    raw = fullfile(projroot,'docs','source','figures','kundur_ex126','psat_kundur6_ts_raw.mat');
    if ~exist(raw,'file')
        testCase.assumeTrue(false,'PSAT Kundur6 raw data not present; skipping.');
        return;
    end
    S = load(raw); ps = S.ps_save;
    % Our 6th-order with the same scenario + load model as PSAT (pq2z => cz).
    opt = struct('model','genpj6','t_end',min(ps.td_tend,6),'dt',1e-3,'fault_bus',8, ...
        't_fault',1.0,'t_clear',1.05,'Zf',[],'method','trapezoidal','corrector_iter',1, ...
        'load_model','cz','verbose',false);
    r = stability.ts_simulate(cases.case_kundur_two_area_classical(), opt);
    [~,oo] = sort(r.gen_buses);
    do = rad2deg(r.delta(:,oo)); wo = r.omega(:,oo);
    H = r.H_machine(:).';
    tg = r.t;
    dps = rad2deg(interp1(ps.t, ps.delta, tg)); wps = interp1(ps.t, ps.omega, tg);
    [~,o] = sort(ps.delta_bus); dps = dps(:,o); wps = wps(:,o);
    % COI frame (PSAT fixes slack angle; ours floats -> compare relative).
    drel_p = dps - sum(H.*dps,2)/sum(H); drel_o = do - sum(H.*do,2)/sum(H);
    wrel_p = wps - mean(wps,2); wrel_o = wo - mean(wo,2);
    testCase.verifyLessThan(max(abs(drel_p-drel_o),[],'all'), 5, ...
        '6th-order COI rotor angle vs PSAT should agree within 5 deg.');
    testCase.verifyLessThan(max(abs(wrel_p-wrel_o),[],'all'), 1e-3, ...
        '6th-order COI speed vs PSAT should agree within 1e-3 pu.');
end
