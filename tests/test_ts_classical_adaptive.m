function tests = test_ts_classical_adaptive()
%TEST_TS_CLASSICAL_ADAPTIVE  Classical adaptive-step (variable dt) TS gate tests.
%   Phase 6: the classical model wired through ts_adaptive_driver must complete
%   a fault scenario with finite bounded trajectory, exact event landing, and the
%   frozen adaptive result schema. Fixed-vs-adaptive common-grid equivalence is
%   within pre-declared tolerances.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function r = run_classical_adaptive(t_end, overrides)
c = cases.case_matpower6_case14();
opt = struct('stepper','adaptive','t_end',t_end,'dt',0.01, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'pm_mode','pgaz','corrector_mode','adaptive','verbose',false);
if nargin >= 2
    fn = fieldnames(overrides);
    for k = 1:numel(fn), opt.(fn{k}) = overrides.(fn{k}); end
end
r = stability.ts_simulate(c, opt);
end

function test_adaptive_completes_and_schema(testCase)
r = run_classical_adaptive(5);
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyEqual(r.model, 'classical');
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
testCase.verifyGreaterThan(r.accepted_steps, 0);
testCase.verifyEqual(numel(r.dt_history), numel(r.t)-1);
testCase.verifyEqual(numel(r.lte_history), numel(r.t)-1);
testCase.verifyTrue(all(diff(r.t) > 0), 'strictly increasing r.t');
testCase.verifyEqual(numel(r.t), r.accepted_steps + 1);
testCase.verifyEqual(r.dt, 0.01, 'r.dt is scalar nominal');
end

function test_adaptive_exact_event_landing(testCase)
r = run_classical_adaptive(5);
testCase.verifyEqual(min(abs(r.t - 1.0)), 0, 'AbsTol', 1e-14, 't_fault on grid');
testCase.verifyEqual(min(abs(r.t - 1.1)), 0, 'AbsTol', 1e-14, 't_clear on grid');
testCase.verifyGreaterThan(numel(r.event_diagnostics), 0);
end

function test_adaptive_no_fault_drift(testCase)
r = run_classical_adaptive(3, struct('t_fault',99,'t_clear',99.1,'fault_enabled',false));
testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:))), 1e-6, ...
    'No-fault delta drift < 1e-6 rad');
testCase.verifyLessThan(max(abs(r.omega(:) - 1)), 1e-6, 'No-fault omega drift');
end

function test_adaptive_fault_depresses_voltage(testCase)
% Use a fault on a generator bus (bus 1) so the Vbus drop is directly
% observable on a gen-bus column, avoiding the fault_bus-not-a-gen-bus filter.
r = run_classical_adaptive(5, struct('fault_bus',1));
tf = find(abs(r.t - 1.0) < 1e-14, 1);
% Classical result does not carry bus_ids; the fault bus is column 1 by
% construction (gbus(1)). Verify gen-bus-1 voltage drops at the fault.
testCase.verifyLessThan(r.Vbus(tf,1), r.Vbus(tf-1,1)*0.95, ...
    'Fault-bus voltage must drop at fault application.');
end

function test_fixed_vs_adaptive_common_grid(testCase)
% Phase 6: fixed-vs-adaptive common-grid equivalence for Case14 classical.
% Interpolate the adaptive raw trajectory onto the fixed canonical grid using
% interp_no_extrapolate (per-event-segment, no cross-event, no extrapolation).
% Tolerance rationale (declared a priori, NOT borrowed from PSAT): the fixed
% path uses exact ci=10 Picard iterations while the adaptive path uses a
% residual-checked corrector that may converge in fewer iterations; the
% resulting trajectory difference is bounded by the corrector tolerance, not
% by the LTE budget. Pre-declared: COI angle < 1.0 deg, speed < 1e-3 pu.
c = cases.case_matpower6_case14();
opt_fixed = struct('t_end',5,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','fixed','corrector_iter',10,'verbose',false);
r_fixed = stability.ts_simulate(c, opt_fixed);
r_adapt = run_classical_adaptive(5);
tg = r_fixed.t;
% Segment by event: interpolate each segment separately (no cross-event).
seg_edges = [0; 1.0; 1.1; 5];
delta_f_interp = zeros(numel(tg), numel(r_fixed.delta(1,:)));
delta_a_interp = zeros(numel(tg), numel(r_adapt.delta(1,:)));
omega_f_interp = zeros(numel(tg), numel(r_fixed.omega(1,:)));
omega_a_interp = zeros(numel(tg), numel(r_adapt.omega(1,:)));
for s = 1:numel(seg_edges)-1
    lo = seg_edges(s); hi = seg_edges(s+1);
    idx_tg = find(tg >= lo - 1e-14 & tg <= hi + 1e-14);
    idx_f = find(r_fixed.t >= lo - 1e-14 & r_fixed.t <= hi + 1e-14);
    idx_a = find(r_adapt.t >= lo - 1e-14 & r_adapt.t <= hi + 1e-14);
    for k = 1:size(delta_f_interp,2)
        delta_f_interp(idx_tg,k) = interp_no_extrapolate(r_fixed.t(idx_f), r_fixed.delta(idx_f,k), tg(idx_tg));
        delta_a_interp(idx_tg,k) = interp_no_extrapolate(r_adapt.t(idx_a), r_adapt.delta(idx_a,k), tg(idx_tg));
        omega_f_interp(idx_tg,k) = interp_no_extrapolate(r_fixed.t(idx_f), r_fixed.omega(idx_f,k), tg(idx_tg));
        omega_a_interp(idx_tg,k) = interp_no_extrapolate(r_adapt.t(idx_a), r_adapt.omega(idx_a,k), tg(idx_tg));
    end
end
ddelta = max(abs(rad2deg(delta_f_interp - delta_a_interp)),[],'all');
domega = max(abs(omega_f_interp - omega_a_interp),[],'all');
testCase.verifyLessThan(ddelta, 1.0, 'Fixed-vs-adaptive COI angle < 1.0 deg (corrector-mode difference).');
testCase.verifyLessThan(domega, 1e-3, 'Fixed-vs-adaptive speed < 1e-3 pu.');
end
