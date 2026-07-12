function res = ts_simulate(case_data, varargin)
%TS_SIMULATE General classical transient-stability engine.
%   RES = ts_simulate(CASE) runs a classical (2nd-order) transient stability
%   simulation for ANY case returned by a +cases/ loader. The engine is
%   case-agnostic: add a new case in +cases/ and it runs with no engine edit.
%
%   CASE accepted formats:
%     (a) MATPOWER-style:  CASE.mpc  (bus/branch/gen/baseMVA), optionally
%                          CASE.machines (struct array: bus,H,D,Xdp,model).
%                          If .machines is absent, classical defaults
%                          H=5, D=0, Xdp=0.3 are used.
%     (b) Kundur-style:    CASE.bus_data, CASE.line_data, CASE.machines.units,
%                          CASE.base_values  (machine base converted to the
%                          system base automatically).
%
%   OPT fields: t_end, dt, fault_bus, t_fault, t_clear, Zf, method,
%               corrector_iter, pm_mode ('balanced'|'pfpg'), verbose.
%
%   The classical path is independently cross-validated against PSAT and
%   PGAz on IEEE 14-bus. Higher-order models (4th/6th) plug into this engine
%   via the per-machine .model field (stage 2).

opt = struct('t_end',15.0,'dt',0.01,'fault_bus',[],'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal', ...
    'corrector_mode','adaptive','corrector_iter',[], ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','verbose',true,'H',[],'D',[],'Xdp',[],'model','classical','load_model','cc_p_cz_q', ...
    'fault_enabled',true);
if nargin > 1 && isstruct(varargin{1})
    fn = fieldnames(varargin{1});
    for k=1:numel(fn), opt.(fn{k}) = varargin{1}.(fn{k}); end
end
% --- Backward compatibility: corrector_iter without corrector_mode -------
% If corrector_iter is set but corrector_mode is 'adaptive', switch to
% 'fixed' so old scripts that only set corrector_iter keep working.
if ~isempty(opt.corrector_iter) && strcmp(opt.corrector_mode,'adaptive')
    opt.corrector_mode = 'fixed';
end
% Default corrector_iter for fixed mode
if strcmp(opt.corrector_mode,'fixed') && isempty(opt.corrector_iter)
    opt.corrector_iter = 1;
end

% --- Model dispatch: single entry point for classical and 6th-order -------
% The operational EMF6 model is the single sixth-order equation set shared
% with SSSA (stability.emf6_dae / stability.synchronous_emf6_ssa). The
% legacy calibrated GENTPJ names (flux6/genpj6/kundur6) also route through
% the unified EMF6 path so SSSA and TS never diverge onto a second model.
if any(strcmpi(opt.model,{'padiyar_1_1_avr','padiyar_1_1_manual'}))
    if strcmpi(opt.model,'padiyar_1_1_manual'), opt.excitation='manual'; else, opt.excitation='avr'; end
    if opt.verbose, fprintf('[ts_simulate] Dispatching to Padiyar model 1.1 (%s).\n',opt.excitation); end
    res=stability.ts_simulate_padiyar_model11(case_data,opt);
    return;
elseif strcmpi(opt.model,'emf6')
    if opt.verbose, fprintf('[ts_simulate] Dispatching to EMF6 (emf6_dae) path.\n'); end
    res = stability.ts_simulate_emf6(case_data, opt);
    return;
elseif any(strcmpi(opt.model,{'flux6','genpj6','kundur6'}))
    if opt.verbose
        fprintf('[ts_simulate] Dispatching to EMF6 (emf6_dae) path [legacy alias %s].\n',opt.model);
    end
    res = stability.ts_simulate_emf6(case_data, opt);
    return;
end

[mpc, mach, freq] = normalize_case(case_data);
base = mpc.baseMVA;
ws = 2*pi*freq;

% --- Power flow (in-house Newton) ------------------------------------------
if opt.verbose, fprintf('[ts_simulate] Running PF (%s)...\n', mpc.case_name); end
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false,'plot_results',false, ...
    'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
if ~pf.converged, error('ts_simulate:pfNotConverged','Power flow did not converge.'); end

gen = mpc.gen(mpc.gen(:,8) ~= 0,:);
% Deduplicate generator buses: if mpc.gen has multiple rows at the same
% bus (e.g. raw MATPOWER cases), keep one representative row per bus.
% The classical engine models one equivalent generator per bus.
gbus_raw = gen(:,1);
[gbus, ~, ic] = unique(gbus_raw, 'stable');
ng = numel(gbus); nb = size(mpc.bus,1);
if isempty(opt.fault_bus), opt.fault_bus = gbus(1); end

% --- Machine dynamic data on system base ----------------------------------
[H,D,Xdp] = expand_machines(mach, ng, gbus, mpc.bus(:,1), opt);

if opt.verbose, fprintf('[ts_simulate] Dynamic init (classical, ng=%d)...\n', ng); end
Ybus = build_ybus_from_mpc(mpc);
V0 = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
Sload = (mpc.bus(:,3) + 1i*mpc.bus(:,4))/base;
Yload = conj(Sload)./(abs(V0).^2 + eps);
Ynet = Ybus + diag(Yload);

E0=zeros(ng,1); delta0=zeros(ng,1); Eqmag=zeros(ng,1); Pm=zeros(ng,1);
for k=1:ng
    b=find(mpc.bus(:,1)==gbus(k),1);
    Sg=pf.P_generation(b)+1i*pf.Q_generation(b);
    Ig0=conj(Sg/V0(b));
    E0(k)=V0(b)+1i*Xdp(k)*Ig0;
    delta0(k)=angle(E0(k)); Eqmag(k)=abs(E0(k));
    Pm(k)=real(E0(k)*conj(Ig0));
end

if opt.verbose
    fprintf('[ts_simulate] TS: t_end=%.3f dt=%.4f fault bus %d (%.3f-%.3f s)\n', ...
        opt.t_end,opt.dt,opt.fault_bus,opt.t_fault,opt.t_clear);
    fprintf('[ts_simulate] Corrector: mode=%s', opt.corrector_mode);
    if strcmp(opt.corrector_mode,'adaptive')
        fprintf(' abs_tol=%.1e rel_tol=%.1e max_iter=%d failure=%s\n', ...
            opt.corrector_abs_tol, opt.corrector_rel_tol, ...
            opt.max_corrector_iter, opt.corrector_failure);
    else
        fprintf(' iter=%d\n', opt.corrector_iter);
    end
end

% --- Event-aware time grid -------------------------------------------------
% Ensure t_fault and t_clear fall exactly on the grid so that no
% trapezoidal step straddles two different network topologies.
t_raw = (0:opt.dt:opt.t_end).';
event_times = [];
if isfinite(opt.t_fault) && opt.t_fault > t_raw(1) && opt.t_fault < t_raw(end)
    event_times = [event_times; opt.t_fault];
end
if isfinite(opt.t_clear) && opt.t_clear > t_raw(1) && opt.t_clear < t_raw(end)
    event_times = [event_times; opt.t_clear];
end
% Insert event times into the grid (if not already present)
t = t_raw;
for et = event_times.'
    [~, idx] = min(abs(t - et));
    if abs(t(idx) - et) > opt.dt * 1e-10
        t = sort([t; et]);
    end
end
nt = numel(t);
dt_arr = diff(t);  % actual dt per step (may differ at event boundaries)

% --- Event side tracking --------------------------------------------------
% At an event time, both a left-limit (pre-event) and right-limit
% (post-event) sample exist. We store the post-event value (right limit)
% as the row at that time index. The pre-event value is used only for
% integration up to the event.
event_idx = [];
for et = event_times.'
    event_idx = [event_idx; find(abs(t - et) < opt.dt * 1e-10, 1)];
end
event_side = zeros(nt,1);  % 0 = normal, 1 = event-right (post-switch)
for ei = event_idx.'
    event_side(ei) = 1;
end

delta=zeros(nt,ng); omega=zeros(nt,ng); Pe=zeros(nt,ng); Vhist=zeros(nt,nb);
delta(1,:)=delta0.'; omega(1,:)=ones(1,ng);

% --- Build the classical DAE + strategy (Phase 2) --------------------------
% Route the fixed-step classical path through the shared one-step contract
% (ts_model_strategy('classical',...) + ts_step_kernel). The algebraic contract
% is linear (V=(Y+Ygen)\Iinj), solved exactly inside dae_f; no nonlinear dae_g,
% no Jyy. Bit-identical to the legacy inline corrector verified by
% tests/test_ts_classical_strategy_equivalence.m and tests/test_ts_characterization_fixed.m.
cdae = stability.classical_dae(case_data, opt);
strat = stability.ts_model_strategy('classical', cdae);
Pm = cdae.Pm;

% Fault topology matrices (event-aware, single source: ts_topology_at).
Ypre_da = cdae.Ynet;
Yfault_da = Ypre_da;
if opt.fault_enabled
    fb = find(mpc.bus(:,1)==opt.fault_bus,1);
    Yfault_da(fb,fb) = Yfault_da(fb,fb) + 1/opt.Zf;
end
Ypost_da = Ypre_da;

% --- Stepper dispatch (Phase 6) --------------------------------------------
% opt.stepper='fixed' (default): canonical fixed-step path (bit-identical to
%   the validated baseline).
% opt.stepper='adaptive': variable-dt LTE/reject path via ts_adaptive_driver.
if isfield(opt,'stepper') && strcmpi(opt.stepper,'adaptive')
    res = run_classical_adaptive(opt, cdae, strat, mpc, gbus, base);
    return;
end

% Initial output sample (pre-fault topology).
[V,~,Pe0] = solve_network(delta0,Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp,0,opt);
if strcmpi(opt.pm_mode,'balanced') || strcmpi(opt.pm_mode,'pe0')
    % Pm already set to Pe0 via classical_dae; nothing to redo.
elseif strcmpi(opt.pm_mode,'pfpg') || strcmpi(opt.pm_mode,'pgaz') || strcmpi(opt.pm_mode,'pg')
    % Pm already set from PF generation via classical_dae.
else
    error('ts_simulate:unknownPmMode','Unknown pm_mode "%s".',opt.pm_mode);
end
Pe(1,:)=Pe0.'; Vhist(1,:)=abs(V).';

% --- Corrector diagnostics -------------------------------------------------
corr_iters = zeros(nt-1,1);
corr_residual = zeros(nt-1,1);
corr_update = zeros(nt-1,1);
corr_converged = true(nt-1,1);
nonconv_count = 0;

x=[delta0; ones(ng,1)];
y = cdae.y0(:);
kopt_cl = struct('max_corrector_iter',opt.max_corrector_iter, ...
    'corrector_abs_tol',opt.corrector_abs_tol, ...
    'corrector_rel_tol',opt.corrector_rel_tol, ...
    'corrector_mode',opt.corrector_mode);
if strcmp(opt.corrector_mode,'fixed')
    kopt_cl.max_corrector_iter = opt.corrector_iter;
end

for it=1:nt-1
    dt_step = dt_arr(it);
    t_now = t(it);
    t_next = t(it+1);

    % Topology for this step: the fault status at t_now determines the
    % pre-event topology used for the entire step (no trapezoidal step
    % averages RHS from two topologies). The topology switches at the event
    % boundary; the next step starts with the post-event topology.
    Y_now  = stability.ts_topology_at(t_now,  opt, Ypre_da, Yfault_da, Ypost_da);
    Y_next = stability.ts_topology_at(t_next, opt, Ypre_da, Yfault_da, Ypost_da);

    step = stability.ts_step_kernel(strat, x, y, dt_step, Y_now, kopt_cl);
    corr_iters(it) = step.corrector_iterations;
    corr_residual(it) = step.corrector_residual;
    corr_update(it) = step.corrector_update;
    corr_converged(it) = step.corrector_converged;
    if ~step.corrector_converged
        nonconv_count = nonconv_count + 1;
        % Legacy fixed corrector uses a loose residual check (<= 1e-6) and does
        % NOT raise on non-convergence (only the adaptive corrector errors when
        % corrector_failure='error'). Preserve this behavior bit-identically.
        if strcmp(opt.corrector_mode,'adaptive') && strcmp(opt.corrector_failure, 'error')
            error('ts_simulate:correctorNotConverged', ...
                ['Corrector did not converge at t=%.4f (step %d). ' ...
                'Iterations=%d, update=%.3e, residual=%.3e.'], ...
                t_next, it, step.corrector_iterations, ...
                step.corrector_update, step.corrector_residual);
        end
    end

    x = step.x_full; y = step.y_full;
    delta(it+1,:) = x(1:ng).'; omega(it+1,:) = x(ng+1:end).';

    % Recompute algebraic with the ACTUAL topology at t_next (right-limit V).
    [V,~,Pek] = solve_network(x(1:ng),Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp, ...
        (opt.fault_enabled && t_next >= opt.t_fault && t_next < opt.t_clear), opt);
    Pe(it+1,:) = Pek.'; Vhist(it+1,:) = abs(V).';
end
if opt.verbose
    fprintf('[ts_simulate] TS finished: %d steps, method=%s, mode=%s\n', ...
        nt-1, opt.method, opt.corrector_mode);
    fprintf('[ts_simulate] Corrector: max_iter_used=%d, max_residual=%.3e, nonconv=%d\n', ...
        max(corr_iters), max(corr_residual), nonconv_count);
end

res=struct('t',t,'delta',delta,'omega',omega,'Pe_pu',Pe,'Pe_MW',Pe*base, ...
    'Vbus',Vhist,'pf',pf,'gen_buses',gbus,'H',H,'D',D,'Xdp',Xdp, ...
    'Pm',Pm,'Eqmag',Eqmag,'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'fault_bus',opt.fault_bus,'t_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'model','classical','freq_Hz',freq, ...
    'corrector_mode',opt.corrector_mode, ...
    'corrector_iterations',corr_iters, ...
    'corrector_residual',corr_residual, ...
    'corrector_update_norm',corr_update, ...
    'corrector_converged',corr_converged, ...
    'max_corrector_iterations_used',max(corr_iters), ...
    'max_corrector_residual',max(corr_residual), ...
    'nonconverged_step_count',nonconv_count, ...
    'event_idx',event_idx, 'event_side',event_side);
end

% =========================================================================
function res = run_classical_adaptive(opt, cdae, strat, mpc, gbus, base)
%RUN_CLASSICAL_ADAPTIVE  Phase 6 classical adaptive-step path.
%   Builds the events struct + classical strategy and calls the shared
%   ts_adaptive_driver. Converts the adaptive result to the legacy classical
%   result schema (plus the frozen adaptive fields).
events = struct('fault_enabled',opt.fault_enabled, ...
    't_fault',opt.t_fault,'t_clear',opt.t_clear, ...
    'Ypre',cdae.Ynet,'Yfault',cdae.Ynet,'Ypost',cdae.Ynet);
% Recompute Yfault with the fault admittance (classical uses Ynet + 1/Zf).
if opt.fault_enabled
    fb = find(mpc.bus(:,1)==opt.fault_bus,1);
    Yf = cdae.Ynet;
    Yf(fb,fb) = Yf(fb,fb) + 1/opt.Zf;
    events.Yfault = Yf;
end
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
aopt.max_corrector_iter = opt.max_corrector_iter;
aopt.corrector_abs_tol = opt.corrector_abs_tol;
aopt.corrector_rel_tol = opt.corrector_rel_tol;
aopt.corrector_mode = opt.corrector_mode;
if strcmp(opt.corrector_mode,'fixed') && ~isempty(opt.corrector_iter)
    aopt.corrector_iter = opt.corrector_iter;
end
ares = stability.ts_adaptive_driver(strat, cdae.x0, cdae.y0, ...
    [0, opt.t_end], events, aopt);
nt = numel(ares.t);
res = struct('t',ares.t,'delta',ares.delta,'omega',ares.omega, ...
    'Pe_pu',ares.Pe_pu,'Pe_MW',ares.Pe_pu*base, ...
    'Vbus',ares.Vbus,'pf',cdae.pf,'gen_buses',gbus,'H',cdae.H,'D',cdae.D,'Xdp',cdae.Xdp, ...
    'Pm',cdae.Pm,'Eqmag',cdae.Eqmag,'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'fault_bus',opt.fault_bus,'t_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'model','classical','freq_Hz',cdae.freq, ...
    'corrector_mode',opt.corrector_mode, ...
    'corrector_iterations',zeros(nt-1,1), ...
    'corrector_residual',ares.lte_history(:), ...
    'corrector_update_norm',zeros(nt-1,1), ...
    'corrector_converged',true(nt-1,1), ...
    'max_corrector_iterations_used',0, ...
    'max_corrector_residual',max(ares.lte_history), ...
    'nonconverged_step_count',ares.rejected_steps, ...
    'event_idx',find(abs(ares.t-opt.t_fault)<1e-14|abs(ares.t-opt.t_clear)<1e-14), ...
    'event_side',zeros(nt,1), ...
    'stepper','adaptive','dt_nominal',ares.dt_nominal, ...
    'dt_history',ares.dt_history,'lte_history',ares.lte_history, ...
    'accepted_steps',ares.accepted_steps,'rejected_steps',ares.rejected_steps, ...
    'rejection_history',ares.rejection_history,'event_diagnostics',ares.event_diagnostics);
end

% =========================================================================
function [mpc,mach,freq] = normalize_case(case_data)
% Convert any supported case format to a MATPOWER mpc + system-base machines.
if isfield(case_data,'mpc')
    mpc = case_data.mpc;
    mpc.case_name = 'MATPOWER';
    freq = 60;
    if isfield(case_data,'base_values') && isfield(case_data.base_values,'frequency_Hz')
        freq = case_data.base_values.frequency_Hz;
    end
    mach = [];
    if isfield(case_data,'machines') && ~isempty(case_data.machines) && isstruct(case_data.machines) && isfield(case_data.machines,'units')
        mach = case_data.machines.units;
        % Published machine data (e.g. Kundur) are on machine MVA base,
        % while the classical network solver expects system-base H/D/X'd.
        if isfield(case_data.machines,'base') && ...
                isfield(case_data.machines.base,'S_MVA') && ...
                isfield(case_data.machines,'reactances')
            ratio=case_data.machines.base.S_MVA/mpc.baseMVA;
            for kk=1:numel(mach)
                mach(kk).H=mach(kk).H*ratio;
                mach(kk).D=mach(kk).D*ratio;
                mach(kk).Xdp=case_data.machines.reactances.Xdp/ratio;
                mach(kk).model='classical';
            end
        end
    elseif isfield(case_data,'machines') && isstruct(case_data.machines) && ~isempty(case_data.machines)
        if isfield(case_data.machines(1),'bus'), mach = case_data.machines; end
    end
elseif isfield(case_data,'bus_data')
    [mpc,mach,freq] = kundur_to_mpc(case_data);
else
    error('ts_simulate:badCase','Case must provide .mpc or Kundur-style bus_data/line_data.');
end
end

% =========================================================================
function [mpc,mach,freq] = kundur_to_mpc(case_data)
% Convert Kundur-style case to MATPOWER mpc + system-base machines.
bv = case_data.base_values;
Ssys = bv.S_base_MVA;
freq = bv.frequency_Hz;
bd = case_data.bus_data;
nb = size(bd,1);
% Kundur type: 1=slack,2=PV,3=PQ  ->  MATPOWER: 1=PQ,2=PV,3=ref
mptype = zeros(nb,1);
mptype(bd(:,2)==1)=3; mptype(bd(:,2)==2)=2; mptype(bd(:,2)==3)=1;
bus = [bd(:,1), mptype, bd(:,7)*Ssys, bd(:,8)*Ssys, bd(:,9)*Ssys, bd(:,10)*Ssys, ...
       ones(nb,1), bd(:,3), bd(:,4), bv.V_base_kV*ones(nb,1), ones(nb,1), ...
       1.1*ones(nb,1), 0.9*ones(nb,1)];
% Generators: buses with type 1 or 2 (have generation).
grows = find(bd(:,2)==1 | bd(:,2)==2);
ng = numel(grows);
gen = zeros(ng,10);
for k=1:ng
    r=grows(k);
    gen(k,:)=[bd(r,1), bd(r,5)*Ssys, bd(r,6)*Ssys, 999, -999, bd(r,3), Ssys, 1, 999, -999];
end
% Branches: line_data [From To R X B_half] -> MATPOWER [f t r x b 0 0 0 0 0 1]
ld = case_data.line_data;
nl = size(ld,1);
branch = zeros(nl,11);
branch(:,1:5)=[ld(:,1),ld(:,2),ld(:,3),ld(:,4),2*ld(:,5)];
branch(:,11)=1;
mpc = struct('baseMVA',Ssys,'bus',bus,'gen',gen,'branch',branch,'gencost',[]);
mpc.case_name = case_data.system_name;
% Machines -> system base. ratio = S_mach/S_sys.
Smach = case_data.machines.base.S_MVA;
ratio = Smach/Ssys;
R = case_data.machines.reactances;
units = case_data.machines.units;
nu = numel(units);
mach = repmat(struct('bus',0,'H',0,'D',0,'Xdp',0,'model','classical'), nu, 1);
for k=1:nu
    mach(k).bus = units(k).bus;
    mach(k).H = units(k).H * ratio;     % inertia referred to system base
    mach(k).D = units(k).D * ratio;
    mach(k).Xdp = R.Xdp / ratio;       % reactance referred to system base
    mach(k).model = 'classical';
end
end

% =========================================================================
function [H,D,Xdp] = expand_machines(mach, ng, gbus, bus_ids, opt) %#ok<INUSD>
%EXPAND_MACHINES  Map machine dynamic data to generator buses.
%   Always maps by BUS ID (never by index), so that machine ordering does
%   not need to match the gen-row ordering.  When multiple machines are
%   connected to the same bus they are aggregated using the standard
%   coherent classical equivalent:
%       H_agg    = sum(H_k)            (kinetic energies add)
%       D_agg    = sum(D_k)            (damping torques add)
%       1/X'd_agg = sum(1/X'd_k)      (parallel admittances add)
%
%   If a case provides machine data (mach non-empty) but a generator bus
%   has no matching machine, an ERROR is raised -- we never silently fall
%   back to H=5 / X'd=0.3 when the case explicitly carries machine data.
%   Defaults are used ONLY when no machine data is supplied at all.

H = 5.0*ones(ng,1); D = zeros(ng,1); Xdp = 0.30*ones(ng,1);
has_mach = ~isempty(mach) && numel(mach) > 0;

if has_mach
    machBus = [mach.bus];
    for k = 1:ng
        b = gbus(k);
        idx = find(machBus == b);
        if isempty(idx)
            error('ts_simulate:noMachineForBus', ...
                ['Generator bus %d has no matching machine data. ' ...
                 'When a case provides .machines, every generator bus ' ...
                 'must have at least one machine entry. ' ...
                 'Add the missing machine or remove the generator bus.'], b);
        end
        Hk  = [mach(idx).H];
        Dk  = [mach(idx).D];
        Xk  = [mach(idx).Xdp];
        H(k)   = sum(Hk);
        D(k)   = sum(Dk);
        Xdp(k) = 1 / sum(1./Xk);
    end
    % Validate: H > 0, Xdp > 0 and finite.
    if any(~isfinite(H)) || any(H <= 0)
        error('ts_simulate:badH', 'Aggregated H must be positive and finite (got min=%.4g).', min(H));
    end
    if any(~isfinite(Xdp)) || any(Xdp <= 0)
        error('ts_simulate:badXdp', 'Aggregated X''d must be positive and finite (got min=%.4g).', min(Xdp));
    end
end

% Per-run overrides (e.g. classical defaults for MATPOWER cases).
if ~isempty(opt.H),   H=opt.H(:);   if numel(H)==1, H=H*ones(ng,1); end, end
if ~isempty(opt.D),   D=opt.D(:);   if numel(D)==1, D=D*ones(ng,1); end, end
if ~isempty(opt.Xdp), Xdp=opt.Xdp(:); if numel(Xdp)==1, Xdp=Xdp*ones(ng,1); end, end
end

% =========================================================================
function [V,Ig,Pe] = solve_network(delta,Eqmag,Ynet,gen_buses,bus_ids,Xdp,fault_on,opt)
nb=size(Ynet,1); ng=numel(gen_buses);
Y=Ynet; Iinj=zeros(nb,1);
for k=1:ng
    b=find(bus_ids==gen_buses(k),1);
    yg=1/(1i*Xdp(k));
    E=Eqmag(k)*exp(1i*delta(k));
    Y(b,b)=Y(b,b)+yg;
    Iinj(b)=Iinj(b)+E*yg;
end
if fault_on
    fb=find(bus_ids==opt.fault_bus,1);
    Y(fb,fb)=Y(fb,fb)+1/opt.Zf;
end
V=Y\Iinj;
Ig=zeros(ng,1); Pe=zeros(ng,1);
for k=1:ng
    b=find(bus_ids==gen_buses(k),1);
    E=Eqmag(k)*exp(1i*delta(k));
    Ig(k)=(E-V(b))/(1i*Xdp(k));
    Pe(k)=real(V(b)*conj(Ig(k)));
end
end

% =========================================================================
function Y = build_ybus_from_mpc(mpc)
bus=mpc.bus; br=mpc.branch; nb=size(bus,1); Y=zeros(nb);
for k=1:size(br,1)
    if br(k,11)==0, continue; end
    i=find(bus(:,1)==br(k,1),1); j=find(bus(:,1)==br(k,2),1);
    r=br(k,3); x=br(k,4); b=br(k,5); tap=br(k,9); shift=br(k,10);
    if tap==0, tap=1; end
    a=tap*exp(1i*deg2rad(shift)); y=1/(r+1i*x);
    Y(i,i)=Y(i,i)+y/(a*conj(a))+1i*b/2;
    Y(j,j)=Y(j,j)+y+1i*b/2;
    Y(i,j)=Y(i,j)-y/conj(a);
    Y(j,i)=Y(j,i)-y/a;
end
Y = Y + diag((bus(:,5)+1i*bus(:,6))/mpc.baseMVA);
end
