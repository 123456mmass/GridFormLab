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

% --- Algebraic network solver: solve dae_g(x,.,Y) = 0 for y ----------------
g_tol = 1e-12;            % tight, so no-fault equilibrium is preserved
jac_y = jac_y_fd(x,y,Ypre,dae_g,nb);
Ycur = Ypre;

set_topo = @(tnow) topology_at(tnow, opt, Ypre, Yfault, Ypost);
for it = 1:nt-1
    dt_step = dt_arr(it);
    t_now = t(it); t_next = t(it+1);
    Y_now  = set_topo(t_now);
    Y_next = set_topo(t_next);
    jac_y = jac_y_fd(x,y,Y_now,dae_g,nb); Ycur = Y_now;

    % Consistent algebraic state at current x (seed with previous y).
    y = solve_g(x, y, Y_now, dae_g, jac_y, g_tol);
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
    step = stability.ts_step_kernel(x,y,dt_step,dae_f,dae_g,Y_now,jac_y,kopt);
    corr_iters(it) = step.corrector_iterations;
    corr_residual(it) = step.corrector_residual;
    corr_update(it) = step.corrector_update;
    corr_converged(it) = step.corrector_converged;
    if ~step.corrector_converged
        nonconv = nonconv + 1;
        if strcmp(cfail,'error') && strcmp(cmode,'adaptive')
            error('ts_simulate_emf6:correctorNotConverged', ...
                'Corrector did not converge at t=%.4f (step %d): residual=%.3e.', ...
                t_next, it, step.corrector_residual);
        end
    end
    x = step.x_full; jac_y = jac_y_fd(x,step.y_full,Y_next,dae_g,nb); y = solve_g(x, step.y_full, Y_next, dae_g, jac_y, g_tol);
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
    'freq_Hz',dae.base.frequency_Hz);
end

% =========================================================================
function Y = topology_at(tnow, opt, Ypre, Yfault, Ypost)
if tnow < opt.t_fault,        Y = Ypre;
elseif tnow < opt.t_clear,    Y = Yfault;
else,                         Y = Ypost; end
end

function tf = equalY(A,B)
tf = isequal(size(A),size(B)) && max(abs(A(:)-B(:)),[],'all') == 0;
end

function y = solve_g(x, y0, Y, dae_g, Jyy, tol)
% Damped Newton on dae_g(x,y,Y) = 0.  y is the algebraic (voltage) state.
y = y0(:);
for k = 1:30
    g = dae_g(x, y, Y);
    ng = norm(g, inf);
    if ng <= tol, return; end
    step = -(Jyy \ g);
    if any(~isfinite(step)), return; end
    % Line search to keep the residual decreasing.
    alpha = 1; accepted = false;
    while alpha >= 2^-16
        yt = y + alpha*step;
        gt = dae_g(x, yt, Y);
        if all(isfinite(gt)) && norm(gt,inf) < ng, y = yt; accepted = true; break; end
        alpha = alpha/2;
    end
    if ~accepted, return; end
end
end

function J = jac_y_fd(x, y, Y, dae_g, nb)
% Central finite-difference Jacobian of dae_g w.r.t. y (network voltages).
ny = 2*nb; J = complex(zeros(ny));
g0 = dae_g(x, y, Y);
for j = 1:ny
    h = 1e-7*(1 + abs(y(j)));
    yp = y; ym = y; yp(j) = yp(j) + h; ym(j) = ym(j) - h;
    J(:,j) = (dae_g(x, yp, Y) - dae_g(x, ym, Y)) / (2*h);
end
% Guard against an all-zero column (degenerate bus).
J = J + 1e-14*eye(ny);
end
