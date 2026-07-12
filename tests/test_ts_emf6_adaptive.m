function tests = test_ts_emf6_adaptive()
%TEST_TS_EMF6_ADAPTIVE  EMF6 adaptive-step (variable dt) TS gate tests.
%   Phase 5: the EMF6 model wired through ts_adaptive_driver must complete a
%   fault scenario with finite bounded trajectory, exact event landing, and the
%   frozen adaptive result schema. Kundur 12.6 vs PSAT stays within 5 deg / 1e-3
%   (fresh, if PSAT raw data is available).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function r = run_emf6_adaptive(t_end, varargin)
c = cases.case_kundur_two_area_classical();
opt = struct('model','emf6','stepper','adaptive', ...
    't_end',t_end,'dt',1e-3,'fault_bus',8,'t_fault',1.0,'t_clear',1.05, ...
    'Zf',[],'load_model','cz','verbose',false);
if nargin >= 2
    fn = fieldnames(varargin{1});
    for k = 1:numel(fn), opt.(fn{k}) = varargin{1}.(fn{k}); end
end
r = stability.ts_simulate(c, opt);
end

function test_adaptive_completes_and_schema(testCase)
r = run_emf6_adaptive(3);
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
testCase.verifyGreaterThan(r.accepted_steps, 0);
testCase.verifyEqual(numel(r.dt_history), numel(r.t)-1);
testCase.verifyEqual(numel(r.lte_history), numel(r.t)-1);
testCase.verifyTrue(all(diff(r.t) > 0), 'strictly increasing r.t');
testCase.verifyEqual(numel(r.t), r.accepted_steps + 1);
testCase.verifyEqual(r.dt, 1e-3, 'r.dt is scalar nominal');
testCase.verifyEqual(r.dt_nominal, 1e-3);
testCase.verifyEqual(r.model, 'emf6');
testCase.verifyEqual(r.engine, 'stability.synchronous_emf6_ssa');
end

function test_adaptive_exact_event_landing(testCase)
r = run_emf6_adaptive(3);
testCase.verifyEqual(min(abs(r.t - 1.0)), 0, 'AbsTol', 1e-14, 't_fault on grid');
testCase.verifyEqual(min(abs(r.t - 1.05)), 0, 'AbsTol', 1e-14, 't_clear on grid');
testCase.verifyGreaterThan(numel(r.event_diagnostics), 0);
end

function test_adaptive_no_fault_drift(testCase)
r = run_emf6_adaptive(2, struct('t_fault',99,'t_clear',99.1,'fault_enabled',false));
testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:))), 1e-6, ...
    'No-fault delta drift < 1e-6 rad');
testCase.verifyLessThan(max(abs(r.omega(:))), 1e-6, 'No-fault omega drift');
end

function test_adaptive_fault_depresses_voltage(testCase)
r = run_emf6_adaptive(3);
fb = find(r.bus_ids == 8, 1);
tf = find(abs(r.t - 1.0) < 1e-14, 1);
testCase.verifyLessThan(r.Vbus(tf,fb), r.Vbus(tf-1,fb)*0.95, ...
    'Fault-bus voltage must drop at fault application.');
end

function test_adaptive_matches_psat_within_tolerance(testCase)
% Fresh EMF6 adaptive vs PSAT (if raw data present; else skip).
projroot = fileparts(fileparts(mfilename('fullpath')));
raw = fullfile(projroot,'docs','source','figures','kundur_ex126','psat_kundur6_ts_raw.mat');
if ~exist(raw,'file')
    testCase.assumeTrue(false,'PSAT Kundur6 raw data not present; skipping.');
    return;
end
S = load(raw); ps = S.ps_save;
r = run_emf6_adaptive(min(ps.td_tend,6));
[~,oo] = sort(r.gen_buses);
do = rad2deg(r.delta(:,oo)); wo = r.omega(:,oo);
H = r.H(:).'; tg = r.t;
dps = rad2deg(interp1(ps.t, ps.delta, tg, 'linear'));
wps = interp1(ps.t, ps.omega, tg, 'linear');
[~,o] = sort(ps.delta_bus); dps = dps(:,o); wps = wps(:,o);
drel_p = dps - sum(H.*dps,2)/sum(H); drel_o = do - sum(H.*do,2)/sum(H);
wrel_p = wps - mean(wps,2); wrel_o = wo - mean(wo,2);
testCase.verifyLessThan(max(abs(drel_p-drel_o),[],'all'), 5, ...
    'EMF6 adaptive COI rotor angle vs PSAT should agree within 5 deg.');
testCase.verifyLessThan(max(abs(wrel_p-wrel_o),[],'all'), 1e-3, ...
    'EMF6 adaptive COI speed vs PSAT should agree within 1e-3 pu.');
end
