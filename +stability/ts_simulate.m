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
    'Zf',1i*0.1,'method','trapezoidal','corrector_iter',1, ...
    'pm_mode','balanced','verbose',true,'H',[],'D',[],'Xdp',[],'model','classical','load_model','cc_p_cz_q');
if nargin > 1 && isstruct(varargin{1})
    fn = fieldnames(varargin{1});
    for k=1:numel(fn), opt.(fn{k}) = varargin{1}.(fn{k}); end
end

% --- Model dispatch: single entry point for classical and 6th-order -------
if strcmpi(opt.model,'genpj6')
    if opt.verbose, fprintf('[ts_simulate] Dispatching to 6th-order GENTPJ path.\n'); end
    res = stability.ts_simulate_genpj6(case_data, opt);
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
gbus = gen(:,1); ng = size(gen,1); nb = size(mpc.bus,1);
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
end

t=(0:opt.dt:opt.t_end).'; nt=numel(t);
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

x=[delta0; ones(ng,1)];
for it=1:nt-1
    f0=rhs(t(it),x);
    xnext=x+opt.dt*f0;
    for ci=1:max(1,opt.corrector_iter)
        f1=rhs(t(it+1),xnext);
        xnext=x+0.5*opt.dt*(f0+f1);
    end
    x=xnext;
    delta(it+1,:)=x(1:ng).'; omega(it+1,:)=x(ng+1:end).';
    fault_on=t(it+1)>=opt.t_fault && t(it+1)<opt.t_clear;
    [V,~,Pek]=solve_network(x(1:ng),Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp,fault_on,opt);
    Pe(it+1,:)=Pek.'; Vhist(it+1,:)=abs(V).';
end
if opt.verbose, fprintf('[ts_simulate] TS finished: %d steps, method=%s\n',nt-1,opt.method); end

res=struct('t',t,'delta',delta,'omega',omega,'Pe_pu',Pe,'Pe_MW',Pe*base, ...
    'Vbus',Vhist,'pf',pf,'gen_buses',gbus,'H',H,'D',D,'Xdp',Xdp, ...
    'Pm',Pm,'Eqmag',Eqmag,'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'fault_bus',opt.fault_bus,'t_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'model','classical','freq_Hz',freq);

    function dx=rhs(tnow,xx)
        del=xx(1:ng); w=xx(ng+1:end);
        fault_on=tnow>=opt.t_fault && tnow<opt.t_clear;
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
function [H,D,Xdp] = expand_machines(mach, ng, gbus, bus_ids, opt)
H=5.0*ones(ng,1); D=zeros(ng,1); Xdp=0.30*ones(ng,1);
if ~isempty(mach) && numel(mach)==ng
    for k=1:ng
        if isfield(mach(k),'H'),   H(k)=mach(k).H;   end
        if isfield(mach(k),'D'),   D(k)=mach(k).D;   end
        if isfield(mach(k),'Xdp'), Xdp(k)=mach(k).Xdp; end
    end
elseif ~isempty(mach)
    % map by bus if counts differ
    for k=1:ng
        b=gbus(k);
        idx=find([mach.bus]==b,1);
        if ~isempty(idx)
            H(k)=mach(idx).H; D(k)=mach(idx).D; Xdp(k)=mach(idx).Xdp;
        end
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
