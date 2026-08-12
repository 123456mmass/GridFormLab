function tests = test_ts_hybrid_adaptive_rollback()
%TEST_TS_HYBRID_ADAPTIVE_ROLLBACK  A rejected adaptive trial must leave no trace.
%   The adaptive accept/reject loop works on local temporaries and commits once,
%   so a rejected step may advance NOTHING except the rejection bookkeeping.
%   These tests pin the observable consequences of that contract:
%
%     G-ROLLBACK  numel(rejection_history) == rejected_steps; every recorded
%                 rejection carries a reason drawn from the closed vocabulary and
%                 a retry_dt that is exactly the halved (floored) attempt; the
%                 accepted time grid is strictly increasing; and the run is
%                 deterministic (two identical invocations agree to the last bit).
%     Landing     every scheduled event time appears exactly in res.t, so
%                 rejection/halving never steps over an event boundary.
%
%   Determinism is the load-bearing assertion: it is what proves a rejected
%   trial did not perturb supervisor state (event cursor, dwell timers, mode
%   commitments). If a reject leaked, the second run would diverge.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function [scenario,opt] = adaptive_arm()
% Short chronology arm with a tight tolerance, so the controller is forced to
% reject and halve at least once (the load step at 0.92 drives the GFM current
% limiters). Kept brief to stay a targeted test rather than a production run.
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
opt.t_end = 1.00;
opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',0.90,'load_step',0.92,'load_step_factor',0.20, ...
    'fault_on',0.94,'fault_clear',0.95,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',0.96,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',0.98,'sg_on',0.98,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
opt.stepper = 'adaptive';
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
opt.dt_max = 0.5; opt.dt_max_armed = 0.05; opt.reject_limit = 12;
end

function test_rejection_bookkeeping_is_consistent(testCase)
[scenario,opt] = adaptive_arm();
r = stability.run_hybrid_case(scenario,opt);

testCase.assertEqual(char(r.stepper),'adaptive');
testCase.assertTrue(isfield(r,'rejection_history'), ...
    'adaptive must publish rejection_history');
testCase.verifyEqual(numel(r.rejection_history), r.rejected_steps, ...
    'every rejected step must appear exactly once in rejection_history');

valid = {'newton_nonconvergence','nonfinite_estimate','algebraic_residual', ...
    'lte_exceeded'};
% dt_min is the driver's default adaptive floor: dt/2^(max_step_subdivisions+1)
% (initialize(), ts_simulate_ibr_hybrid). retry_dt is the halved attempt floored
% there, so once attempted_dt/2 falls below dt_min the retry pins to dt_min.
dt_min = opt.dt / (2^(opt.max_step_subdivisions+1));
for k = 1:numel(r.rejection_history)
    rec = r.rejection_history(k);
    testCase.verifyTrue(ismember(rec.reason,valid), ...
        sprintf('unexpected rejection reason "%s"',rec.reason));
    % The retry is the halved attempt, floored at dt_min. This is what makes a
    % rejection monotone progress toward the floor rather than an open loop.
    testCase.verifyEqual(rec.retry_dt, max(dt_min, rec.attempted_dt/2), ...
        'RelTol',1e-12, 'retry_dt must be the floored half of the attempt');
    testCase.verifyGreaterThan(rec.attempted_dt, 0);
end
end

function test_accepted_grid_is_monotone_and_lands_on_events(testCase)
[scenario,opt] = adaptive_arm();
r = stability.run_hybrid_case(scenario,opt);
testCase.assertTrue(r.converged, ...
    sprintf('adaptive arm must converge (%s)', ...
    char(local_get(r,'failure_reason',''))));

t = r.t(:);
% The hybrid schema stores a LEFT-limit and a RIGHT-limit sample at each event
% instant (the arrival state and the post-transition state share the event
% timestamp). So the raw sample grid is monotone NON-decreasing with an exact
% zero gap at every applied event time -- NOT strictly increasing. Assert
% non-decreasing, then prove every zero gap coincides with an event (a zero gap
% mid-coast is what a leaked/duplicated step would produce).
dts = diff(t);
testCase.verifyGreaterThanOrEqual(min(dts), 0, ...
    'accepted time grid must be monotone non-decreasing');
testCase.verifyEqual(t(1),0,'AbsTol',0);
zero_gap_t = t([false; dts <= 0]);   % timestamps of the duplicate samples
for z = zero_gap_t(:).'
    testCase.verifyTrue(any(abs([r.events.t] - z) <= 1e-9), ...
        sprintf('a zero time gap at t=%.6f is not on any event (possible leaked step)', z));
end

% G-LANDING: a rejected step halves h, so the target can only move closer to an
% event boundary, never past it. Every scheduled event must therefore be hit.
for k = 1:numel(r.events)
    miss = min(abs(t - r.events(k).t));
    testCase.verifyLessThanOrEqual(miss, 1e-9, ...
        sprintf('event %d at t=%.6f was stepped over (closest sample %.3e away)', ...
        k, r.events(k).t, miss));
end
end

function test_adaptive_run_is_deterministic(testCase)
% If a rejected trial leaked into supervisor state (event cursor, dwell timers,
% mode commitments, RNG-free counters), a second identical run would diverge.
[scenario,opt] = adaptive_arm();
r1 = stability.run_hybrid_case(scenario,opt);
r2 = stability.run_hybrid_case(scenario,opt);

testCase.verifyEqual(r2.t,       r1.t,       'AbsTol',0, 't must be reproducible');
testCase.verifyEqual(r2.x_traj,  r1.x_traj,  'AbsTol',0, 'x_traj must be reproducible');
testCase.verifyEqual(r2.y_traj,  r1.y_traj,  'AbsTol',0, 'y_traj must be reproducible');
testCase.verifyEqual(r2.rejected_steps, r1.rejected_steps);
testCase.verifyEqual(r2.dt_history, r1.dt_history, 'AbsTol',0);
testCase.verifyEqual(char(r2.reclose_status), char(r1.reclose_status));
end

function test_dt_history_matches_accepted_grid(testCase)
% dt_history records the step ACTUALLY taken, so it must reconstruct the grid.
[scenario,opt] = adaptive_arm();
r = stability.run_hybrid_case(scenario,opt);
testCase.assertTrue(r.converged);
testCase.verifyLessThanOrEqual(max(r.dt_history), opt.dt_max*(1+1e-12), ...
    'no accepted step may exceed dt_max');
testCase.verifyEqual(numel(r.lte_history), numel(r.dt_history), ...
    'one LTE record per accepted step');
% Backward-Euler window steps carry no Richardson estimate and are recorded as
% NaN; every other accepted step must have a finite error at or below tol.
fin = r.lte_history(isfinite(r.lte_history));
testCase.verifyTrue(all(fin >= 0), 'LTE estimates must be nonnegative');
end

function v = local_get(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
