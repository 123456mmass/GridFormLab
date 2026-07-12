function tests = test_ts_classical_strategy_equivalence()
%TEST_TS_CLASSICAL_STRATEGY_EQUIVALENCE  Classical strategy path == legacy inline.
%   Verifies that routing the classical fixed-step one-step through the model
%   strategy (ts_model_strategy('classical', ...)) + classical_step produces a
%   trajectory equivalent to the legacy inline corrector in ts_simulate.
%   This is the Phase 2 mechanical-refactor equivalence gate.
%
%   Classical algebraic contract is LINEAR (V = (Y+Ygen)\Iinj, solved exactly
%   inside dae_f); there is no nonlinear dae_g and no Jyy. The strategy path
%   uses classical_step (skips ts_algebraic_solve). The trapezoidal
%   predictor/corrector/residual algorithm is the SAME as the legacy path.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function [dae,Yfault,Ypre] = setup_classical()
c = cases.case_matpower6_case14();
opt = struct('pm_mode','pgaz','fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'fault_enabled',true,'model','classical');
dae = stability.classical_dae(c, opt);
Ypre = dae.Ynet;
Yfault = Ypre;
fb = find(dae.bus_ids == opt.fault_bus, 1);
Yfault(fb,fb) = Yfault(fb,fb) + 1/opt.Zf;
end

function test_classical_strategy_step_matches_legacy_formula(testCase)
[dae,Yfault,~] = setup_classical();
x = dae.x0(:); y = dae.y0(:);
h = 0.01;
strat = stability.ts_model_strategy('classical', dae);
kopt = struct('max_corrector_iter',10,'corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'corrector_mode','adaptive');
step = stability.ts_step_kernel(strat, x, y, h, Yfault, kopt);
% Manual replication of the legacy adaptive corrector (ts_simulate lines 195-237),
% adapted to use dae_f(x,y,Y) with the topology Y.
f0 = dae.dae_f(x, y, Yfault);
xnext = x + h*f0;
tol_now = 1e-10 + 1e-8*max(1, norm(xnext, inf));
residual_ref = 0;
for ci = 1:10
    f1 = dae.dae_f(xnext, y, Yfault);
    x_new = x + 0.5*h*(f0 + f1);
    f1_new = dae.dae_f(x_new, y, Yfault);
    R = x_new - x - 0.5*h*(f0 + f1_new);
    update_norm = norm(x_new - xnext, inf);
    residual_norm = norm(R, inf);
    xnext = x_new;
    if update_norm <= tol_now && residual_norm <= tol_now
        residual_ref = residual_norm; break;
    end
    residual_ref = residual_norm;
end
testCase.verifyEqual(step.x_full, xnext, 'AbsTol', 0, ...
    'Classical strategy x_full must match the legacy adaptive-corrector formula.');
testCase.verifyEqual(step.corrector_residual, residual_ref, 'AbsTol', 0);
end

function test_classical_strategy_fixed_step_matches_legacy(testCase)
[dae,Yfault,~] = setup_classical();
x = dae.x0(:); y = dae.y0(:);
h = 0.01;
strat = stability.ts_model_strategy('classical', dae);
kopt = struct('max_corrector_iter',10,'corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'corrector_mode','fixed','corrector_iter',10);
step = stability.ts_step_kernel(strat, x, y, h, Yfault, kopt);
% Legacy fixed corrector: exactly ci iterations.
f0 = dae.dae_f(x, y, Yfault);
xnext = x + h*f0;
for ci = 1:10
    f1 = dae.dae_f(xnext, y, Yfault);
    xnext = x + 0.5*h*(f0 + f1);
end
testCase.verifyEqual(step.x_full, xnext, 'AbsTol', 0, ...
    'Classical strategy fixed x_full must match the legacy fixed-corrector formula.');
end

function test_classical_strategy_no_finite_check(testCase)
[dae,Yfault,~] = setup_classical();
x = dae.x0(:); y = dae.y0(:);
h = 0.01;
strat = stability.ts_model_strategy('classical', dae);
kopt = struct('max_corrector_iter',10,'corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'corrector_mode','adaptive');
step = stability.ts_step_kernel(strat, x, y, h, Yfault, kopt);
testCase.verifyTrue(step.finite);
testCase.verifyTrue(all(isfinite(step.x_full)));
end
