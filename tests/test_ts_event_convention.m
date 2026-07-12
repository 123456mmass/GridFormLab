function tests = test_ts_event_convention()
%TEST_TS_EVENT_CONVENTION  Event public-sample convention (plan §6).
tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end
function test_event_left_right_diagnostics(testCase)
% At t_fault and t_clear, event_diagnostics must record both left and right
% topology/residual evidence.
c = cases.case_padiyar_two_area_4m_avr();
r = stability.ts_simulate(c, struct('model','padiyar_1_1_avr','stepper','adaptive', ...
    't_end',3,'dt',0.01,'fault_bus',3,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'excitation','avr','verbose',false));
testCase.verifyGreaterThan(numel(r.event_diagnostics), 0);
sides = {r.event_diagnostics.side};
testCase.verifyTrue(any(strcmp(sides,'left')), 'left-limit recorded');
testCase.verifyTrue(any(strcmp(sides,'right')), 'right-limit recorded');
end
function test_no_cross_topology_residual(testCase)
% The fault-bus voltage at t_fault must reflect the right-limit (faulted)
% topology, not the pre-fault topology (no trapezoidal step averaging across
% the event).
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',3,'dt',0.01, ...
    'fault_bus',1,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
tf = find(abs(r.t - 1.0) < 1e-14, 1);
% Right-limit (faulted) voltage must be below pre-fault.
testCase.verifyLessThan(r.Vbus(tf,1), r.Vbus(tf-1,1)*0.95, ...
    'Fault-bus Vbus at t_fault must reflect faulted (right-limit) topology.');
end
function test_x_continuous_at_event(testCase)
% x (delta) is continuous across the event: the value just before and at the
% event must match (no state jump).
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',3,'dt',0.01, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
tf = find(abs(r.t - 1.0) < 1e-14, 1);
testCase.verifyLessThan(max(abs(r.delta(tf,:) - r.delta(tf-1,:))), 1e-6, ...
    'delta continuous across t_fault.');
end
