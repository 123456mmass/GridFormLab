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
% FD perturbation rule. 'absolute' (default) perturbs every unknown by the
% same fd_eps, which is the historical behavior of this kernel and is what
% every existing caller gets. 'scaled' uses the rule this repository already
% derived for the coupled Jacobian in stability.ts_coupled_jacobian
% (:32-51), h_j = fd_eps*(1+|z_j|), so a state whose magnitude is far from
% unity is perturbed proportionally instead of being over- or under-resolved.
% The choice is a NUMERICAL_METHOD option only; it changes no equation, no
% state order and no acceptance gate. Opt-in per caller.
fd_perturbation = lower(string(option_value(opt,'fd_perturbation','absolute')));
if ~isscalar(fd_perturbation) || ...
        ~ismember(fd_perturbation,["absolute","scaled"])
    error('ts_step_composite:badFdPerturbation', ...
        'fd_perturbation must be absolute or scaled.');
end
% FD column grouping. 'auto' asks stability.ts_fd_column_groups for the
% structurally disjoint grouping of the state columns and falls back to one
% column per group when the structure cannot be established; 'off' forces the
% historical per-column construction. Both build the same dense Jacobian.
% 'fd_structure_check' additionally rebuilds the Jacobian per column and
% requires exact equality — expensive, for verification runs and tests.
fd_grouping = lower(string(option_value(opt,'fd_grouping','auto')));
fd_structure_check = logical(option_value(opt,'fd_structure_check',false));
if ~isscalar(fd_grouping) || ~ismember(fd_grouping,["auto","off"])
    error('ts_step_composite:badFdGrouping', ...
        'fd_grouping must be auto or off.');
end
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
if fd_grouping == "off"
    nz0 = numel(z0);
    fd_groups = num2cell(1:nz0);
    fd_rowsets = repmat({{}},1,nz0);
    fd_info = struct('grouped',false,'n_groups',nz0, ...
        'n_state_groups',numel(active_indices), ...
        'n_state_columns',numel(active_indices), ...
        'fallback_reason','disabled_by_option');
else
    [fd_groups,fd_rowsets,fd_info] = stability.ts_fd_column_groups( ...
        dae,active_indices,numel(free_vars),full_kcl);
end
if fd_perturbation == "absolute"
    % Scalar step: forward_fd takes the byte-for-byte historical path.
    jacobian_fn=@(z) forward_fd(z,residual_fn,fd_eps,fd_groups,fd_rowsets, ...
        fd_structure_check);
else
    jacobian_fn=@(z) forward_fd(z,residual_fn,fd_eps*(1+abs(z)), ...
        fd_groups,fd_rowsets,fd_structure_check);
end
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
step.fd_column_groups = fd_info;
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

function J = forward_fd(z,residual_fn,fd_eps,groups,rowsets,structure_check)
%FORWARD_FD  Dense forward-difference Jacobian of the coupled residual.
%   GROUPS partitions the columns; every column of one group is perturbed in
%   the same residual evaluation. For a singleton group the whole difference
%   vector becomes that column, which is byte-for-byte the historical
%   per-column construction. For a multi-column group each member takes only
%   its own residual rows: by the derivation in
%   stability.ts_fd_column_groups those rows are computed from inputs that do
%   not include the other members' perturbations, and every row outside all
%   members' row sets is an exact zero in both constructions.
%
%   FD_EPS is either a scalar step applied to every column (the historical
%   absolute rule) or a length-numel(z) vector of per-column steps. With a
%   scalar the arithmetic below is the same expression in the same order as
%   the scalar-only version, so the Jacobian is bit-identical.
r0 = residual_fn(z);
nz = numel(z);
J = zeros(numel(r0),nz);
scalar_step = isscalar(fd_eps);
for gi = 1:numel(groups)
    cols = groups{gi};
    if scalar_step
        hc = fd_eps;
    else
        hc = fd_eps(cols);
    end
    zp = z;
    zp(cols) = zp(cols)+hc;
    if isscalar(cols)
        J(:,cols) = (residual_fn(zp)-r0)/hc;
    else
        dr = residual_fn(zp)-r0;
        rs = rowsets{gi};
        for m = 1:numel(cols)
            rws = rs{m};
            if scalar_step
                J(rws,cols(m)) = dr(rws)/hc;
            else
                J(rws,cols(m)) = dr(rws)/hc(m);
            end
        end
    end
end
if structure_check
    Jref = zeros(numel(r0),nz);
    for j = 1:nz
        if scalar_step
            hj = fd_eps;
        else
            hj = fd_eps(j);
        end
        zp = z;
        zp(j) = zp(j)+hj;
        Jref(:,j) = (residual_fn(zp)-r0)/hj;
    end
    if ~isequal(J,Jref)
        error('ts_step_composite:fdGroupingMismatch', ...
            ['Grouped FD Jacobian differs from the per-column Jacobian ' ...
             '(max abs difference %.17g). The structural derivation in ' ...
             'stability.ts_fd_column_groups does not hold for this model.'], ...
            max(abs(J(:)-Jref(:))));
    end
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
%   Returns true ONLY for a confirmed MODEL DOMAIN BOUNDARY that a line-search
%   trial can cross while the accepted iterate stays physical. Every other
%   exception (including the constructor/equilibrium
%   voltageOutsideValidityDomain ID and all hard errors) returns false so
%   composite_newton rethrows it unchanged.
%
%   The registered boundaries, and why each one belongs here:
%     ibr:gfl_rms10_model:lowVoltagePowerInversion
%       The RMS10 GFL constitutive law inverts below its runtime minimum
%       terminal voltage.
%     ibr:dc_source_thevenin:dcVoltage
%       The DC bus carries a constant-power load, so the link equation has the
%       term P_ac/V_dc, which is singular at V_dc = 0. A trial iterate with
%       V_dc <= 0 is outside the model domain, not a solution the step may
%       accept. Shortening the trial is the correct response; widening the
%       guard so 1/V_dc is evaluated anyway would be a silent fallback.
%
%   This predicate does NOT weaken any gate. A violation at an ACCEPTED state
%   is thrown outside this try/catch and still aborts the step, and
%   composite_newton never assigns the accepted iterate, its residual or its
%   Jacobian from a rejected trial (composite_newton.m:132-136).
DOMAIN_BOUNDARY_IDS = { ...
    'ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
    'ibr:dc_source_thevenin:dcVoltage'};
tf = any(strcmp(me.identifier, DOMAIN_BOUNDARY_IDS));
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
