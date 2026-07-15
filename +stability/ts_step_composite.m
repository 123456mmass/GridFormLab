function step = ts_step_composite(x0,y0,h,dae,Ynet,u,event_context,active_indices,opt)
%TS_STEP_COMPOSITE Canonical coupled-trapezoidal step for a composite DAE.
%   STEP = stability.ts_step_composite(X0,Y0,H,DAE,YNET,U,EC,ACTIVE,OPT)
%   solves the active differential rows and the configured algebraic rows in
%   one damped Newton system. Both ts_simulate_composite and the IBR event
%   supervisor call this function; no second composite trapezoidal residual or
%   FD Jacobian is permitted.

arguments
    x0 (:,1) double
    y0 (:,1) double
    h (1,1) double {mustBePositive,mustBeFinite}
    dae struct
    Ynet double
    u (:,1) double
    event_context struct
    active_indices double
    opt struct = struct()
end

tol = option_value(opt,'newton_tol',1e-8);
max_iter = option_value(opt,'max_iter',50);
fd_eps = option_value(opt,'fd_eps',3e-6);
verbose = logical(option_value(opt,'verbose',false));
full_kcl = logical(option_value(opt,'full_kcl',true));
t_now = option_value(opt,'t_now',0.0);

nx = numel(x0);
ny = numel(y0);
active_indices = active_indices(:)';
if any(~isfinite(active_indices)) || any(active_indices~=fix(active_indices)) || ...
        any(active_indices<1) || any(active_indices>nx) || ...
        numel(unique(active_indices))~=numel(active_indices)
    error('ts_step_composite:badActiveStates', ...
        'active_indices must contain unique in-range integers.');
end
frozen_indices = setdiff(1:nx,active_indices,'stable');

if full_kcl
    vcon_vars = [];
    vcon_ref = [];
    free_vars = 1:ny;
    free_rows = 1:ny;
else
    if ~isfield(opt,'vcon_vars') || ~isfield(opt,'vcon_ref') || ...
            ~isfield(opt,'free_vars') || ~isfield(opt,'free_rows')
        error('ts_step_composite:missingVcon', ...
            'Reduced-KCL stepping requires vcon/free variable metadata.');
    end
    vcon_vars = opt.vcon_vars(:)';
    vcon_ref = opt.vcon_ref(:);
    free_vars = opt.free_vars(:)';
    free_rows = opt.free_rows(:)';
end

f0 = dae.dae_f(t_now,x0,y0,u,event_context);
if any(~isfinite(f0))
    error('ts_step_composite:nonFiniteRhs', ...
        'The composite pre-step RHS contains NaN or Inf.');
end
z0 = [x0(active_indices);y0(free_vars)];
residual_fn = @(z) coupled_residual(z,x0,f0,h,active_indices, ...
    frozen_indices,free_vars,free_rows,vcon_vars,vcon_ref,ny,dae,Ynet,u, ...
    event_context,full_kcl,t_now+h);
jacobian_fn = @(z) forward_fd(z,residual_fn,fd_eps);
[z_sol,niter,ok,residual_norm,rcond_val] = stability.composite_newton( ...
    z0,residual_fn,jacobian_fn,tol,max_iter,verbose);

x1 = x0;
y1 = zeros(ny,1);
y1(vcon_vars) = vcon_ref;
if ok
    na = numel(active_indices);
    x1(active_indices) = z_sol(1:na);
    y1(free_vars) = z_sol(na+1:end);
else
    y1 = y0;
end

step = struct('x_full',x1,'y_full',y1,'converged',ok, ...
    'iterations',niter,'residual_norm',residual_norm,'rcond',rcond_val, ...
    'active_state_indices',active_indices, ...
    'frozen_state_indices',frozen_indices,'finite', ...
    all(isfinite(x1)) && all(isfinite(y1)) && isfinite(residual_norm));
end

function r = coupled_residual(z,x0,f0,h,active,frozen,free_vars,free_rows, ...
    vcon_vars,vcon_ref,ny,dae,Ynet,u,event_context,full_kcl,t_next)
na = numel(active);
x1 = x0;
x1(active) = z(1:na);
% FROZEN is intentionally retained for contract clarity: x1 begins at x0,
% so every frozen coordinate remains an exact hold.
if any(x1(frozen)~=x0(frozen))
    error('ts_step_composite:frozenStateDrift', ...
        'A frozen composite state changed during residual reconstruction.');
end
y1 = zeros(ny,1);
y1(vcon_vars) = vcon_ref;
y1(free_vars) = z(na+1:end);
f1 = dae.dae_f(t_next,x1,y1,u,event_context);
g1 = dae.dae_g(t_next,x1,y1,Ynet,u,event_context);
rx_full = x1-x0-0.5*h*(f0+f1);
if full_kcl
    rg = g1;
else
    rg = g1(free_rows);
end
r = [rx_full(active);rg(:)];
end

function J = forward_fd(z,residual_fn,fd_eps)
r0 = residual_fn(z);
J = zeros(numel(r0),numel(z));
for j = 1:numel(z)
    zp = z;
    zp(j) = zp(j)+fd_eps;
    J(:,j) = (residual_fn(zp)-r0)/fd_eps;
end
end

function value = option_value(opt,name,default)
value = default;
if isfield(opt,name) && ~isempty(opt.(name))
    value = opt.(name);
end
end
