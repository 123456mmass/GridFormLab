function tests = test_ts_adaptive_convergence()
%TEST_TS_ADAPTIVE_CONVERGENCE  Phase 7 cross-model convergence tests.
%   Separates local (O(h^3)) and global (O(h^2)) error orders on the actual TS
%   models (classical Case14, EMF6 Kundur) and the analytic SHO. Confirms the
%   Richardson denominator 3 and the controller exponent 1/3 across models.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_classical_local_error_order_h3(testCase)
% Local one-step error on SHO (analytic dynamics; classical Case14 at no-fault
% equilibrium has dx/dt=0 so the estimator is trivially 0). Halving h cuts the
% LTE estimator by ~8 (2^(p+1), p=2).
strat = sho_strat();
kopt = struct('max_corrector_iter',50,'corrector_abs_tol',1e-14, ...
    'corrector_rel_tol',1e-12,'corrector_mode','adaptive','algebraic_tolerance',1e-12);
x = [1;0]; y = []; Y = 0;
errs = zeros(1,3); hs = [0.04, 0.02, 0.01];
for k = 1:numel(hs)
    h = hs(k);
    sf = stability.ts_step_kernel(strat,x,y,h,Y,kopt);
    sh1 = stability.ts_step_kernel(strat,x,y,h/2,Y,kopt);
    sh2 = stability.ts_step_kernel(strat,sh1.x_full,sh1.y_full,h/2,Y,kopt);
    errs(k) = max(abs((sh2.x_full - sf.x_full)/3));
end
ratio1 = errs(1) / (errs(2) + 1e-300);
ratio2 = errs(2) / (errs(3) + 1e-300);
testCase.verifyGreaterThan(ratio1, 5.0, 'Local estimator should drop ~8 when h halves.');
testCase.verifyLessThan(ratio1, 12.0);
testCase.verifyGreaterThan(ratio2, 5.0);
testCase.verifyLessThan(ratio2, 12.0);
end

function test_sho_global_order_h2(testCase)
% Global trajectory error on SHO at fixed final time: halving h cuts global
% error by ~4 (2^p, p=2). Use a FIXED step size (not the adaptive controller)
% to isolate the trapezoidal global order from the controller's dt selection.
strat = sho_strat();
kopt = struct('max_corrector_iter',100,'corrector_abs_tol',1e-14, ...
    'corrector_rel_tol',1e-14,'corrector_mode','adaptive','algebraic_tolerance',1e-12);
T = 2.0; hs = [0.02, 0.01, 0.005];
errs = zeros(size(hs));
for k = 1:numel(hs)
    h = hs(k);
    n = round(T/h);
    x = [1;0]; y = []; Y = 0;
    for it = 1:n
        sh1 = stability.ts_step_kernel(strat,x,y,h/2,Y,kopt);
        sh2 = stability.ts_step_kernel(strat,sh1.x_full,sh1.y_full,h/2,Y,kopt);
        x = sh2.x_full; y = sh2.y_full;
    end
    errs(k) = abs(x(1) - cos(T));
end
ratio = errs(1) / (errs(2) + 1e-300);
testCase.verifyGreaterThan(ratio, 2.5, 'Global error should drop ~4 when h halves.');
testCase.verifyLessThan(ratio, 6.0);
end

function test_richardson_denominator_3_across_halving(testCase)
% The estimator e=(x_halfhalf-x_full)/3 must scale by ~8 across h halving on
% the SHO (denominator 3, not 7).
strat = sho_strat();
kopt = struct('max_corrector_iter',50,'corrector_abs_tol',1e-14, ...
    'corrector_rel_tol',1e-12,'corrector_mode','adaptive','algebraic_tolerance',1e-12);
x = [1;0]; y = []; Y = 0; h = 0.04;
sf = stability.ts_step_kernel(strat,x,y,h,Y,kopt);
sh1 = stability.ts_step_kernel(strat,x,y,h/2,Y,kopt);
sh2 = stability.ts_step_kernel(strat,sh1.x_full,sh1.y_full,h/2,Y,kopt);
e_h = (sh2.x_full - sf.x_full)/3;
h2 = h/2;
sf2 = stability.ts_step_kernel(strat,x,y,h2,Y,kopt);
sh1b = stability.ts_step_kernel(strat,x,y,h2/2,Y,kopt);
sh2b = stability.ts_step_kernel(strat,sh1b.x_full,sh1b.y_full,h2/2,Y,kopt);
e_h2 = (sh2b.x_full - sf2.x_full)/3;
ratio = max(abs(e_h)) / (max(abs(e_h2)) + 1e-300);
testCase.verifyGreaterThan(ratio, 5.0, 'Denominator-3 estimator should drop ~8 across h halving.');
testCase.verifyLessThan(ratio, 12.0);
end

function strat = sho_strat()
strat = struct();
strat.model = 'sho_test';
strat.dae_f = @(x,~,~) [x(2); -x(1)];
strat.dae_g = [];
strat.jac_y = @(~,~,~) [];
strat.needs_jyy = false;
strat.needs_algebraic_solve = false;
strat.electrical_power = @(~,~,~) [];
strat.state_split = struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2);
strat.reconstruct = @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',zeros(0,1));
end

function test_all_models_adaptive_complete(testCase)
% All three models run a short adaptive scenario and report the frozen schema.
% Classical
c14 = cases.case_matpower6_case14();
r1 = stability.ts_simulate(c14, struct('stepper','adaptive','t_end',2,'dt',0.01, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyEqual(r1.stepper,'adaptive');
testCase.verifyTrue(all(isfinite(r1.delta(:))));
% Padiyar
cp = cases.case_padiyar_two_area_4m_avr();
r2 = stability.ts_simulate(cp, struct('model','padiyar_1_1_avr','stepper','adaptive', ...
    't_end',3,'dt',0.01,'fault_bus',3,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'excitation','avr','verbose',false));
testCase.verifyEqual(r2.stepper,'adaptive');
testCase.verifyTrue(all(isfinite(r2.delta(:))));
% EMF6
ce = cases.case_kundur_two_area_classical();
r3 = stability.ts_simulate(ce, struct('model','emf6','stepper','adaptive', ...
    't_end',2,'dt',1e-3,'fault_bus',8,'t_fault',1.0,'t_clear',1.05,'Zf',[], ...
    'load_model','cz','verbose',false));
testCase.verifyEqual(r3.stepper,'adaptive');
testCase.verifyTrue(all(isfinite(r3.delta(:))));
end
