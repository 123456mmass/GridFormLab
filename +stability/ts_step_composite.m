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
% --- Limiter-regime freezing (opt-in) ------------------------------------
% The IBR current limiter and its anti-windup are BRANCH SWITCHES that the
% device RHS re-decides on every call. A coupled Newton solve therefore
% evaluates a residual whose identity can change between the base point, the FD
% perturbation points and the line-search trials: Jacobian columns are then
% assembled across a branch boundary and the search direction is a Newton
% direction for neither branch. Measured at the sg_fault_bus9 wall
% (docs/project/defects/2026-09-03-scenario-suite-adaptive-dtmin-nonsmooth-wall.md):
% 2 of 46 state perturbations and 1 of 28 algebraic perturbations flip IBR2's
% two hold booleans at the last accepted state, and at no earlier state.
%
% When enabled this runs the active-set pattern stability.active_bound_run
% already uses for the equilibrium solve: freeze each device's branch, solve to
% convergence on that single smooth residual, reclassify at the solution, and
% repeat while the classification keeps changing, up to a declared cap. Nothing
% about newton_tol, kcl_tol, the LTE gate or the fail-closed policy changes --
% the step is accepted or rejected by exactly the same authority. A solve that
% never settles returns the LAST attempt's outcome, so the caller sees an
% ordinary non-convergence and its halving/fail-closed path is untouched.
% Default off: byte-identical to the historical single solve.
limiter_freeze_enabled = logical(option_value(opt,'limiter_regime_freeze',false));
limiter_freeze_max_outer = option_value(opt,'limiter_regime_max_outer',4);
if ~isnumeric(limiter_freeze_max_outer) || ~isscalar(limiter_freeze_max_outer) || ...
        ~isfinite(limiter_freeze_max_outer) || limiter_freeze_max_outer < 1 || ...
        limiter_freeze_max_outer ~= fix(limiter_freeze_max_outer)
    error('ts_step_composite:badLimiterMaxOuter', ...
        'limiter_regime_max_outer must be a positive integer.');
end
limiter_freeze_enabled = limiter_freeze_enabled && ...
    isfield(dae,'limiter_regime') && isa(dae.limiter_regime,'function_handle');
% Residual builder parameterised by the event context, so a frozen-branch solve
% reuses this EXACT construction with only the freeze added. The live-context
% residual below is the historical one, expression for expression.
make_residual = @(ec) @(z) coupled_residual(z,x0,f0,h,active_indices, ...
    frozen_indices,free_vars,free_rows,vcon_vars,vcon_ref,ny,dae,Ynet,u, ...
    ec,full_kcl,t_now+h,integration_method);
residual_fn = make_residual(event_context);
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
    make_jacobian = @(rfn) @(z) forward_fd(z,rfn,fd_eps,fd_groups,fd_rowsets, ...
        fd_structure_check);
else
    make_jacobian = @(rfn) @(z) forward_fd(z,rfn,fd_eps*(1+abs(z)), ...
        fd_groups,fd_rowsets,fd_structure_check);
end
jacobian_fn = make_jacobian(residual_fn);
make_newton_opt = @(ec) newton_options(domain_preserving,active_indices, ...
    free_vars,vcon_vars,vcon_ref,ny,dae,ec);
newton_opt = make_newton_opt(event_context);
na = numel(active_indices);
if ~limiter_freeze_enabled
    [z_sol,niter,ok,residual_norm,rcond_val,~,newton_info] = ...
        stability.composite_newton(z0,residual_fn,jacobian_fn,tol,max_iter, ...
        verbose,newton_opt);
    limiter_info = struct('enabled',false,'outer_iterations',0, ...
        'settled',true,'regime_changes',0,'frozen_solves',0);
else
    % Outer active-set loop over the limiter branch. Each pass solves a single
    % SMOOTH residual (the branch held fixed), then reclassifies at that
    % solution on the LIVE branch. Settling means the solution's own branch is
    % the one it was solved under -- at which point the frozen residual and the
    % live residual are the same function at that point, so the reported
    % convergence is convergence of the true switched residual, at the same
    % newton_tol. Not settling is reported as non-convergence: the caller's
    % halving and fail-closed policy then applies unchanged. No gate moves.
    z_c = z0;
    outer_iters = 0;
    settled = false;
    n_changes = 0;
    n_solves = 0;
    ok = false; residual_norm = inf; rcond_val = NaN;
    newton_info = struct('domain_rejected_trials',0,'line_search_exhausted',false, ...
        'residual_before_line_search',inf,'final_tested_alpha',NaN, ...
        'minimum_trial_voltage',NaN,'final_domain_violation',[], ...
        'minimum_voltage_violation',[]);
    for outer = 1:limiter_freeze_max_outer
        frz = freeze_from_regime(limiter_regime_at(dae,t_now+h,x0,z_c, ...
            active_indices,vcon_vars,vcon_ref,free_vars,ny,u,event_context), ...
            blend_from_context(event_context));
        ec_frozen = event_context;
        ec_frozen.limiter_freeze = frz;
        rfn = make_residual(ec_frozen);
        [z_new,ni,ok,residual_norm,rcond_val,~,newton_info] = ...
            stability.composite_newton(z_c,rfn,make_jacobian(rfn),tol, ...
            max_iter,verbose,make_newton_opt(ec_frozen));
        outer_iters = outer_iters + ni;
        n_solves = n_solves + 1;
        z_c = z_new;
        if ~ok, break; end
        frz_at_solution = freeze_from_regime(limiter_regime_at(dae,t_now+h, ...
            x0,z_c,active_indices,vcon_vars,vcon_ref,free_vars,ny,u, ...
            event_context), blend_from_context(event_context));
        if isequal(frz_at_solution,frz)
            settled = true;
            break;
        end
        n_changes = n_changes + 1;
    end
    z_sol = z_c;
    niter = outer_iters;
    % A converged frozen solve whose branch does not match its own solution has
    % NOT solved the switched residual. Report it as non-convergence rather than
    % accept a root of a different equation.
    ok = ok && settled;
    limiter_info = struct('enabled',true,'outer_iterations',outer_iters, ...
        'settled',settled,'regime_changes',n_changes,'frozen_solves',n_solves);
end
terminal_residual=residual_fn(z_sol);
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
step.limiter_regime_info = limiter_info;
step.domain_rejected_trials = newton_info.domain_rejected_trials;
step.fd_column_groups = fd_info;
step.terminal_residual_vector=terminal_residual;
step.terminal_candidate_x=candidate_x;
step.terminal_candidate_y=candidate_y;
end

function opt_out = newton_options(domain_preserving,active_indices,free_vars, ...
    vcon_vars,vcon_ref,ny,dae,event_context)
%NEWTON_OPTIONS  The composite_newton option struct for one event context.
%   Factored out so the frozen-branch solves build it exactly as the live solve
%   does, with the domain diagnostics bound to the SAME context the residual
%   uses. Default-off path is unchanged: an empty struct.
opt_out = struct();
if domain_preserving
    opt_out.trial_exception_classifier = @trial_domain_classifier;
    opt_out.trial_exception_diagnostic = @(z_trial,me) ...
        trial_domain_diagnostic(z_trial,me,active_indices,free_vars, ...
        vcon_vars,vcon_ref,ny,dae,event_context);
end
end

function reg = limiter_regime_at(dae,t_next,x0,z,active,vcon_vars,vcon_ref, ...
    free_vars,ny,u,event_context)
%LIMITER_REGIME_AT  The live (unfrozen) limiter regime at the iterate Z.
%   Reconstructs x/y from Z exactly as coupled_residual does, then asks the
%   composite for each device's branch. The event context passed in is the
%   caller's own, i.e. WITHOUT any freeze, so this always reports the true
%   switched-system branch and can be used to test whether a frozen solution is
%   self-consistent.
na = numel(active);
x1 = x0;
x1(active) = z(1:na);
y1 = zeros(ny,1);
y1(vcon_vars) = vcon_ref;
y1(free_vars) = z(na+1:end);
reg = dae.limiter_regime(t_next,x1,y1,u,event_context);
end

function frz = freeze_from_regime(reg,blend)
%FREEZE_FROM_REGIME  Reduce a regime report to the freeze the models consume.
%   Keeps only the two hold booleans plus the controller branch that produced
%   them, so a freeze is never silently applied to the other branch after a mode
%   transfer. Devices whose report lacks the fields are omitted, which leaves
%   them on their live branch. When the anti-windup BLEND is active the switch
%   is continuous, so held-at-one has margin there is no sliding value to cross:
%   partially-held rows are reported at their frozen blend fraction, and a freeze
%   omits them (the live blend applies inside every solve).
if nargin<2 || isempty(blend), blend=0; end
frz = struct();
if ~isstruct(reg) || ~isscalar(reg), return; end
keys = fieldnames(reg);
for k = 1:numel(keys)
    c = reg.(keys{k});
    if ~isstruct(c) || ~isscalar(c) || ...
            ~isfield(c,'hold_d') || ~isfield(c,'hold_q'), continue; end
    if blend>0
        part_d = ismember(c.hold_d,[0,1]);
        part_q = ismember(c.hold_q,[0,1]);
        if ~part_d || ~part_q, continue; end
    end
    entry = struct('hold_d',logical(c.hold_d),'hold_q',logical(c.hold_q));
    if isfield(c,'mode'), entry.mode = char(string(c.mode)); end
    frz.(keys{k}) = entry;
end
end

function blend = blend_from_context(event_context)
%BLEND_FROM_CONTEXT  The declared anti-windup blend width, or 0.
%   Mirrors the device models' reader so the freeze machinery uses exactly the
%   same value the RHS uses. Absent (every historical caller) is 0.
blend = 0;
if isempty(event_context) || ~isstruct(event_context) || ...
        ~isfield(event_context,'anti_windup_blend'), return; end
v = event_context.anti_windup_blend;
if isnumeric(v) && isscalar(v) && isfinite(v) && v>=0, blend = double(v); end
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
