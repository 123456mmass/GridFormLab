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
    'pm_mode','balanced','verbose',true,'H',[],'D',[],'Xdp',[],'model','classical','load_model','cc_p_cz_q');
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
if strcmpi(opt.model,'emf6')
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
[V,~,Pe0]=solve_network(delta0,Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp,0,opt);
switch lower(opt.pm_mode)
    case {'balanced','pe0'}
        Pm=Pe0;
    case {'pfpg','pgaz','pg'}
        Pm=zeros(ng,1);
        for kk=1:ng
            bb=find(mpc.bus(:,1)==gbus(kk),1); Pm(kk)=pf.P_generation(bb);
        end
    otherwise
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
for it=1:nt-1
    dt_step = dt_arr(it);
    t_now = t(it);
    t_next = t(it+1);

    % Determine topology for this step. The fault status at t_now determines
    % the pre-event topology. If t_next is an event time, the step uses the
    % pre-event topology for the entire step, then the topology switches
    % at the event boundary. The next step starts with the post-event topology.
    % This prevents trapezoidal averaging of RHS from different topologies.
    fault_on_now = t_now >= opt.t_fault && t_now < opt.t_clear;

    % Predictor: explicit Euler
    f0 = rhs_fixed(t_now, x, fault_on_now);
    xnext = x + dt_step * f0;

    if strcmp(opt.corrector_mode,'adaptive')
        % Adaptive Picard corrector with trapezoidal residual check
        for ci = 1:opt.max_corrector_iter
            f1 = rhs_fixed(t_next, xnext, fault_on_now);
            x_new = x + 0.5*dt_step*(f0 + f1);
            update_norm = norm(x_new - xnext, inf);
            % Check the residual at the candidate state itself.  Checking
            % only the Picard update can accept a state whose trapezoidal
            % equation is still not solved.
            f1_new = rhs_fixed(t_next, x_new, fault_on_now);
            R_new = x_new - x - 0.5*dt_step*(f0 + f1_new);
            residual_norm = norm(R_new, inf);
            corr_iters(it) = ci;
            corr_update(it) = update_norm;
            corr_residual(it) = residual_norm;
            xnext = x_new;
            tol_now = opt.corrector_abs_tol + ...
                opt.corrector_rel_tol * max(1, norm(xnext, inf));
            if update_norm <= tol_now && residual_norm <= tol_now
                corr_converged(it) = true;
                break;
            end
            if ci == opt.max_corrector_iter
                corr_converged(it) = false;
                % Recompute final residual for reporting
                f1_final = rhs_fixed(t_next, xnext, fault_on_now);
                R = xnext - x - 0.5*dt_step*(f0 + f1_final);
                corr_residual(it) = norm(R, inf);
                if strcmp(opt.corrector_failure, 'error')
                    error('ts_simulate:correctorNotConverged', ...
                        ['Corrector did not converge at t=%.4f (step %d). ' ...
                        'Iterations=%d, update=%.3e, residual=%.3e. ' ...
                        'Consider increasing max_corrector_iter or loosening tolerance.'], ...
                        t_next, it, ci, update_norm, corr_residual(it));
                end
            end
        end
        % Final residual (for converged steps)
        if corr_converged(it)
            f1_final = rhs_fixed(t_next, xnext, fault_on_now);
            R = xnext - x - 0.5*dt_step*(f0 + f1_final);
            corr_residual(it) = norm(R, inf);
        end
    else
        % Fixed corrector (backward compatible)
        for ci=1:max(1,opt.corrector_iter)
            f1 = rhs_fixed(t_next, xnext, fault_on_now);
            xnext = x + 0.5*dt_step*(f0 + f1);
        end
        corr_iters(it) = opt.corrector_iter;
        f1_final = rhs_fixed(t_next, xnext, fault_on_now);
        R = xnext - x - 0.5*dt_step*(f0 + f1_final);
        corr_residual(it) = norm(R, inf);
        corr_update(it) = norm(R, inf);  % for fixed mode, update ~ residual
        corr_converged(it) = corr_residual(it) <= 1e-6;  % loose check
    end
    if ~corr_converged(it), nonconv_count = nonconv_count + 1; end

    x = xnext;
    delta(it+1,:) = x(1:ng).'; omega(it+1,:) = x(ng+1:end).';

    % Recompute algebraic with the ACTUAL topology at t_next
    fault_on_next = t_next >= opt.t_fault && t_next < opt.t_clear;
    [V,~,Pek] = solve_network(x(1:ng),Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp,fault_on_next,opt);
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

    function dx=rhs(tnow,xx) %#ok<USD>
        del=xx(1:ng); w=xx(ng+1:end);
        fault_on=tnow>=opt.t_fault && tnow<opt.t_clear;
        [~,~,Pek]=solve_network(del,Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp,fault_on,opt);
        dx=[ws*(w-1); (Pm-Pek-D.*(w-1))./(2*H)];
    end

    function dx=rhs_fixed(~,xx,fault_on)
        del=xx(1:ng); w=xx(ng+1:end);
        [~,~,Pek]=solve_network(del,Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp,fault_on,opt);
        dx=[ws*(w-1); (Pm-Pek-D.*(w-1))./(2*H)];
    end
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
