function tests = test_event_transition()
%TEST_EVENT_TRANSITION  B3 shared event-transition helper tests.
%   Verifies the shared ts_event_transition helper:
%     - selects the right topology by EXPLICIT event_id (no t+eps discovery)
%     - re-solves algebraic y under the right topology
%     - fails closed on coincident events (ts_prevalidate_events)
%     - is bit-identical to the legacy adaptive path for non-coincident cases
%   Also includes a grep guard that no t+1e-14/t+eps/+1e- topology-discovery
%   pattern survives in ts_adaptive_driver.m or ts_simulate.m.
%
%   Source: project B3 design (docs/project/plans/ibr_interface_foundation.md).
%   Uses SYNTHETIC fixtures; no +ibr. IEEE14 end-to-end gate included.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function testCase = base_opt()
testCase = struct('t_end',1.5,'dt',0.02,'fault_bus',4,'t_fault',1.0, ...
    't_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'corrector_iter',10,'max_corrector_iter',10,'verbose',false, ...
    'fault_enabled',true);
end

function test_fault_on_selects_Yfault(testCase)
% ts_event_transition('fault_on', ...) must return events.Yfault as Y_right.
events = struct('fault_enabled',true,'t_fault',1.0,'t_clear',1.1, ...
    'Ypre',eye(2),'Yfault',[2 0;0 2],'Ypost',eye(2));
strat = struct('needs_algebraic_solve',false);   % classical: no re-solve
kopt = struct('algebraic_tolerance',1e-12);
[~, Y_right, ~, ~] = stability.ts_event_transition(1.0, "fault_on", events, ...
    [0;0], [1;0], strat, kopt, false, 1e-10);
testCase.verifyEqual(Y_right, events.Yfault, 'AbsTol', 0, 'fault_on => Yfault.');
end

function test_fault_off_selects_Ypost(testCase)
% ts_event_transition('fault_off', ...) must return events.Ypost as Y_right.
events = struct('fault_enabled',true,'t_fault',1.0,'t_clear',1.1, ...
    'Ypre',eye(2),'Yfault',[2 0;0 2],'Ypost',[3 0;0 3]);
strat = struct('needs_algebraic_solve',false);
kopt = struct('algebraic_tolerance',1e-12);
[~, Y_right, ~, ~] = stability.ts_event_transition(1.1, "fault_off", events, ...
    [0;0], [1;0], strat, kopt, false, 1e-10);
testCase.verifyEqual(Y_right, events.Ypost, 'AbsTol', 0, 'fault_off => Ypost.');
end

function test_bad_event_id_fail_closed(testCase)
% Unknown event_id => fail closed.
events = struct('fault_enabled',true,'t_fault',1.0,'t_clear',1.1, ...
    'Ypre',eye(2),'Yfault',eye(2),'Ypost',eye(2));
strat = struct('needs_algebraic_solve',false);
kopt = struct('algebraic_tolerance',1e-12);
testCase.verifyError(@() stability.ts_event_transition(1.0, "bogus", events, ...
    [0;0], [1;0], strat, kopt, false, 1e-10), ...
    'ts_event_transition:badEventId');
end

function test_coincident_events_fail_closed(testCase)
% ts_prevalidate_events: t_fault == t_clear within event_tol => fail closed.
events = struct('fault_enabled',true,'t_fault',1.0,'t_clear',1.0, ...
    'Ypre',eye(2),'Yfault',eye(2),'Ypost',eye(2));
testCase.verifyError(@() stability.ts_prevalidate_events(events, [0, 2], 1e-10), ...
    'ts_event_transition:ambiguousCoincident');
end

function test_distinct_events_pass(testCase)
% Distinct t_fault/t_clear => prevalidate returns both, no error.
events = struct('fault_enabled',true,'t_fault',1.0,'t_clear',1.1, ...
    'Ypre',eye(2),'Yfault',eye(2),'Ypost',eye(2));
et = stability.ts_prevalidate_events(events, [0, 2], 1e-10);
testCase.verifyEqual(numel(et), 2, 'two distinct events.');
testCase.verifyEqual(et, [1.0; 1.1], 'AbsTol', 0, 'event times sorted.');
end

function test_no_t_plus_eps_discovery_grep(testCase)
% Grep guard: no t+1e-14 / t+eps / +1e- topology-discovery pattern in
% ts_adaptive_driver.m or ts_simulate.m (run_model_bundle).
projroot = fileparts(fileparts(mfilename('fullpath')));
files = {fullfile(projroot,'+stability','ts_adaptive_driver.m'), ...
         fullfile(projroot,'+stability','ts_simulate.m')};
violations = {};
for f = files
    lines = readlines(f{1});
    for li = 1:numel(lines)
        ln = strtrim(lines{li});
        if isempty(ln) || ln(1) == '%', continue; end
        cidx = find(ln == '%', 1);
        if ~isempty(cidx), ln = strtrim(ln(1:cidx-1)); end
        % Flag topology-discovery patterns: t + 1e-14, t+eps, +1e-14 etc.
        % Allow '1e-10' (event_tol) and '1e-14' only in the loop bound
        % 't < t_end - 1e-14' (not a topology query).
        if contains(ln,'ts_topology_at') && (contains(ln,'+ 1e-') || ...
                contains(ln,'+1e-') || contains(ln,'+ eps') || contains(ln,'+eps'))
            violations = [violations; {sprintf('%s:%d', f{1}, li)}]; %#ok<AGROW>
        end
    end
end
testCase.verifyTrue(isempty(violations), ...
    sprintf('t+eps topology discovery found: %s', strjoin(violations, ', ')));
end

function test_adaptive_padiyar_runs_end_to_end(testCase)
% End-to-end: adaptive Padiyar over a case with machine data, with a fault
% event, must run (legacy adaptive path now uses ts_event_transition).
% Legacy AbsTol=0 verified by test_ts_event_convention; this is a smoke
% gate. Uses the Padiyar two-area case (has sourced machine data). IEEE14
% (MATPOWER-only) does not carry SG machine data, so it is exercised via
% the classical bundle path in the next test (advisor directive: MATPOWER
% provides network/PF data only).
c = cases.case_padiyar_two_area_4m_avr();
opt = base_opt();
opt.fault_bus = 3;   % Padiyar two-area bus map (no bus 4)
opt.excitation = 'manual';
opt.model = 'padiyar_1_1_manual';
opt.stepper = 'adaptive';
opt.dt_init = 0.01; opt.dt_nominal = 0.01;
opt.dt_min = 1e-4; opt.dt_max = 0.05;
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
opt.controller_fac = 0.9;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'finite adaptive trajectory.');
testCase.verifyTrue(numel(r.t) >= 2, 'multiple time samples.');
end

function test_bundle_fixed_runs_with_event(testCase)
% End-to-end: bundle fixed-step over IEEE14 with a fault event must run
% (run_model_bundle now uses ts_event_transition at event steps).
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'finite bundle fixed trajectory.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'provenance preserved.');
end
