function g = check_emf6_no_fault_gate()
%CHECK_EMF6_NO_FAULT_GATE  True no-fault EMF6 equilibrium gate.
%   Runs the EMF6 TS with fault_enabled=false (NO fault active during the
%   simulation — not a fault placed outside the window). The operating point
%   must be an equilibrium: the state, voltage, speed and generator power must
%   not drift, the corrector must converge every step, and all values must be
%   finite. Reports the actual residual/drift metrics (not just a count).
%
%   Tolerances are declared a priori from numerical precision (matching
%   test_emf6_contract): the initializer solves angle init to 1e-10 and the
%   DAE residual is ~1e-14, so EQ_TOL=1e-10 is conservative; an implicit
%   trapezoidal run from a machine-precision equilibrium accumulates only
%   round-off (~1e-12), so DRIFT_TOL=1e-9 is conservative.

pf_init_paths;
EQ_TOL = 1e-10;   % equilibrium residual (declared a priori)
DRIFT_TOL = 1e-9; % no-fault trapezoidal drift (declared a priori)

c = cases.kundur_ex126_book_case();
dae = stability.emf6_dae(c, struct('load_model','cc_p_cz_q'));
f0 = dae.dae_f(dae.init.x0, dae.init.y0);
g0 = dae.dae_g(dae.init.x0, dae.init.y0, dae.Ynet);
max_f = norm(f0,inf);
max_g = norm(g0,inf);
init_res = norm([f0; g0], inf);

% TRUE no-fault run: fault_enabled=false (no fault topology ever applied).
opt = struct('model','emf6','t_end',2.0,'dt',0.01,'fault_bus',8, ...
    't_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'method','trapezoidal', ...
    'corrector_mode','fixed','corrector_iter',2,'load_model','cc_p_cz_q', ...
    'fault_enabled',false,'verbose',false);
r = stability.ts_simulate(c, opt);

g = struct();
g.fault_disabled = true;   % fault_enabled=false was passed
g.max_f = max_f;
g.max_g = max_g;
g.init_residual = init_res;
g.nonconverged_steps = r.nonconverged_step_count;
g.max_corrector_residual = r.max_corrector_residual;
g.drift_delta = max(abs(r.delta(end,:) - r.delta(1,:)),[],'all');
g.drift_omega = max(abs(r.omega),[],'all');   % omega is deviation
g.drift_Vbus  = max(abs(r.Vbus(end,:) - r.Vbus(1,:)),[],'all');
g.drift_Pe    = max(abs(r.Pe_pu(end,:) - r.Pe_pu(1,:)),[],'all');
g.all_finite  = all(isfinite(r.delta(:))) && all(isfinite(r.omega(:))) && ...
                all(isfinite(r.Vbus(:))) && all(isfinite(r.Pe_pu(:)));
g.completed   = (numel(r.t) == numel((0:0.01:2.0).')) && abs(r.t(end)-2.0)<1e-9;
g.tol = struct('eq',EQ_TOL,'drift',DRIFT_TOL);

g.gate = g.fault_disabled && (g.max_f < EQ_TOL) && (g.max_g < EQ_TOL) && ...
         (g.init_residual < EQ_TOL) && (g.nonconverged_steps == 0) && ...
         (g.drift_delta < DRIFT_TOL) && (g.drift_omega < DRIFT_TOL) && ...
         (g.drift_Vbus < DRIFT_TOL) && (g.drift_Pe < DRIFT_TOL) && ...
         g.all_finite && g.completed;

fprintf('=== No-fault EMF6 gate (fault_enabled=false) ===\n');
fprintf('  fault_disabled=%d  max|f|=%.3e  max|g|=%.3e  init_res=%.3e\n', g.fault_disabled, g.max_f, g.max_g, g.init_residual);
fprintf('  nonconv=%d  max_corrector_resid=%.3e  completed=%d  all_finite=%d\n', g.nonconverged_steps, g.max_corrector_residual, g.completed, g.all_finite);
fprintf('  drift: delta=%.3e omega=%.3e Vbus=%.3e Pe=%.3e (tol %.0e)\n', g.drift_delta, g.drift_omega, g.drift_Vbus, g.drift_Pe, DRIFT_TOL);
fprintf('  GATE = %s\n', ternary(g.gate,'PASS','FAIL'));
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
