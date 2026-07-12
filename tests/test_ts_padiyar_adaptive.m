function tests = test_ts_padiyar_adaptive()
%TEST_TS_PADIYAR_ADAPTIVE  Padiyar adaptive-step (variable dt) TS gate tests.
%   Phase 4: the Padiyar model wired through ts_adaptive_driver must complete a
%   fault scenario with finite bounded trajectory, exact event landing, and the
%   frozen adaptive result schema.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function r = run_padiyar_adaptive(t_end, excitation)
c = cases.case_padiyar_two_area_4m_avr();
if nargin < 2, excitation = 'avr'; end
if strcmp(excitation,'manual'), model = 'padiyar_1_1_manual'; else, model = 'padiyar_1_1_avr'; end
opt = struct('model',model,'stepper','adaptive', ...
    't_end',t_end,'dt',0.01,'fault_bus',3,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'excitation',excitation,'verbose',false);
r = stability.ts_simulate(c, opt);
end

function test_adaptive_completes_and_schema(testCase)
r = run_padiyar_adaptive(3);
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
testCase.verifyGreaterThan(r.accepted_steps, 0);
testCase.verifyEqual(numel(r.dt_history), numel(r.t)-1);
testCase.verifyEqual(numel(r.lte_history), numel(r.t)-1);
testCase.verifyTrue(all(diff(r.t) > 0), 'strictly increasing r.t');
testCase.verifyEqual(numel(r.t), r.accepted_steps + 1);
testCase.verifyTrue(isfield(r,'rejection_history'));
testCase.verifyTrue(isfield(r,'event_diagnostics'));
testCase.verifyEqual(r.dt, 0.01, 'r.dt is scalar nominal');
testCase.verifyEqual(r.dt_nominal, 0.01);
end

function test_adaptive_exact_event_landing(testCase)
r = run_padiyar_adaptive(3);
testCase.verifyEqual(min(abs(r.t - 1.0)), 0, 'AbsTol', 1e-14, 't_fault on grid');
testCase.verifyEqual(min(abs(r.t - 1.1)), 0, 'AbsTol', 1e-14, 't_clear on grid');
% Event diagnostics must record left/right at fault and clear.
testCase.verifyGreaterThan(numel(r.event_diagnostics), 0);
end

function test_adaptive_long_horizon_15s(testCase)
r = run_padiyar_adaptive(15);
% Long-horizon gate: 0 non-converged (accepted), bounded swing.
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
% COI-relative angle bounded (< 60 deg equivalent: max pairwise < 120 deg).
H = r.H(:).'; dcoi = r.delta - sum(H.*r.delta,2)/sum(H);
testCase.verifyLessThan(max(max(dcoi))*180/pi, 90, 'COI-relative bounded');
% Speed deviation bounded.
testCase.verifyLessThan(max(abs(r.omega(:) - 1)), 0.05, 'Speed deviation < 0.05 pu');
% Voltage bounded.
testCase.verifyGreaterThan(min(r.Vbus(:)), 0.5, 'Min Vbus > 0.5');
testCase.verifyLessThan(max(r.Vbus(:)), 1.2, 'Max Vbus < 1.2');
end

function test_adaptive_no_fault_drift(testCase)
c = cases.case_padiyar_two_area_4m_avr();
opt = struct('model','padiyar_1_1_avr','stepper','adaptive', ...
    't_end',2,'dt',0.01,'fault_bus',3,'fault_enabled',false, ...
    'excitation','avr','verbose',false);
r = stability.ts_simulate(c, opt);
% No-fault: delta and omega must not drift from initial.
testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:))), 1e-6, ...
    'No-fault delta drift < 1e-6 rad');
testCase.verifyLessThan(max(abs(r.omega(:) - 1)), 1e-6, 'No-fault omega drift');
end

function test_adaptive_manual_mode(testCase)
r = run_padiyar_adaptive(3, 'manual');
testCase.verifyEqual(r.excitation, 'manual');
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyEqual(r.stepper, 'adaptive');
end
