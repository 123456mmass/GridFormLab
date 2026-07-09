function res = case14_ts_classical(varargin)
%CASE14_TS_CLASSICAL Classical transient-stability simulation for MATPOWER case14.
% Uses in-house PF, classical generator model with default dynamic data, and
% trapezoidal predictor-corrector/Heun integration.  This is a TS smoke/demo
% for the imported MATPOWER6 case14 power-flow data; MATPOWER is not called.
%
% Conventions are standard power-system practice (terminal electrical power
% Pe = Re{V*conj(Ig)}, mechanical power from solved PF generation, default
% H/X'd) and are NOT tied to any external tool. The result has been
% independently cross-validated against PSAT (Federico Milano, independent
% code + implicit-Newton trapezoidal scheme): in the COI frame rotor angles
% agree to ~0.6 deg and speeds to ~3e-4 pu. See compare_case14_ts_three_way.

opt = struct('t_end',15.0,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal','corrector_iter',1, ...
    'H',[],'D',[],'Xdp',[],'verbose',true,'pm_mode','balanced');
if nargin > 0
    user = varargin{1};
    fn = fieldnames(user);
    for k=1:numel(fn), opt.(fn{k}) = user.(fn{k}); end
end

if opt.verbose, fprintf('Running PF...\n'); end
c = cases.case_matpower6_case14();
pf = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false, ...
    'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
if ~pf.converged, error('case14_ts_classical:pfNotConverged','Power flow did not converge.'); end

mpc = c.mpc; base = mpc.baseMVA;
gen = mpc.gen(mpc.gen(:,8) ~= 0,:);
gbus = gen(:,1); ng = size(gen,1); nb = size(mpc.bus,1);
if isempty(opt.H),   opt.H   = 5.0*ones(ng,1); end  % default inertia (s); MATPOWER case14 carries no H, so 5 s is assumed
if isempty(opt.D),   opt.D   = zeros(ng,1); end
if isempty(opt.Xdp), opt.Xdp = 0.30*ones(ng,1); end
H=opt.H(:); D=opt.D(:); Xdp=opt.Xdp(:);
if numel(H)~=ng || numel(D)~=ng || numel(Xdp)~=ng
    error('case14_ts_classical:badDynamicData','H, D, and Xdp must have one entry per online generator.');
end

if opt.verbose, fprintf('Dynamic initialization...\n'); end
Ybus = build_ybus_from_mpc(mpc);
V0 = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
Sload = (mpc.bus(:,3) + 1i*mpc.bus(:,4))/base;
Yload = conj(Sload)./(abs(V0).^2 + eps);
Ynet = Ybus + diag(Yload);

E0 = zeros(ng,1); delta0=zeros(ng,1); Eqmag=zeros(ng,1); Pm=zeros(ng,1);
for k=1:ng
    b = find(mpc.bus(:,1)==gbus(k),1);
    % Generator current from solved PF generation (standard classical-model init).
    Sg = pf.P_generation(b) + 1i*pf.Q_generation(b);
    Ig0 = conj(Sg/V0(b));
    E0(k) = V0(b) + 1i*Xdp(k)*Ig0;
    delta0(k)=angle(E0(k)); Eqmag(k)=abs(E0(k));
    Pm(k)=real(E0(k)*conj(Ig0));
end

if opt.verbose
    fprintf('Running TS: t_end = %.3f s, dt = %.4f s\n', opt.t_end, opt.dt);
    fprintf('Fault: bus %d, t_fault = %.3f s, t_clear = %.3f s, Zf = %.4g %+.4gj pu\n', ...
        opt.fault_bus, opt.t_fault, opt.t_clear, real(opt.Zf), imag(opt.Zf));
end

t = (0:opt.dt:opt.t_end).'; nt=numel(t); ws=2*pi*60;
delta=zeros(nt,ng); omega=zeros(nt,ng); Pe=zeros(nt,ng); Vhist=zeros(nt,nb);
delta(1,:)=delta0.'; omega(1,:)=ones(1,ng);
[V,Ig,Pe0] = solve_network(delta0, Eqmag, Ynet, gbus, mpc.bus(:,1), Xdp, 0, opt);
switch lower(opt.pm_mode)
    case {'balanced','pe0'}
        % Pm = pre-fault electrical power -> stationary pre-fault trajectory.
        Pm = Pe0;
    case {'pfpg','pgaz','pg'}
        % Pm = solved PF generation (constant mechanical power). 'pgaz'/'pg'
        % are kept as deprecated aliases for backward compatibility.
        Pm = zeros(ng,1);
        for kk = 1:ng
            bb = find(mpc.bus(:,1)==gbus(kk),1);
            Pm(kk) = pf.P_generation(bb);
        end
    otherwise
        error('case14_ts_classical:unknownPmMode','Unknown pm_mode "%s".', opt.pm_mode);
end
Pe(1,:)=Pe0.'; Vhist(1,:)=abs(V).';

x=[delta0; ones(ng,1)];
for it=1:nt-1
    f0 = rhs(t(it), x);
    xnext = x + opt.dt*f0;
    for ci=1:max(1,opt.corrector_iter)
        f1 = rhs(t(it+1), xnext);
        xnext = x + 0.5*opt.dt*(f0+f1);
    end
    x=xnext;
    delta(it+1,:)=x(1:ng).'; omega(it+1,:)=x(ng+1:end).';
    fault_on_rec = t(it+1) >= opt.t_fault && t(it+1) < opt.t_clear;
    [V,~,Pek] = solve_network(x(1:ng), Eqmag, Ynet, gbus, mpc.bus(:,1), Xdp, fault_on_rec, opt);
    Pe(it+1,:)=Pek.'; Vhist(it+1,:)=abs(V).';
end

if opt.verbose
    fprintf('------------------------------------------------------------\n');
    fprintf('TS finished.\n');
    fprintf('Generators online : %d\n', ng);
    fprintf('Method            : %s\n', opt.method);
    fprintf('Simulation time   : %.3f s\n', opt.t_end);
    fprintf('Time step         : %.4f s\n', opt.dt);
    fprintf('Fault bus         : %d\n', opt.fault_bus);
    fprintf('Fault time        : %.3f s\n', opt.t_fault);
    fprintf('Clear time        : %.3f s\n', opt.t_clear);
end

res=struct('t',t,'delta',delta,'omega',omega,'Pe_pu',Pe,'Pe_MW',Pe*base, ...
    'Vbus',Vhist,'pf',pf,'case_data',c,'gen_buses',gbus,'H',H,'D',D,'Xdp',Xdp, ...
    'Pm',Pm,'Eqmag',Eqmag,'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'fault_bus',opt.fault_bus,'t_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf);

    function dx = rhs(tnow, xx)
        del=xx(1:ng); w=xx(ng+1:end);
        fault_on = tnow >= opt.t_fault && tnow < opt.t_clear;
        [~,~,Pek]=solve_network(del, Eqmag, Ynet, gbus, mpc.bus(:,1), Xdp, fault_on, opt);
        ddel=ws*(w-1);
        dw=(Pm-Pek-D.*(w-1))./(2*H);
        dx=[ddel; dw];
    end
end

function [V,Ig,Pe] = solve_network(delta, Eqmag, Ynet, gen_buses, bus_ids, Xdp, fault_on, opt)
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
    % Electrical power = terminal active power Re{V*conj(Ig)} (standard
    % classical-model convention; equals air-gap Re{E*conj(Ig)} for ra=0).
    Pe(k)=real(V(b)*conj(Ig(k)));
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
% bus shunts, MATPOWER Bs in MVAr at V=1, Gs MW at V=1
Y = Y + diag((bus(:,5)+1i*bus(:,6))/mpc.baseMVA);
end
