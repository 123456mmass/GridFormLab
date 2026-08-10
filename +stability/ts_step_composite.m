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
% Domain-preserving line search is opt-in. Only the hybrid IBR TS caller
% sets this flag; ts_simulate_composite, equilibrium, and SSSA callers use
% the default-off path so their behavior is unchanged.
domain_preserving = logical(option_value(opt,'domain_preserving_trials',false));
integration_method=lower(string(option_value(opt,'integration_method','trapezoidal')));
state_predictor=lower(string(option_value(opt,'state_predictor','hold')));
if ~isscalar(integration_method) || ...
        ~ismember(integration_method,["trapezoidal","backward_euler"])
    error('ts_step_composite:badIntegrationMethod', ...
        'integration_method must be trapezoidal or backward_euler.');
end
if ~isscalar(state_predictor) || ...
        ~ismember(state_predictor,["hold","explicit_euler", ...
        "explicit_euler_kcl","linear_kcl"])
    error('ts_step_composite:badStatePredictor', ...
        ['state_predictor must be hold, explicit_euler, ' ...
         'explicit_euler_kcl, or linear_kcl.']);
end

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
x_guess=x0(active_indices);
y_guess=y0(free_vars);
if state_predictor=="explicit_euler" || ...
        state_predictor=="explicit_euler_kcl" || state_predictor=="linear_kcl"
    % NUMERICAL_METHOD predictor only: it changes the Newton initial guess,
    % never the trapezoidal/BE residual or acceptance tolerance.  This is
    % valuable for fast angle states after a bumpless multi-GFM transfer.
    trial=x_guess+h*f0(active_indices);
    if state_predictor=="linear_kcl" && isfield(opt,'x_predictor') && ...
            isnumeric(opt.x_predictor) && numel(opt.x_predictor)==nx && ...
            all(isfinite(opt.x_predictor(:)))
        trial=opt.x_predictor(active_indices);
    end
    if all(isfinite(trial))
        x_guess=trial;
        if (state_predictor=="explicit_euler_kcl" || ...
                state_predictor=="linear_kcl") && full_kcl
            x_pred=x0; x_pred(active_indices)=x_guess;
            g_pred=@(xx,yy,YY) dae.dae_g(t_now+h,xx,yy,YY,u,event_context);
            try
                [yp,ainfo]=stability.ts_algebraic_solve( ...
                    x_pred,y0,Ynet,g_pred,@stability.ts_jac_y_fd,tol);
                if ainfo.converged && all(isfinite(yp)), y_guess=yp(free_vars); end
            catch
                % Predictor failure is not a step failure. Fall back to the
                % accepted algebraic state; the coupled residual/gate below
                % remains the sole acceptance authority.
                x_guess=x0(active_indices);
                y_guess=y0(free_vars);
            end
        end
    end
end
z0 = [x_guess;y_guess];
residual_fn = @(z) coupled_residual(z,x0,f0,h,active_indices, ...
    frozen_indices,free_vars,free_rows,vcon_vars,vcon_ref,ny,dae,Ynet,u, ...
    event_context,full_kcl,t_now+h,integration_method);
jacobian_fn=@(z) forward_fd(z,residual_fn,fd_eps);
newton_opt = struct();
if domain_preserving
    newton_opt.trial_exception_classifier = @trial_domain_classifier;
    newton_opt.trial_exception_diagnostic = @(z_trial,me) ...
        trial_domain_diagnostic(z_trial,me,active_indices,free_vars, ...
        vcon_vars,vcon_ref,ny,dae,event_context);
end
[z_sol,niter,ok,residual_norm,rcond_val,~,newton_info] = ...
    stability.composite_newton(z0,residual_fn,jacobian_fn,tol,max_iter, ...
    verbose,newton_opt);
terminal_residual=residual_fn(z_sol);
na=numel(active_indices);
candidate_x=x0;
candidate_x(active_indices)=z_sol(1:na);
candidate_y=zeros(ny,1);
candidate_y(vcon_vars)=vcon_ref;
candidate_y(free_vars)=z_sol(na+1:end);

x1 = x0;
y1 = zeros(ny,1);
y1(vcon_vars) = vcon_ref;
if ok
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
% Additive diagnostics (default-off path publishes zero/empty counters so
% every caller sees a stable shape).
step.newton_info = newton_info;
step.domain_rejected_trials = newton_info.domain_rejected_trials;
step.terminal_residual_vector=terminal_residual;
step.terminal_candidate_x=candidate_x;
step.terminal_candidate_y=candidate_y;
end

function r = coupled_residual(z,x0,f0,h,active,frozen,free_vars,free_rows, ...
    vcon_vars,vcon_ref,ny,dae,Ynet,u,event_context,full_kcl,t_next,method)
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
if method=="backward_euler"
    rx_full=x1-x0-h*f1;
else
    rx_full=x1-x0-0.5*h*(f0+f1);
end
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

% =========================================================================
function tf = trial_domain_classifier(me)
%TRIAL_DOMAIN_CLASSIFIER  Exact-ID predicate for line-search trial throws.
%   Returns true ONLY for the confirmed RMS10 runtime low-voltage domain
%   violation. Every other exception (including the constructor/equilibrium
%   voltageOutsideValidityDomain ID and all hard errors) returns false so
%   composite_newton rethrows it unchanged.
tf = strcmp(me.identifier, 'ibr:gfl_rms10_model:lowVoltagePowerInversion');
end

% =========================================================================
function diag = trial_domain_diagnostic(z_trial, ~, active, free_vars, ...
    vcon_vars, vcon_ref, ny, dae, event_context)
%TRIAL_DOMAIN_DIAG  Pure read-only attribution of a rejected trial.
%   Reconstructs y_trial from z_trial using the SAME mapping as
%   coupled_residual, then scans online RMS10-backed devices whose runtime
%   mode is 'gfl' and reports every device whose terminal |V| is below its
%   own configured runtime minimum. No dae_f/dae_g/reconstruct/current_injection
%   callback is invoked; no state is mutated.
na = numel(active);
y_trial = zeros(ny,1);
if ~isempty(vcon_vars)
    y_trial(vcon_vars) = vcon_ref(:);
end
y_trial(free_vars) = z_trial(na+1:end);

violating = repmat(struct('device_id','','bus_id',0,'bus_position',0, ...
    'trial_voltage',NaN,'runtime_min_voltage',NaN), 0);
min_v = NaN;
nd = numel(dae.devices);
for k = 1:nd
    dev = dae.devices(k);
    bp = dev.bus_position;
    if numel(y_trial) < 2*bp, continue; end
    Vmag = abs(complex(y_trial(2*bp-1), y_trial(2*bp)));
    if ~isfinite(Vmag), continue; end
    [is_online, active_mode] = resolve_runtime_mode(dev, event_context);
    if ~is_online || ~strcmp(active_mode,'gfl'), continue; end
    threshold = read_runtime_min_voltage(dev);
    if ~isfinite(threshold), continue; end
    if Vmag < threshold
        violating(end+1) = struct( ...
            'device_id', char(dev.device_id), ...
            'bus_id', dev.bus_id, ...
            'bus_position', bp, ...
            'trial_voltage', Vmag, ...
            'runtime_min_voltage', threshold); %#ok<AGROW>
        if ~isfinite(min_v) || Vmag < min_v
            min_v = Vmag;
        end
    end
end
diag = struct( ...
    'violating_devices', violating, ...
    'minimum_trial_voltage', min_v);
end

function [is_online, active_mode] = resolve_runtime_mode(dev, event_context)
%RESOLVE_RUNTIME_MODE  Read the runtime online/mode for a device without
%   invoking any device callback. Mirrors dual_mode_ibr_model.resolve_status
%   semantics: runtime hybrid_state takes precedence over constructor
%   defaults; an offline device is never a violator.
is_online = true;
active_mode = '';
if isfield(dev,'initial_online') && ~isempty(dev.initial_online)
    is_online = logical(dev.initial_online);
end
if isfield(dev,'initial_mode') && ~isempty(dev.initial_mode)
    active_mode = char(dev.initial_mode);
end
if isempty(event_context) || ~isstruct(event_context) || ...
        ~isfield(event_context,'hybrid_state') || ...
        ~isstruct(event_context.hybrid_state)
    return;
end
hs = event_context.hybrid_state;
if ~isfield(dev,'device_id'), return; end
key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
if isfield(hs,'device_online') && isstruct(hs.device_online) && ...
        isfield(hs.device_online,key)
    is_online = logical(hs.device_online.(key));
end
if isfield(hs,'device_modes') && isstruct(hs.device_modes) && ...
        isfield(hs.device_modes,key)
    raw = hs.device_modes.(key);
    if ischar(raw) || (isstring(raw) && isscalar(raw))
        active_mode = char(raw);
    end
end
end

function threshold = read_runtime_min_voltage(dev)
%READ_RUNTIME_MIN_VOLTAGE  Read the configured RMS10 runtime V_div_min from
%   device provenance. Standalone RMS10 exposes provenance.params.V_div_min;
%   the dual-mode wrapper forwards it as provenance.gfl_runtime_min_voltage.
%   Returns NaN if absent so the caller skips attribution for that device.
threshold = NaN;
if ~isfield(dev,'provenance') || ~isstruct(dev.provenance)
    return;
end
p = dev.provenance;
if isfield(p,'gfl_runtime_min_voltage') && isscalar(p.gfl_runtime_min_voltage) && ...
        isfinite(p.gfl_runtime_min_voltage)
    threshold = p.gfl_runtime_min_voltage;
    return;
end
if isfield(p,'params') && isstruct(p.params) && ...
        isfield(p.params,'V_div_min') && isscalar(p.params.V_div_min) && ...
        isfinite(p.params.V_div_min)
    threshold = p.params.V_div_min;
end
end
