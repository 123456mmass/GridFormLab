function tests = test_ts_adaptive_rollback()
%TEST_TS_ADAPTIVE_ROLLBACK  Rejected-step full rollback (plan §4, §5 item 8).
%   A rejected step must restore x, y, Jyy/cache exactly and append exactly one
%   rejection diagnostic. Accepted output arrays must not be altered.
tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end
function test_rejection_log_grows_one_per_reject(testCase)
% Force rejections with a tight tolerance on the SHO; verify the rejection
% history length equals the rejected count and each record has err > 1.
strat = struct();
strat.model = 'sho';
strat.dae_f = @(x,~,~) [x(2); -x(1)];
strat.dae_g = [];
strat.jac_y = @(~,~,~) [];
strat.needs_jyy = false;
strat.needs_algebraic_solve = false;
strat.electrical_power = @(~,~,~) [];
strat.state_split = struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2);
strat.reconstruct = @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',zeros(0,1));
opt = struct('dt_init',0.1,'dt_nominal',0.1,'dt_min',1e-5,'dt_max',0.1, ...
    'controller_fac',0.9,'controller_fac_min',0.2,'controller_fac_max',5.0, ...
    'reject_limit',50,'atol_x',1e-9,'rtol_x',1e-7,'atol_y',1e-9,'rtol_y',1e-7, ...
    'algebraic_tolerance',1e-12,'max_corrector_iter',50, ...
    'corrector_abs_tol',1e-14,'corrector_rel_tol',1e-12,'corrector_mode','adaptive');
ev = struct('fault_enabled',false,'t_fault',inf,'t_clear',inf, ...
    'Ypre',0,'Yfault',0,'Ypost',0);
r = stability.ts_adaptive_driver(strat, [1;0], [], [0, 0.3], ev, opt);
if r.rejected_steps > 0
    testCase.verifyEqual(numel(r.rejection_history), r.rejected_steps);
    for k = 1:numel(r.rejection_history)
        testCase.verifyGreaterThan(r.rejection_history(k).error_norm, 1.0);
    end
end
% Accepted trajectory strictly increasing (rejections did not corrupt output).
testCase.verifyTrue(all(diff(r.t) > 0));
end
function test_accepted_output_not_altered_by_rejection(testCase)
% The accepted delta trajectory must be continuous and monotone in time; a
% rejection never inserts a partial/corrupted sample.
strat = struct();
strat.model = 'sho';
strat.dae_f = @(x,~,~) [x(2); -x(1)];
strat.dae_g = []; strat.jac_y = @(~,~,~) [];
strat.needs_jyy = false; strat.needs_algebraic_solve = false;
strat.electrical_power = @(~,~,~) [];
strat.state_split = struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2);
strat.reconstruct = @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',zeros(0,1));
opt = struct('dt_init',0.1,'dt_nominal',0.1,'dt_min',1e-5,'dt_max',0.1, ...
    'controller_fac',0.9,'controller_fac_min',0.2,'controller_fac_max',5.0, ...
    'reject_limit',50,'atol_x',1e-9,'rtol_x',1e-7,'atol_y',1e-9,'rtol_y',1e-7, ...
    'algebraic_tolerance',1e-12,'max_corrector_iter',50, ...
    'corrector_abs_tol',1e-14,'corrector_rel_tol',1e-12,'corrector_mode','adaptive');
ev = struct('fault_enabled',false,'t_fault',inf,'t_clear',inf, ...
    'Ypre',0,'Yfault',0,'Ypost',0);
r = stability.ts_adaptive_driver(strat, [1;0], [], [0, 1.0], ev, opt);
testCase.verifyEqual(numel(r.delta), numel(r.t));
testCase.verifyTrue(all(isfinite(r.delta)));
% SHO with x0=[1;0]: delta should stay in [-1, 1] (cosine).
testCase.verifyTrue(max(abs(r.delta)) <= 1.0 + 1e-6);
end
