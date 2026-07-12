function tests = test_ts_strategy_equivalence()
%TEST_TS_STRATEGY_EQUIVALENCE  Strategy path == legacy path (bit-identical).
%   Verifies that routing the fixed-step Padiyar/EMF6 one-step through the model
%   strategy (ts_model_strategy) produces a bit-identical result to the legacy
%   (dae_f, dae_g, Y, Jyy, opt) signature of ts_step_kernel. This is the Phase 1
%   mechanical-refactor equivalence gate: the strategy is a thin adapter that
%   maps into the canonical kernel, NOT a second trapezoidal implementation.
%
%   Per the approved plan: Padiyar/EMF6 fixed-step must be bit-identical when
%   called via the strategy path vs the legacy signature path. Any difference
%   is a root-cause investigation (FP ordering vs bug), never a tolerance raise.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function [x,y,Y,Jyy,dae,kopt] = padiyar_setup()
case_data = cases.case_padiyar_two_area_4m_avr();
opt = struct('excitation','avr','fault_bus',3,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'dt',0.01,'fault_enabled',true);
dae = stability.padiyar_model11_dae(case_data, opt);
x = dae.x0(:); y = dae.y0(:);
Ypre = dae.Ynet;
Yfault = Ypre;
fb = find(dae.bus_ids == opt.fault_bus, 1);
Yfault(fb,fb) = Yfault(fb,fb) + 1/opt.Zf;
Y = Yfault;   % step during the fault
Jyy = stability.ts_jac_y_fd(x, y, Y, dae.dae_g);
kopt = struct('algebraic_tolerance',1e-11,'max_corrector_iter',12, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'corrector_mode','adaptive');
end

function [x,y,Y,Jyy,dae,kopt] = emf6_setup()
case_data = cases.kundur_ex126_book_case();
opt = struct('load_model','cz','fault_bus',8,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1);
dae = stability.emf6_dae(case_data, opt);
x = dae.init.x0(:); y = dae.init.y0(:);
Ypre = dae.Ynet;
Yfault = Ypre;
fb = find(dae.bus_ids == opt.fault_bus, 1);
Yfault(fb,fb) = Yfault(fb,fb) + 1/opt.Zf;
Y = Yfault;
Jyy = stability.ts_jac_y_fd(x, y, Y, dae.dae_g);
kopt = struct('algebraic_tolerance',1e-12,'max_corrector_iter',10, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'corrector_mode','fixed','corrector_iter',2);
end

function test_padiyar_strategy_matches_legacy(testCase)
[x,y,Y,Jyy,dae,kopt] = padiyar_setup();
h = 0.01;
% Legacy path
step_legacy = stability.ts_step_kernel(x,y,h,dae.dae_f,dae.dae_g,Y,Jyy,kopt);
% Strategy path
strat = stability.ts_model_strategy('padiyar', dae);
step_strat = stability.ts_step_kernel(strat,x,y,h,Y,kopt);
testCase.verifyEqual(step_strat.x_full, step_legacy.x_full, 'AbsTol', 0);
testCase.verifyEqual(step_strat.y_full, step_legacy.y_full, 'AbsTol', 0);
testCase.verifyEqual(step_strat.corrector_residual, step_legacy.corrector_residual, 'AbsTol', 0);
testCase.verifyEqual(step_strat.corrector_iterations, step_legacy.corrector_iterations);
testCase.verifyEqual(step_strat.corrector_converged, step_legacy.corrector_converged);
end

function test_emf6_strategy_matches_legacy(testCase)
[x,y,Y,Jyy,dae,kopt] = emf6_setup();
h = 0.001;
step_legacy = stability.ts_step_kernel(x,y,h,dae.dae_f,dae.dae_g,Y,Jyy,kopt);
strat = stability.ts_model_strategy('emf6', dae);
step_strat = stability.ts_step_kernel(strat,x,y,h,Y,kopt);
testCase.verifyEqual(step_strat.x_full, step_legacy.x_full, 'AbsTol', 0);
testCase.verifyEqual(step_strat.y_full, step_legacy.y_full, 'AbsTol', 0);
testCase.verifyEqual(step_strat.corrector_residual, step_legacy.corrector_residual, 'AbsTol', 0);
testCase.verifyEqual(step_strat.corrector_iterations, step_legacy.corrector_iterations);
end
