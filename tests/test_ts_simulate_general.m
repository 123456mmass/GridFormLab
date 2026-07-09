function tests = test_ts_simulate_general()
%TEST_TS_SIMULATE_GENERAL Guardrail for the general classical TS engine.
%   Verifies that stability.ts_simulate runs ANY case in +cases/ (MATPOWER or
%   Kundur format) with no engine edit, and that case14 reproduces the
%   validated case14_ts_classical result (independently cross-checked vs PSAT).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_kundur_6th_order_via_general_engine(testCase)
    % The validated 6th-order model (<0.5% vs Kundur Table E12.3) must run
    % through the SAME engine entry point as classical, via opt.model.
    opt = struct('model','genpj6','t_end',3,'dt',1e-3,'fault_bus',8, ...
        't_fault',0.5,'t_clear',0.6,'Zf',[],'method','trapezoidal', ...
        'corrector_iter',1,'verbose',false);
    r = stability.ts_simulate(cases.case_kundur_two_area_classical(), opt);
    testCase.verifyEqual(r.model, '6th-order GENTPJ full nonlinear');
    testCase.verifyEqual(numel(r.gen_buses), 4);
    % Must reproduce the validated standalone 6th-order simulator exactly.
    r0 = stability.kundur_fault_simulation_6th_order(struct('bus',8,'tclear',0.1, ...
        'tmax',3,'dt',1e-3,'tfault_start',0.5,'method','trapezoidal','corrector_iter',1));
    testCase.verifyLessThan(max(abs(rad2deg(r.delta-r0.delta)),[],'all'), 1e-6);
    % Operating point (q-axis rotor angles) must match the validated SSSA init.
    testCase.verifyLessThan(max(abs(rad2deg(r.delta(1,:)) - [63.304 52.480 37.331 26.201])), 1e-2);
end

function test_case14_matches_validated_engine(testCase)
    opt = struct('t_end',4,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',1i*0.1,'pm_mode','pgaz','verbose',false);
    r_gen = stability.ts_simulate(cases.case_matpower6_case14(), opt);
    r_old = stability.case14_ts_classical(opt);
    testCase.verifyTrue(r_gen.pf.converged);
    % General engine must reproduce the validated classical engine exactly.
    testCase.verifyLessThan(max(abs(rad2deg(r_gen.delta - r_old.delta)),[],'all'), 1e-6);
end

function test_case9_new_case_runs(testCase)
    % A case never used to build the engine: proves "add a case and it runs".
    opt = struct('t_end',4,'dt',0.01,'fault_bus',7,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',1i*0.1,'pm_mode','pfpg','verbose',false);
    r = stability.ts_simulate(cases.case_matpower6_case9(), opt);
    testCase.verifyTrue(r.pf.converged);
    testCase.verifyEqual(numel(r.gen_buses), 3);
    % Stable: bounded inter-machine angles, speed returns near nominal.
    H = r.H(:).'; dcoi = sum(H.*r.delta,2)/sum(H); drel = r.delta - dcoi;
    testCase.verifyLessThan(max((max(drel)-min(drel))*180/pi), 360);
    testCase.verifyLessThan(max(abs(r.omega(end,:)-1)), 0.1);
end

function test_kundur_runs_with_base_conversion(testCase)
    opt = struct('t_end',4,'dt',0.01,'fault_bus',8,'t_fault',0.5,'t_clear',0.6, ...
        'Zf',1i*0.1,'pm_mode','pfpg','verbose',false);
    r = stability.ts_simulate(cases.case_kundur_two_area_classical(), opt);
    testCase.verifyTrue(r.pf.converged);
    testCase.verifyEqual(numel(r.gen_buses), 4);
    % Machine base 900 MVA -> system 100 MVA: H_sys = H_mach*9, Xdp_sys = 0.3/9.
    testCase.verifyEqual(r.H, [58.5; 58.5; 55.575; 55.575], 'AbsTol', 1e-3);
    testCase.verifyLessThan(max(abs(r.Xdp - 0.3/9)), 1e-6);
    % Pe0 must match the Kundur operating point (system pu).
    testCase.verifyLessThan(max(abs(r.Pe_pu(1,:) - [7.0 7.0 7.2 7.0])), 0.05);
    % Stable.
    H = r.H(:).'; dcoi = sum(H.*r.delta,2)/sum(H); drel = r.delta - dcoi;
    testCase.verifyLessThan(max((max(drel)-min(drel))*180/pi), 360);
end
