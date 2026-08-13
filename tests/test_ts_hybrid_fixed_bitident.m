function tests = test_ts_hybrid_fixed_bitident()
%TEST_TS_HYBRID_FIXED_BITIDENT  The adaptive option plumbing must not perturb
% the fixed path. Asserts that a run with NO stepper option is byte-identical
% (AbsTol 0) to a run with stepper='fixed' explicitly set, on the switching
% path (stability.run_hybrid_case -> ts_simulate_ibr_hybrid). This is the
% self-contained half of G-BITID; the cross-commit byte-identity vs the
% pre-adaptive baseline is recorded separately by the worktree A/B.
%
% It also asserts that stepper='fixed' does NOT publish the adaptive-only
% diagnostic fields (dt_history/rejection_history), so a fixed result keeps its
% exact prior schema aside from the additive res.stepper provenance label.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function [scenario,opt] = compressed_arm()
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, T_d_on=0.10, T_d_off=1.0);
scenario = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
opt = struct('dt',0.10,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
opt.t_end = 2.3;   % through fault_clear -> exercises events, fault, subdivision
opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',1,'load_step',1.5,'load_step_factor',0.20, ...
    'fault_on',2,'fault_clear',2.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',2.2,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',2.25,'sg_on',2.25,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
end

function test_default_equals_explicit_fixed(testCase)
[scenario,opt] = compressed_arm();
r_default = stability.run_hybrid_case(scenario,opt);      % no stepper field
opt_fixed = opt; opt_fixed.stepper = 'fixed';
r_fixed   = stability.run_hybrid_case(scenario,opt_fixed);

testCase.verifyEqual(r_fixed.t,        r_default.t,        'AbsTol',0, 't must match');
testCase.verifyEqual(r_fixed.x_traj,   r_default.x_traj,   'AbsTol',0, 'x_traj must match');
testCase.verifyEqual(r_fixed.y_traj,   r_default.y_traj,   'AbsTol',0, 'y_traj must match');
testCase.verifyEqual(r_fixed.u_history,r_default.u_history,'AbsTol',0, 'u_history must match');
testCase.verifyEqual(numel(r_fixed.event_log), numel(r_default.event_log), ...
    'event_log length must match');
for k = 1:numel(r_fixed.event_log)
    testCase.verifyEqual(r_fixed.event_log(k).t,       r_default.event_log(k).t, 'AbsTol',0);
    testCase.verifyEqual(r_fixed.event_log(k).applied, r_default.event_log(k).applied);
    testCase.verifyEqual(char(r_fixed.event_log(k).type), char(r_default.event_log(k).type));
end
testCase.verifyEqual(char(r_fixed.reclose_status), char(r_default.reclose_status));
end

function test_fixed_omits_adaptive_diagnostics(testCase)
[scenario,opt] = compressed_arm();
opt.stepper = 'fixed';
r = stability.run_hybrid_case(scenario,opt);
testCase.verifyEqual(char(r.stepper),'fixed');
testCase.verifyFalse(isfield(r,'dt_history'),      'fixed must not publish dt_history');
testCase.verifyFalse(isfield(r,'rejection_history'),'fixed must not publish rejection_history');
testCase.verifyFalse(isfield(r,'rejected_steps'),  'fixed must not publish rejected_steps');
end

function test_bad_stepper_fails_closed(testCase)
% The driver's PUBLIC contract is STRUCTURED fail-closed, not an uncaught
% throw: ts_simulate_ibr_hybrid wraps initialize() in try/catch (file lines
% 26-38, comment "The public TS contract is structured fail-closed (no
% uncaught exception), but the governing validation identifier must remain
% observable"). run_hybrid_case likewise returns a structured result for every
% option-validation failure (e.g. automaticGfmSwitchingInvalidType). An
% invalid stepper must therefore surface as converged=false carrying the exact
% governing identifier ts_simulate_ibr_hybrid:badStepper -- NOT as a thrown
% MException. (An earlier draft of this test asserted verifyError; that
% contradicted the documented structured-fail-closed contract and was the test
% being wrong, not the code.)
[scenario,opt] = compressed_arm();
opt.stepper = 'magic';
r = stability.run_hybrid_case(scenario,opt);
testCase.verifyFalse(r.converged, 'a bad stepper must fail closed');
testCase.verifyEqual(char(r.failure_id), 'ts_simulate_ibr_hybrid:badStepper', ...
    'the governing validation identifier must remain observable');
testCase.verifyEqual(char(r.metadata.failure), 'ts_simulate_ibr_hybrid:badStepper');
end

function test_nonstepper_adaptive_option_reaches_driver(testCase)
% Regression for the pass-through loop: transposing the row cell array made
% MATLAB execute the loop once with the whole option list in one column, so
% only afield{1} ('stepper') reached the driver. reject_limit=0 is deliberately
% invalid and must therefore be rejected by the driver's existing validator;
% if this option is silently dropped, the run proceeds under the default 10.
[scenario,opt] = compressed_arm();
opt.stepper = 'adaptive';
opt.reject_limit = 0;
r = stability.run_hybrid_case(scenario,opt);
testCase.verifyFalse(r.converged, ...
    'an invalid forwarded adaptive option must fail closed');
testCase.verifyEqual(char(r.failure_id), ...
    'ts_simulate_ibr_hybrid:badAdaptiveOptions', ...
    'reject_limit must reach the hybrid-driver validator');
testCase.verifyEqual(char(r.metadata.failure), ...
    'ts_simulate_ibr_hybrid:badAdaptiveOptions');
end

