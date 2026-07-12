function dae = classical_dae(case_data, opt)
%CLASSICAL_DAE  Classical (2nd-order) DAE wrapper for the shared step contract.
%   DAE = classical_dae(CASE_DATA, OPT) wraps the classical engine's direct
%   linear network solve (V = Y\Iinj) behind the same dae_f / electrical_power
%   contract used by padiyar_model11_dae and emf6_dae, so the shared
%   ts_step_kernel / ts_model_strategy path can drive the classical model.
%
%   Algebraic contract: the classical network is LINEAR given (delta, Eqmag, Y),
%   so the algebraic solve is a single direct linear solve V = Y\Iinj — NOT a
%   nonlinear Newton iteration. The "Jacobian" of g w.r.t. y is -Y (exact and
%   constant per topology); needs_jyy is false and jac_y returns [].
%
%   State order: x = [delta(1..ng); omega(1..ng)] (delta in rad, omega in pu).
%   Algebraic state: y = [Re(V1), Im(V1), ..., Re(Vnb), Im(Vnb)]^T (interleaved,
%   matching Padiyar/EMF6).
%
%   Y convention: the Y passed to dae_f / electrical_power is the BASE TOPOLOGY
%   (Ynet + fault admittance if faulted), WITHOUT generator admittances. The
%   generator admittances 1/(j*Xdp) and current injections E*yg are added inside
%   solve_network_linear (identical to the classical engine's solve_network), so
%   the linear solve V = (Y + Ygen)\Iinj is bit-identical to the legacy path.
%
%   This is Phase 2 work: routing the classical fixed-step path through the
%   strategy. Bit-identical to the legacy inline corrector is verified by
%   tests/test_ts_characterization_fixed.m (dual-path comparison).

opt = defaults(opt);

% --- Power flow (in-house Newton) ------------------------------------------
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10, ...
    'enforce_q_limits',false));
if ~pf.converged
    error('classical_dae:powerFlow','In-house Newton PF did not converge.');
end

[mpc, mach, freq] = normalize_case(case_data);
base = mpc.baseMVA;
ws = 2*pi*freq;

gen = mpc.gen(mpc.gen(:,8) ~= 0,:);
gbus_raw = gen(:,1);
[gbus, ~, ~] = unique(gbus_raw, 'stable');
ng = numel(gbus); nb = size(mpc.bus,1);

[H,D,Xdp] = stability.expand_machines_classical(mach, ng, gbus, mpc.bus(:,1), opt);

Ybus = build_ybus_from_mpc(mpc);
V0 = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
Sload = (mpc.bus(:,3) + 1i*mpc.bus(:,4))/base;
Yload = conj(Sload)./(abs(V0).^2 + eps);
Ynet = Ybus + diag(Yload);

% --- Initial dynamic state -------------------------------------------------
E0=zeros(ng,1); delta0=zeros(ng,1); Eqmag=zeros(ng,1); Pm=zeros(ng,1);
for k=1:ng
    b=find(mpc.bus(:,1)==gbus(k),1);
    Sg=pf.P_generation(b)+1i*pf.Q_generation(b);
    Ig0=conj(Sg/V0(b));
    E0(k)=V0(b)+1i*Xdp(k)*Ig0;
    delta0(k)=angle(E0(k)); Eqmag(k)=abs(E0(k));
    Pm(k)=real(E0(k)*conj(Ig0));
end

% Pm selection (matches the legacy engine's pm_mode).
switch lower(opt.pm_mode)
    case {'balanced','pe0'}
        [~,~,Pe0] = solve_network_linear(delta0,Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp);
        Pm = Pe0;
    case {'pfpg','pgaz','pg'}
        Pm=zeros(ng,1);
        for kk=1:ng
            bb=find(mpc.bus(:,1)==gbus(kk),1); Pm(kk)=pf.P_generation(bb);
        end
    otherwise
        error('classical_dae:unknownPmMode','Unknown pm_mode "%s".',opt.pm_mode);
end

x0 = [delta0; ones(ng,1)];
y0 = zeros(2*nb,1);
[V0_init,~,~] = solve_network_linear(delta0,Eqmag,Ynet,gbus,mpc.bus(:,1),Xdp);
y0(1:2:end) = real(V0_init); y0(2:2:end) = imag(V0_init);

% --- DAE closures ----------------------------------------------------------
% dae_f(x,y,Y): swing equations. y is NOT used (Pe comes from solve_network,
% which depends only on delta, Eqmag, Y). This matches the legacy rhs_fixed.
dae_f = @(x,y,Y) swing_rhs(x, y, Y, Eqmag, gbus, mpc.bus(:,1), Xdp, H, D, Pm, ws);
% electrical_power(x,y,Y): Pe per generator at the network solution for (delta,Y).
electrical_power = @(x,y,Y) network_pe(x, Y, Eqmag, gbus, mpc.bus(:,1), Xdp);

dae = struct();
dae.model = 'classical';
dae.pf = pf;
dae.mpc = mpc;
dae.bus_ids = mpc.bus(:,1);
dae.gen_buses = gbus;
dae.ng = ng; dae.nb = nb;
dae.H = H; dae.D = D; dae.Xdp = Xdp;
dae.Eqmag = Eqmag; dae.Pm = Pm;
dae.Ynet = Ynet;
dae.x0 = x0; dae.y0 = y0;
dae.dae_f = dae_f;
dae.dae_g = [];                 % no nonlinear algebraic residual
dae.electrical_power = electrical_power;
dae.ws = ws; dae.base = base; dae.freq = freq;
dae.initial_residual = 0;       % classical PF is exact
dae.state_layout = 'classical_2nd_order';
dae.case_name = mpc.case_name;
end

% =========================================================================
function dx = swing_rhs(x, ~, Y, Eqmag, gbus, bus_ids, Xdp, H, D, Pm, ws)
ng = numel(gbus);
delta = x(1:ng); w = x(ng+1:2*ng);
[~,~,Pe] = solve_network_linear(delta,Eqmag,Y,gbus,bus_ids,Xdp);
dx = [ws*(w-1); (Pm-Pe-D.*(w-1))./(2*H)];
end

function Pe = network_pe(x, Y, Eqmag, gbus, bus_ids, Xdp)
ng = numel(gbus);
delta = x(1:ng);
[~,~,Pe] = solve_network_linear(delta,Eqmag,Y,gbus,bus_ids,Xdp);
end

function [V,Ig,Pe] = solve_network_linear(delta,Eqmag,Y,gbus,bus_ids,Xdp)
% Identical to the legacy ts_simulate/solve_network: builds Y+Ygen, solves
% V = (Y+Ygen)\Iinj, then computes Ig and Pe per generator. The fault
% admittance is assumed already in Y (the topology Y). Bit-identical to the
% classical engine's solve_network when called with the same Y.
nb=size(Y,1); ng=numel(gbus);
Yloc=Y; Iinj=zeros(nb,1);
for k=1:ng
    b=find(bus_ids==gbus(k),1);
    yg=1/(1i*Xdp(k));
    E=Eqmag(k)*exp(1i*delta(k));
    Yloc(b,b)=Yloc(b,b)+yg;
    Iinj(b)=Iinj(b)+E*yg;
end
V=Yloc\Iinj;
Ig=zeros(ng,1); Pe=zeros(ng,1);
for k=1:ng
    b=find(bus_ids==gbus(k),1);
    E=Eqmag(k)*exp(1i*delta(k));
    Ig(k)=(E-V(b))/(1i*Xdp(k));
    Pe(k)=real(V(b)*conj(Ig(k)));
end
end

% =========================================================================
function [mpc,mach,freq] = normalize_case(case_data)
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
    error('classical_dae:badCase','Case must provide .mpc or Kundur-style bus_data/line_data.');
end
end

function [mpc,mach,freq] = kundur_to_mpc(case_data)
bv = case_data.base_values;
Ssys = bv.S_base_MVA;
freq = bv.frequency_Hz;
bd = case_data.bus_data;
nb = size(bd,1);
mptype = zeros(nb,1);
mptype(bd(:,2)==1)=3; mptype(bd(:,2)==2)=2; mptype(bd(:,2)==3)=1;
bus = [bd(:,1), mptype, bd(:,7)*Ssys, bd(:,8)*Ssys, bd(:,9)*Ssys, bd(:,10)*Ssys, ...
       ones(nb,1), bd(:,3), bd(:,4), bv.V_base_kV*ones(nb,1), ones(nb,1), ...
       1.1*ones(nb,1), 0.9*ones(nb,1)];
grows = find(bd(:,2)==1 | bd(:,2)==2);
ng = numel(grows);
gen = zeros(ng,10);
for k=1:ng
    r=grows(k);
    gen(k,:)=[bd(r,1), bd(r,5)*Ssys, bd(r,6)*Ssys, 999, -999, bd(r,3), Ssys, 1, 999, -999];
end
ld = case_data.line_data;
nl = size(ld,1);
branch = zeros(nl,11);
branch(:,1:5)=[ld(:,1),ld(:,2),ld(:,3),ld(:,4),2*ld(:,5)];
branch(:,11)=1;
mpc = struct('baseMVA',Ssys,'bus',bus,'gen',gen,'branch',branch,'gencost',[]);
mpc.case_name = case_data.system_name;
Smach = case_data.machines.base.S_MVA;
ratio = Smach/Ssys;
R = case_data.machines.reactances;
units = case_data.machines.units;
nu = numel(units);
mach = repmat(struct('bus',0,'H',0,'D',0,'Xdp',0,'model','classical'), nu, 1);
for k=1:nu
    mach(k).bus = units(k).bus;
    mach(k).H = units(k).H * ratio;
    mach(k).D = units(k).D * ratio;
    mach(k).Xdp = R.Xdp / ratio;
    mach(k).model = 'classical';
end
end

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

function opt = defaults(opt)
d = struct('t_end',15.0,'dt',0.01,'fault_bus',[],'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_iter',[],'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error','pm_mode','balanced', ...
    'verbose',true,'H',[],'D',[],'Xdp',[],'model','classical', ...
    'load_model','cc_p_cz_q','fault_enabled',true);
fns = fieldnames(d);
for k=1:numel(fns)
    if ~isfield(opt,fns{k}), opt.(fns{k}) = d.(fns{k}); end
end
end
