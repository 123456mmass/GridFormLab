function result = classical_sssa(case_data, options)
%CLASSICAL_SSSA Small-signal analysis of a standard network case.
%   Linearises the same classical machine/network model used by
%   stability.ts_simulate.  One coherent equivalent machine is used per
%   online generator bus.  Cases without published dynamics use the
%   documented project defaults H=5 s, D=0, X'd=0.3 pu.

if nargin < 2 || isempty(options), options=struct(); end
if ~isfield(case_data,'schema_version') || ...
        ~strcmp(case_data.schema_version,'power_case/1.0')
    error('classical_sssa:notNetworkCase', ...
        'Classical SSSA requires a power_case/1.0 network case.');
end

init_opt=options;
init_opt.model='classical';
init_opt.t_end=0;
init_opt.dt=0.01;
init_opt.t_fault=inf;
init_opt.t_clear=inf;
init_opt.verbose=false;
init=stability.ts_simulate(case_data,init_opt);

mpc=case_data.mpc;
base=mpc.baseMVA;
freq=case_data.base_values.frequency_Hz;
ws=2*pi*freq;
gbus=init.gen_buses(:);
ng=numel(gbus);
H=init.H(:); D=init.D(:); Xdp=init.Xdp(:); Eqmag=init.Eqmag(:);
delta0=init.delta(1,:).';

V0=init.pf.bus_voltage(:).*exp(1i*deg2rad(init.pf.bus_angle_deg(:)));
Ybus=build_ybus(mpc);
Sload=(mpc.bus(:,3)+1i*mpc.bus(:,4))/base;
Ynet=Ybus+diag(conj(Sload)./(abs(V0).^2+eps));

if isfield(options,'fd_eps'), h=options.fd_eps; else, h=1e-6; end
K=zeros(ng);
for k=1:ng
    dp=delta0; dm=delta0;
    dp(k)=dp(k)+h; dm(k)=dm(k)-h;
    K(:,k)=(electrical_power(dp)-electrical_power(dm))/(2*h);
end

% Grouped ordering [all delta; all omega], then convert to machine-block
% ordering [delta_1;omega_1;delta_2;omega_2;...] required by the common
% COI-reduction engine.
Agroup=[zeros(ng),ws*eye(ng); ...
       -diag(1./(2*H))*K,-diag(D./(2*H))];
perm=reshape([1:ng; ng+(1:ng)],[],1);
A=Agroup(perm,perm);
x0=reshape([delta0.'; ones(1,ng)],[],1);
state_names=cell(2*ng,1);
for k=1:ng
    state_names{2*k-1}=sprintf('delta_G%d@Bus%d',k,gbus(k));
    state_names{2*k}=sprintf('omega_G%d@Bus%d',k,gbus(k));
end

model=struct('x0',x0,'y0',0,'f',@(x,y) zeros(size(x)), ...
    'g',@(x,y) 0,'Jxx',A,'Jxy',zeros(2*ng,1), ...
    'Jyx',zeros(1,2*ng),'Jyy',1,'free_y',1, ...
    'reduction','coi','ng',ng,'states_per_machine',2, ...
    'angle_state_index',1,'speed_state_index',2,'inertia',H, ...
    'state_names',{state_names},'metadata',struct( ...
        'engine','stability.multimachine_ssa', ...
        'plugin','classical_network_linearization', ...
        'dynamic_data_source',dynamic_source(case_data)));
result=stability.multimachine_ssa(model);
result.state_names=state_names;
result.state_table=table((1:2*ng).',string(state_names), ...
    kron(gbus,ones(2,1)),repmat(string({'angle';'speed'}),ng,1), ...
    'VariableNames',{'Index','State','Bus','Type'});
result.linearization=struct('K_Pe_delta',K,'A_grouped',Agroup, ...
    'delta0',delta0,'H',H,'D',D,'Xdp',Xdp,'Eqmag',Eqmag, ...
    'gen_buses',gbus,'pf',init.pf);
result.newton_residual=0;
result=attach_status(result,options);

    function Pe=electrical_power(delta)
        nb=size(Ynet,1);
        Y=Ynet; Iinj=zeros(nb,1);
        for ii=1:ng
            b=find(mpc.bus(:,1)==gbus(ii),1);
            yg=1/(1i*Xdp(ii));
            E=Eqmag(ii)*exp(1i*delta(ii));
            Y(b,b)=Y(b,b)+yg;
            Iinj(b)=Iinj(b)+E*yg;
        end
        V=Y\Iinj;
        Pe=zeros(ng,1);
        for ii=1:ng
            b=find(mpc.bus(:,1)==gbus(ii),1);
            E=Eqmag(ii)*exp(1i*delta(ii));
            Ig=(E-V(b))/(1i*Xdp(ii));
            Pe(ii)=real(V(b)*conj(Ig));
        end
    end
end

function result=attach_status(result,options)
if isfield(options,'stability_tolerance')
    tol=options.stability_tolerance;
else
    tol=1e-7;
end
lam=result.reduced_eigenvalues(:);
nu=sum(real(lam)>tol); ns=sum(real(lam)<-tol); nm=numel(lam)-nu-ns;
if isempty(lam)
    status='NOT APPLICABLE - NO RELATIVE MODES';
elseif nu>0
    status='UNSTABLE';
elseif nm>0
    status='MARGINAL';
else
    status='ASYMPTOTICALLY STABLE';
end
result.stability_status=status;
result.stability_tolerance=tol;
result.root_counts=struct('unstable',nu,'stable',ns,'marginal',nm);
end

function s=dynamic_source(c)
if isfield(c,'dynamic_assumptions') && isfield(c.dynamic_assumptions,'source')
    s=c.dynamic_assumptions.source;
elseif isfield(c,'machines') && ~isempty(c.machines)
    s='case machine data';
else
    s='project classical defaults: H=5 s, D=0, Xdp=0.3 pu';
end
end

function Y=build_ybus(mpc)
bus=mpc.bus; br=mpc.branch; nb=size(bus,1); Y=zeros(nb);
for k=1:size(br,1)
    if br(k,11)==0, continue; end
    i=find(bus(:,1)==br(k,1),1); j=find(bus(:,1)==br(k,2),1);
    r=br(k,3); x=br(k,4); b=br(k,5); tap=br(k,9); shift=br(k,10);
    if tap==0, tap=1; end
    a=tap*exp(1i*deg2rad(shift)); y=1/(r+1i*x);
    Y(i,i)=Y(i,i)+y/(a*conj(a))+1i*b/2;
    Y(j,j)=Y(j,j)+y+1i*b/2;
    Y(i,j)=Y(i,j)-y/conj(a); Y(j,i)=Y(j,i)-y/a;
end
Y=Y+diag((bus(:,5)+1i*bus(:,6))/mpc.baseMVA);
end
