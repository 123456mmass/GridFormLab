function res = ts_simulate_emf6(case_data, opt)
%TS_SIMULATE_EMF6 Higher-order EMF6 transient simulation.
%   Consumes stability.emf6_dae as the SINGLE source of the sixth-order DAE
%   so that SSSA (stability.synchronous_emf6_ssa) and transient stability
%   share one equation set, one initialization, and one network convention.
%
%   State order per machine: [delta, omega, E'q, E'd, E''q, E''d] (radians,
%   pu speed deviation, pu EMFs). Algebraic state y = [Re(V); Im(V)] per bus.
%
%   Integration: implicit trapezoidal predictor-corrector. The default
%   corrector mode for the higher-order EMF6 path is FIXED iterations; an
%   adaptive residual-checked mode is available but is NOT advertised as
%   validated until audited (see AGENTS.md). The classical TS engine
%   remains the validated adaptive path.
%
%   opt fields: t_end, dt, fault_bus, t_fault, t_clear, Zf ([] = solid),
%               method ('trapezoidal'), corrector_mode ('fixed'|'adaptive'),
%               corrector_iter, max_corrector_iter, corrector_abs_tol,
%               corrector_rel_tol, corrector_failure, load_model, verbose.

% --- Phase-2: resolve integrator BEFORE DAE construction --------------------
% (exactly-one resolution per executed route; the parent ts_simulate
% dispatches unresolved). step_fn is the resolved single-step handle
% (@ts_step_kernel for trapezoidal -> bit-identical). The adaptiveNotFrozen
% gate fires before the stepper dispatch below.
[integrator, integrator_source, opt] = stability.resolve_ts_integrator(opt);
opt.integrator_source = integrator_source;
step_fn = stability.ts_integrator_step(opt);
if isfield(opt,'stepper') && strcmpi(opt.stepper,'adaptive') ...
        && ~strcmp(integrator,'trapezoidal')
    error('ts_simulate_emf6:adaptiveNotFrozen', ...
        ['Adaptive stepper is not frozen for integrator ''%s''. ' ...
         'backward_euler and rk4 are FIXED-STEP ONLY (correction 6). ' ...
         'No silent fallback.'], integrator);
end

% --- Build the single EMF6 DAE --------------------------------------------
dae = stability.emf6_dae(case_data, opt);
init = dae.init; ng = dae.ng; nb = dae.nb;
bus_ids = dae.bus_ids(:); gen_buses = dae.gen_buses(:);
dae_f = dae.dae_f; dae_g = dae.dae_g; Pe_fun = dae.electrical_power;
H = dae.units.H_system(:); D = dae.units.D_system(:);
Ypre = dae.Ynet;
x = init.x0(:); y = init.y0(:);

% --- Options --------------------------------------------------------------
dt = opt.dt; tmax = opt.t_end;
method = opt.method; if isempty(method), method = 'trapezoidal'; end
if isfield(opt,'corrector_mode') && ~isempty(opt.corrector_mode)
    cmode = opt.corrector_mode;
else
    cmode = 'fixed';
end
max_citer = pf_get_option(opt,'max_corrector_iter',10);
abs_tol = pf_get_option(opt,'corrector_abs_tol',1e-10);
rel_tol = pf_get_option(opt,'corrector_rel_tol',1e-8);
cfail = pf_get_option(opt,'corrector_failure','error');
if strcmp(cmode,'fixed')
    if isfield(opt,'corrector_iter') && ~isempty(opt.corrector_iter)
        citer = opt.corrector_iter;
    else
        citer = 3; % EMF6 default fixed corrector iterations
    end
else
    citer = 0;
end
verbose = pf_get_option(opt,'verbose',false);

% --- Fault topology -------------------------------------------------------
fb_id = opt.fault_bus;
if isempty(fb_id), fb_id = gen_buses(1); end
fb = find(bus_ids == fb_id, 1);
if isempty(fb), error('ts_simulate_emf6:badFaultBus','fault_bus %g not in bus_ids.',fb_id); end
fault_enabled = true; if isfield(opt,'fault_enabled') && ~isempty(opt.fault_enabled), fault_enabled = opt.fault_enabled; end
Yfault = Ypre;
if fault_enabled
    if isempty(opt.Zf)
        % Solid three-phase fault: pin V_fault = 0 (row/col zeroed, diag = 1).
        Yfault(fb,:) = 0; Yfault(:,fb) = 0; Yfault(fb,fb) = 1;
    else
        Yfault(fb,fb) = Yfault(fb,fb) + 1/opt.Zf;
    end
end
Ypost = Ypre;

% --- Stepper dispatch (Phase 5) --------------------------------------------
% opt.stepper='fixed' (default if stepper is absent or 'fixed'): canonical
%   fixed-step path (bit-identical to the validated baseline).
% opt.stepper='adaptive': variable-dt LTE/reject path via ts_adaptive_driver.
%   Adaptive is reached only when opt.stepper is explicitly 'adaptive'; the
%   production default is fixed. Catalog/run_ts may inject stepper='adaptive'.
% Fixed-step EMF6 Jyy caching is UNCHANGED (Open Q5).
if isfield(opt,'stepper') && strcmpi(opt.stepper,'adaptive')
    res = run_emf6_adaptive(opt, dae, Ypre, Yfault, Ypost, integrator, integrator_source);
    return;
end

% --- Event-aware time grid (no step straddles a topology change) ----------
% Snap the nearest grid point to each exact event time so the fault/clear
% topology switch is applied at the exact event instant (not one step late
% due to floating-point accumulation in the colon grid).
t = (0:dt:tmax).';
event_times = [];
if fault_enabled && isfinite(opt.t_fault) && opt.t_fault > t(1) && opt.t_fault < t(end)
    event_times = [event_times; opt.t_fault]; end
if fault_enabled && isfinite(opt.t_clear) && opt.t_clear > t(1) && opt.t_clear < t(end)
    event_times = [event_times; opt.t_clear]; end
event_idx = [];
for et = event_times.'
    [~,idx] = min(abs(t - et));
    t(idx) = et;          % exact event time on the grid
    event_idx = [event_idx; idx]; %#ok<AGROW>
end
event_idx = sort(event_idx);
nt = numel(t); dt_arr = diff(t);
event_side = zeros(nt,1);
for ei = event_idx.', event_side(ei) = 1; end

% --- Storage ---------------------------------------------------------------
delta_hist = zeros(nt,ng); omega_hist = zeros(nt,ng);
Pe_hist = zeros(nt,ng); Vbus_hist = zeros(nt,nb);
corr_iters = zeros(nt-1,1); corr_residual = zeros(nt-1,1);
corr_update = zeros(nt-1,1); corr_converged = true(nt-1,1); nonconv = 0;
% Phase-2: endpoint algebraic-residual evidence (additive).
integrator_alg_res = zeros(nt-1,1);

% --- Algebraic network solver: solve dae_g(x,.,Y) = 0 for y ----------------
g_tol = 1e-12;            % tight, so no-fault equilibrium is preserved

Ycur = Ypre;

% Phase 1: route through the model-strategy contract (thin adapter into the
% canonical ts_step_kernel). Bit-identical to the legacy call verified by
% tests/test_ts_strategy_equivalence.m.
strat = stability.ts_model_strategy('emf6', dae);

set_topo = @(tnow) stability.ts_topology_at(tnow, opt, Ypre, Yfault, Ypost);
for it = 1:nt-1
    dt_step = dt_arr(it);
    t_now = t(it); t_next = t(it+1);
    Y_now  = set_topo(t_now);
    Y_next = set_topo(t_next);
    jac_y = stability.ts_jac_y_fd(x,y,Y_now,dae_g);

    % Consistent algebraic state at current x (seed with previous y).
    [y, alg_info] = stability.ts_algebraic_solve(x, y, Y_now, dae_g, @stability.ts_jac_y_fd, g_tol, jac_y);
    if ~alg_info.converged, error('ts_simulate_emf6:algebraic', ...
        'Algebraic solve failed at t=%.4f (step %d): residual=%.3e (tol=%.3e), iters=%d.', t_now, it, alg_info.final_residual, g_tol, alg_info.iterations); end
    f0 = dae_f(x, y);

    % Record current sample.
    delta_hist(it,:) = x(1:6:end).'; omega_hist(it,:) = x(2:6:end).';
    Pe_hist(it,:) = Pe_fun(x, y).'; Vbus_hist(it,:) = abs(complex(y(1:2:end),y(2:2:end))).';

    % Predictor (explicit Euler).
    % The differential step [t_now, t_next] uses the topology at t_now
    % (Y_now) for BOTH f0 and the corrector, so no trapezoidal step averages
    % RHS from two different topologies across the fault/clear boundary. The
    % topology switches at the event boundary (next step). The post-step
    % algebraic state is re-solved with Y_next for the recorded voltage.
    kopt = struct('algebraic_tolerance',g_tol, ...
        'max_corrector_iter',max_citer,'corrector_mode',cmode, ...
        'corrector_abs_tol',abs_tol,'corrector_rel_tol',rel_tol);
    if strcmp(cmode,'fixed'), kopt.max_corrector_iter=citer; end
    step = step_fn(strat,x,y,dt_step,Y_now,kopt);
    corr_iters(it) = step.corrector_iterations;
    corr_residual(it) = step.corrector_residual;
    corr_update(it) = step.corrector_update;
    corr_converged(it) = step.corrector_converged;
    integrator_alg_res(it) = step.algebraic_residual;
    % Phase-2 endpoint gate for coupled BE/RK4.
    if strcmp(integrator,'backward_euler') || strcmp(integrator,'rk4')
        if ~step.finite
            error('ts_simulate_emf6:algebraicResidual', ...
                ['Integrator ''%s'' produced non-finite step at t=%.4f (step %d). ' ...
                 'No silent fallback.'], integrator, t_next, it);
        end
        if step.algebraic_residual > g_tol
            error('ts_simulate_emf6:algebraicResidual', ...
                ['Integrator ''%s'' endpoint algebraic residual=%.3e exceeds tol=%.3e ' ...
                 'at t=%.4f (step %d). No silent fallback.'], ...
                integrator, step.algebraic_residual, g_tol, t_next, it);
        end
    end
    if ~step.corrector_converged
        nonconv = nonconv + 1;
        if strcmp(cfail,'error') && strcmp(cmode,'adaptive')
            error('ts_simulate_emf6:correctorNotConverged', ...
                'Corrector did not converge at t=%.4f (step %d): residual=%.3e.', ...
                t_next, it, step.corrector_residual);
        end
    end
    x = step.x_full; jac_y = stability.ts_jac_y_fd(x,step.y_full,Y_next,dae_g);
    [y, alg_info2] = stability.ts_algebraic_solve(x, step.y_full, Y_next, dae_g, @stability.ts_jac_y_fd, g_tol, jac_y);
    if ~alg_info2.converged, error('ts_simulate_emf6:algebraic', ...
        'Algebraic solve failed at t=%.4f (step %d): residual=%.3e (tol=%.3e), iters=%d.', t_next, it, alg_info2.final_residual, g_tol, alg_info2.iterations); end
end
% Final sample.
delta_hist(nt,:) = x(1:6:end).'; omega_hist(nt,:) = x(2:6:end).';
Pe_hist(nt,:) = Pe_fun(x, y).'; Vbus_hist(nt,:) = abs(complex(y(1:2:end),y(2:2:end))).';

% --- Initial DAE residual (same equation set as SSSA) ----------------------
f0 = dae_f(init.x0, init.y0); g0 = dae_g(init.x0, init.y0, Ypre);
init_res = norm([f0; g0], inf);

if verbose
    fprintf('[ts_simulate_emf6] EMF6 TS: %d steps, method=%s, corrector=%s, nonconv=%d\n', ...
        nt-1, method, cmode, nonconv);
    fprintf('[ts_simulate_emf6] initial DAE residual=%.3e, max corrector residual=%.3e\n', ...
        init_res, max(corr_residual));
end

res = struct('t',t,'delta',delta_hist,'omega',omega_hist, ...
    'Pe_pu',Pe_hist,'Pe_MW',Pe_hist*dae.base.S_base_MVA, ...
    'Vbus',Vbus_hist,'pf',dae.pf,'bus_ids',bus_ids,'gen_buses',gen_buses, ...
    'H',H,'D',D,'Pm',init.Tm,'method',method,'dt',dt,'t_end',tmax, ...
    'fault_bus',fb_id,'t_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'model','emf6','model_key','emf6','engine','stability.synchronous_emf6_ssa', ...
    'omega_is_deviation',true,'initial_dae_residual',init_res, ...
    'corrector_mode',cmode,'corrector_iterations',corr_iters, ...
    'corrector_residual',corr_residual,'corrector_update_norm',corr_update, ...
    'corrector_converged',corr_converged,'max_corrector_iterations_used',max(corr_iters), ...
    'max_corrector_residual',max(corr_residual),'nonconverged_step_count',nonconv, ...
    'event_idx',event_idx,'event_side',event_side, ...
    'load_model',dae.load_model,'case_name',dae.case_name, ...
    'freq_Hz',dae.base.frequency_Hz, ...
    'integrator',integrator, ...
    'integrator_algebraic_residual',integrator_alg_res, ...
    'max_integrator_algebraic_residual',max(integrator_alg_res));
res.metadata = stability.ts_method_metadata(integrator, integrator_source, 'built_in_string');
end

function res = run_emf6_adaptive(opt, dae, Ypre, Yfault, Ypost, integrator, integrator_source)
%RUN_EMF6_ADAPTIVE  Phase 5 EMF6 adaptive-step path.
%   Builds the events struct + EMF6 strategy and calls the shared
%   ts_adaptive_driver. Converts the adaptive result to the legacy schema (plus
%   the frozen adaptive fields). Fixed-step EMF6 Jyy caching is NOT changed;
%   adaptive substeps start from a consistent y and do not cache Jyy across
%   rejected/independent trials (Open Q5). Phase-2: the route-level
%   adaptiveNotFrozen gate already guaranteed integrator='trapezoidal'; the
%   driver independently re-checks via aopt.integrator.
strat = stability.ts_model_strategy('emf6', dae);
events = struct('fault_enabled', ~isempty(opt.fault_enabled) && opt.fault_enabled, ...
    't_fault',opt.t_fault,'t_clear',opt.t_clear, ...
    'Ypre',Ypre,'Yfault',Yfault,'Ypost',Ypost);
aopt = struct();
aopt.dt_nominal = opt.dt;
aopt.dt_init = opt.dt;
aopt.dt_min = opt.dt/1024;
aopt.dt_max = opt.dt*4;
aopt.controller_fac = 0.9;
aopt.controller_fac_min = 0.2;
aopt.controller_fac_max = 5.0;
aopt.reject_limit = 30;
aopt.atol_x = 1e-6; aopt.rtol_x = 1e-4;
aopt.atol_y = 1e-5; aopt.rtol_y = 1e-4;
aopt.algebraic_tolerance = 1e-12;
aopt.max_corrector_iter = 10;
aopt.corrector_abs_tol = 1e-10;
aopt.corrector_rel_tol = 1e-8;
aopt.corrector_mode = 'adaptive';
aopt.integrator = integrator;   % Phase-2: thread for driver guard
ares = stability.ts_adaptive_driver(strat, dae.init.x0, dae.init.y0, ...
    [0, opt.t_end], events, aopt);
nt = numel(ares.t);
delta_hist = ares.delta; omega_hist = ares.omega;
Pe_hist = ares.Pe_pu; Vbus_hist = ares.Vbus;
corr_iters = zeros(nt-1,1); corr_residual = ares.lte_history(:);
corr_update = zeros(nt-1,1); corr_converged = true(nt-1,1); nonconv = ares.rejected_steps;
event_idx = find(abs(ares.t - opt.t_fault) < 1e-14 | abs(ares.t - opt.t_clear) < 1e-14);
event_side = zeros(nt,1); for ei = event_idx.', event_side(ei) = 1; end
init_res = norm([dae.dae_f(dae.init.x0,dae.init.y0); dae.dae_g(dae.init.x0,dae.init.y0,Ypre)], inf);
res = struct('t',ares.t,'delta',delta_hist,'omega',omega_hist, ...
    'Pe_pu',Pe_hist,'Pe_MW',Pe_hist*dae.base.S_base_MVA, ...
    'Vbus',Vbus_hist,'pf',dae.pf,'bus_ids',dae.bus_ids,'gen_buses',dae.gen_buses, ...
    'H',dae.units.H_system(:),'D',dae.units.D_system(:),'Pm',dae.init.Tm, ...
    'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'fault_bus',opt.fault_bus,'t_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'model','emf6','model_key','emf6','engine','stability.synchronous_emf6_ssa', ...
    'omega_is_deviation',true,'initial_dae_residual',init_res, ...
    'corrector_mode','adaptive','corrector_iterations',corr_iters, ...
    'corrector_residual',corr_residual,'corrector_update_norm',corr_update, ...
    'corrector_converged',corr_converged,'max_corrector_iterations_used',max(corr_iters), ...
    'max_corrector_residual',max(corr_residual),'nonconverged_step_count',nonconv, ...
    'event_idx',event_idx,'event_side',event_side, ...
    'load_model',dae.load_model,'case_name',dae.case_name, ...
    'freq_Hz',dae.base.frequency_Hz, ...
    'stepper','adaptive','dt_nominal',ares.dt_nominal, ...
    'dt_history',ares.dt_history,'lte_history',ares.lte_history, ...
    'accepted_steps',ares.accepted_steps,'rejected_steps',ares.rejected_steps, ...
    'rejection_history',ares.rejection_history,'event_diagnostics',ares.event_diagnostics, ...
    'p',ares.p,'q',ares.q,'denominator',ares.denominator, ...
    'controller_exponent',ares.controller_exponent, ...
    'integrator',integrator, ...
    'integrator_algebraic_residual',zeros(nt-1,1), ...
    'max_integrator_algebraic_residual',0);
res.metadata = stability.ts_method_metadata(integrator, integrator_source, 'built_in_string');
end

