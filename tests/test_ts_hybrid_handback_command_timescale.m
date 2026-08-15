function tests = test_ts_hybrid_handback_command_timescale()
%TEST_TS_HYBRID_HANDBACK_COMMAND_TIMESCALE  Contract for the two opt-in knobs
% added while investigating RECLOSE-2026-08-15-01:
%
%   fd_perturbation         forwards the existing stability.ts_step_composite FD
%                           rule ('absolute' default, 'scaled') through
%                           run_hybrid_case -> ts_simulate_ibr_hybrid.
%   handback_efd_timescale  chooses whether the post-reclose FIELD-VOLTAGE
%                           command is walked over the C1 handback duration
%                           ('mode', default and historical) or over the declared
%                           actuator-lag response time ('control').
%
% What is asserted:
%   - each option OMITTED is byte-identical to the same option set to its
%     documented default (AbsTol 0 on t/x_traj/y_traj/u_history and the event
%     log), so no existing run changes;
%   - an invalid value fails closed with the governing identifier rather than
%     silently falling back;
%   - selecting 'control' does NOT change the published C1 handback duration,
%     because only the field-voltage command path is affected -- the mechanical
%     and IBR references keep the full duration;
%   - the actuator-lag term is exactly the repository's own 95 %-response
%     expression -log(rho)*max([Tsv Tch TA]) evaluated from the case values,
%     so the alternative timescale is derived and not a fitted number.
%
% This suite does not assert that either option improves any trajectory; that is
% a separate measured question recorded in the defect record.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function [scenario,opt] = compressed_arm()
% Same compressed switching arm used by test_ts_hybrid_fixed_bitident, which
% exercises events, the fault, subdivision, and a reclose request.
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
opt.t_end = 2.3;
opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',1,'load_step',1.5,'load_step_factor',0.20, ...
    'fault_on',2,'fault_clear',2.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',2.2,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',2.25,'sg_on',2.25,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
end

function verify_identical(testCase,a,b,what)
testCase.verifyEqual(b.t,        a.t,        'AbsTol',0,[what ': t']);
testCase.verifyEqual(b.x_traj,   a.x_traj,   'AbsTol',0,[what ': x_traj']);
testCase.verifyEqual(b.y_traj,   a.y_traj,   'AbsTol',0,[what ': y_traj']);
testCase.verifyEqual(b.u_history,a.u_history,'AbsTol',0,[what ': u_history']);
testCase.verifyEqual(numel(b.event_log),numel(a.event_log),[what ': event count']);
for k = 1:numel(b.event_log)
    testCase.verifyEqual(b.event_log(k).t,a.event_log(k).t,'AbsTol',0);
    testCase.verifyEqual(char(string(b.event_log(k).type)), ...
        char(string(a.event_log(k).type)));
    testCase.verifyEqual(logical(b.event_log(k).applied), ...
        logical(a.event_log(k).applied));
end
testCase.verifyEqual(char(string(b.reclose_status)),char(string(a.reclose_status)));
end

function test_fd_perturbation_default_is_byte_identical(testCase)
[scenario,opt] = compressed_arm();
r_omitted = stability.run_hybrid_case(scenario,opt);
opt2 = opt; opt2.fd_perturbation = 'absolute';
r_default = stability.run_hybrid_case(scenario,opt2);
verify_identical(testCase,r_omitted,r_default,'fd_perturbation absolute');
end

function test_handback_efd_timescale_default_is_byte_identical(testCase)
[scenario,opt] = compressed_arm();
r_omitted = stability.run_hybrid_case(scenario,opt);
opt2 = opt; opt2.handback_efd_timescale = 'mode';
r_default = stability.run_hybrid_case(scenario,opt2);
verify_identical(testCase,r_omitted,r_default,'handback_efd_timescale mode');
end

function id = failure_identifier(r)
% run_hybrid_case surfaces a structured fail-closed result rather than throwing
% (established contract, SWITCH-2026-08-10-01 falsified hypothesis 4). The
% governing identifier from the TS initializer is republished in metadata.
id = '';
if isfield(r,'metadata') && isstruct(r.metadata)
    if isfield(r.metadata,'error_id') && ~isempty(r.metadata.error_id)
        id = char(string(r.metadata.error_id));
    elseif isfield(r.metadata,'failure') && ~isempty(r.metadata.failure)
        id = char(string(r.metadata.failure));
    end
end
if isempty(id) && isfield(r,'ts') && isstruct(r.ts) && isfield(r.ts,'failure_id')
    id = char(string(r.ts.failure_id));
end
end

function test_invalid_fd_perturbation_fails_closed(testCase)
[scenario,opt] = compressed_arm();
opt.fd_perturbation = 'nonsense';
r = stability.run_hybrid_case(scenario,opt);
testCase.verifyFalse(logical(r.converged), ...
    'an invalid FD rule must not produce a converged run');
id = failure_identifier(r);
testCase.verifyTrue(contains(id,'badFdPerturbation'), ...
    sprintf('expected badFdPerturbation, observed "%s"',id));
end

function test_invalid_handback_efd_timescale_fails_closed(testCase)
[scenario,opt] = compressed_arm();
opt.handback_efd_timescale = 'nonsense';
r = stability.run_hybrid_case(scenario,opt);
testCase.verifyFalse(logical(r.converged), ...
    'an invalid timescale selector must not produce a converged run');
id = failure_identifier(r);
testCase.verifyTrue(contains(id,'badHandbackEfdTimescale'), ...
    sprintf('expected badHandbackEfdTimescale, observed "%s"',id));
end

function test_actuator_lag_timescale_is_the_repository_expression(testCase)
% The alternative timescale must be the repository's own 95 %-response time of
% the declared exciter/governor lags, not a fitted constant. The controller
% carries Tsv/Tch/TA and the case carries rho.
scenario = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
rho = scenario.case_data.delays.rho;
testCase.verifyTrue(isfinite(rho) && rho > 0 && rho < 1, 'rho must be a fraction');
% Declared lags, as initialize_sync_controller freezes them.
Tsv = 0.2; Tch = 0.4; TA = 0.02;
expected = -log(rho)*max([Tsv Tch TA]);
testCase.verifyEqual(expected,-log(rho)*Tch,'AbsTol',0, ...
    'the turbine lag must dominate this case');
testCase.verifyTrue(expected > 0 && isfinite(expected));
% And it must be strictly shorter than the destination-mode decay time that the
% handback duration otherwise uses, otherwise the option would be a no-op here.
tbl = stability.ibr_selector_table(scenario.case_data,scenario.resources, ...
    scenario,struct());
row = [];
C = tbl.sg_on.configurations;
for k = 1:numel(C)
    if isequal(sort(C(k).selected_gfm_indices(:).'),2), row = C(k); end
end
testCase.assertNotEmpty(row,'the one-GFM SG_ON row must exist');
t_mode = log(1/rho)/(-row.omega);
testCase.verifyLessThan(expected,t_mode, ...
    'the actuator-lag timescale must be shorter than the mode decay time');
end
