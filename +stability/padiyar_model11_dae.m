function dae = padiyar_model11_dae(case_data, options)
%PADIYAR_MODEL11_DAE Five-state model-1.1/AVR DAE for the Padiyar case.
%   DAE = stability.padiyar_model11_dae(CASE,OPTIONS) builds one shared
%   equation set for initialization, SSSA and TS. OPTIONS.excitation is
%   'avr' (five states/machine) or 'manual' (four states/machine).

if nargin<1 || isempty(case_data)
    case_data=cases.case_padiyar_two_area_4m_avr();
end
if nargin<2 || isempty(options), options=struct(); end
if ~isfield(options,'excitation'), options.excitation='avr'; end
if ~isfield(options,'equilibrium_tolerance'), options.equilibrium_tolerance=1e-10; end
if ~isfield(options,'fd_eps'), options.fd_eps=1e-6; end
excitation=lower(char(options.excitation));
if ~any(strcmp(excitation,{'avr','manual'}))
    error('padiyar_model11_dae:excitation','excitation must be avr or manual.');
end

pf=pfsolver.powerflow_newton_raphson(case_data,struct('verbose',false, ...
    'plot_results',false,'tolerance',options.equilibrium_tolerance, ...
    'max_iter',100,'enforce_q_limits',false));
if ~pf.converged
    error('padiyar_model11_dae:powerFlow','In-house Newton PF did not converge.');
end

[m,u]=parameters(case_data,pf);
[Ynet,load]=network_model(case_data,pf);
[init,x0,y0]=initialize(case_data,pf,m,u,excitation,options);
ns=init.states_per_machine;
f=@(x,y) differential_residual(x,y,init,m,u,excitation);
g=@(x,y) network_residual(x,y,init,m,Ynet);
gY=@(x,y,Y) network_residual(x,y,init,m,Y);
rf=f(x0,y0); rg=g(x0,y0); residual=norm([rf;rg],inf);
if residual>100*options.equilibrium_tolerance
    error('padiyar_model11_dae:equilibrium', ...
        'Initial DAE residual %.3e exceeds tolerance.',residual);
end

dae=struct();
dae.model='padiyar_model_1_1'; dae.excitation=excitation;
dae.case_data=case_data; dae.pf=pf; dae.machine=m; dae.units=u;
dae.init=init; dae.x0=x0; dae.y0=y0; dae.Ynet=Ynet; dae.load=load;
dae.dae_f=f; dae.dae_g=gY; dae.g_equilibrium=g;
dae.electrical_power=@(x,y) electrical_power(x,y,init,m);
dae.reactive_power=@(x,y) reactive_power(x,y,init,m);
dae.current_injection=@(x,y) all_currents(x,y,init,m);
dae.initial_residual_f=norm(rf,inf); dae.initial_residual_g=norm(rg,inf);
dae.initial_residual=residual; dae.ng=m.ng; dae.nb=numel(pf.external_bus_ids);
dae.ns=ns; dae.bus_ids=pf.external_bus_ids(:);
dae.gen_buses=arrayfun(@(z) z.bus,case_data.machines.units(:));
dae.state_names=init.state_names; dae.options=options;
dae.base=case_data.base_values;
end

function [m,u]=parameters(c,pf)
M=c.machines; R=M.reactances; T=M.time_constants; ng=numel(M.units);
m.ng=ng; m.Ra=expand(R.Ra,ng); m.Xd=expand(R.Xd,ng);
m.Xdp=expand(R.Xdp,ng); m.Xq=expand(R.Xq,ng); m.Xqp=expand(R.Xqp,ng);
m.Tpd0=expand(T.Tpd0,ng); m.Tpq0=expand(T.Tpq0,ng);
m.KA=expand(M.exciter.KA,ng); m.TA=expand(M.exciter.TA,ng);
m.wB=2*pi*c.base_values.frequency_Hz;
u.bus_idx=zeros(ng,1); u.bus_ids=zeros(ng,1); u.H=zeros(ng,1); u.D=zeros(ng,1);
u.id=cell(ng,1);
for k=1:ng
    u.bus_ids(k)=M.units(k).bus;
    u.bus_idx(k)=find(pf.external_bus_ids==u.bus_ids(k),1);
    if isempty(u.bus_idx(k)), error('padiyar_model11_dae:bus','Generator bus not found.'); end
    u.H(k)=M.units(k).H; u.D(k)=M.units(k).D; u.id{k}=M.units(k).gen_id;
end
end

function v=expand(v,n)
v=v(:); if isscalar(v), v=repmat(v,n,1); end
if numel(v)~=n, error('padiyar_model11_dae:parameterLength','Parameter length mismatch.'); end
if any(~isfinite(v)), error('padiyar_model11_dae:parameterFinite','Parameters must be finite.'); end
end

function [init,x0,y0]=initialize(~,pf,m,u,excitation,opt)
ng=m.ng; nb=numel(pf.external_bus_ids);
ns=4+strcmp(excitation,'avr'); x0=zeros(ns*ng,1); y0=zeros(2*nb,1);
for b=1:nb
    V=pf.bus_voltage(b)*exp(1i*deg2rad(pf.bus_angle_deg(b)));
    y0(2*b-1:2*b)=[real(V);imag(V)];
end
init=struct('ng',ng,'states_per_machine',ns,'bus_idx',u.bus_idx, ...
    'Efd0',zeros(ng,1),'Pm',zeros(ng,1),'Vref',zeros(ng,1), ...
    'state_names',{cell(ns*ng,1)},'newton_iterations',0);
nopt=struct('tolerance',opt.equilibrium_tolerance,'max_iter',100,'fd_eps',opt.fd_eps);
for k=1:ng
    b=u.bus_idx(k); V=complex(y0(2*b-1),y0(2*b));
    S=pf.P_generation(b)+1i*pf.Q_generation(b); I=conj(S/V);
    seed=angle(V+(m.Ra(k)+1i*m.Xq(k))*I);
    [delta,rv,info]=nonlinear_newton(@(d) angle_residual(d,V,I,m,k),seed,nopt);
    if ~info.converged || abs(rv)>1e-9
        error('padiyar_model11_dae:angleInit','Machine %d angle initialization failed.',k);
    end
    [Id,Iq]=to_dq(I,delta); [Vd,Vq]=to_dq(V,delta);
    Edp=(m.Xq(k)-m.Xqp(k))*Iq;
    Eqp=Vq+m.Ra(k)*Iq+m.Xdp(k)*Id;
    Efd=Eqp+(m.Xd(k)-m.Xdp(k))*Id;
    Te=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
    ii=(k-1)*ns; state=[delta;1;Eqp;Edp];
    names={sprintf('delta_%s',u.id{k});sprintf('omega_%s',u.id{k}); ...
        sprintf('Eqp_%s',u.id{k});sprintf('Edp_%s',u.id{k})};
    if strcmp(excitation,'avr')
        state=[state;Efd]; names=[names;{sprintf('Efd_%s',u.id{k})}]; %#ok<AGROW>
    end
    x0(ii+(1:ns))=state; init.state_names(ii+(1:ns))=names;
    init.Efd0(k)=Efd; init.Pm(k)=Te;
    init.Vref(k)=abs(V)+Efd/m.KA(k);
    init.newton_iterations=init.newton_iterations+info.iterations;
end
init.x0=x0; init.y0=y0;
end

function r=angle_residual(delta,V,I,m,k)
[Id,Iq]=to_dq(I,delta); [Vd,~]=to_dq(V,delta);
r=Vd+m.Ra(k)*Id-m.Xq(k)*Iq;
end

function dx=differential_residual(x,y,init,m,u,excitation)
ns=init.states_per_machine; dx=zeros(size(x));
for k=1:m.ng
    ii=(k-1)*ns; [Id,Iq,Vd,Vq,V]=machine_algebraic(x,y,init,m,k);
    omega=x(ii+2); Eqp=x(ii+3); Edp=x(ii+4);
    if strcmp(excitation,'avr'), Efd=x(ii+5); else, Efd=init.Efd0(k); end
    Te=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
    dx(ii+1)=m.wB*(omega-1);
    dx(ii+2)=(init.Pm(k)-Te-u.D(k)*(omega-1))/(2*u.H(k));
    dx(ii+3)=(Efd-Eqp-(m.Xd(k)-m.Xdp(k))*Id)/m.Tpd0(k);
    dx(ii+4)=(-Edp+(m.Xq(k)-m.Xqp(k))*Iq)/m.Tpq0(k);
    if strcmp(excitation,'avr')
        dx(ii+5)=(m.KA(k)*(init.Vref(k)-abs(V))-Efd)/m.TA(k);
    end
end
end

function g=network_residual(x,y,init,m,Y)
V=complex(y(1:2:end),y(2:2:end)); Inet=Y*V; nb=numel(V);
gc=-Inet;
for k=1:m.ng
    [Id,Iq,~,~,~]=machine_algebraic(x,y,init,m,k);
    ii=(k-1)*init.states_per_machine; delta=x(ii+1);
    Ig=from_dq_current(Id,Iq,delta); b=init.bus_idx(k); gc(b)=gc(b)+Ig;
end
g=zeros(2*nb,1); g(1:2:end)=real(gc); g(2:2:end)=imag(gc);
end

function [Id,Iq,Vd,Vq,V]=machine_algebraic(x,y,init,m,k)
ns=init.states_per_machine; ii=(k-1)*ns; delta=x(ii+1);
Eqp=x(ii+3); Edp=x(ii+4); b=init.bus_idx(k);
V=complex(y(2*b-1),y(2*b)); [Vd,Vq]=to_dq(V,delta);
rd=Vd-Edp; rq=Vq-Eqp; den=m.Ra(k)^2+m.Xdp(k)*m.Xqp(k);
Id=(-m.Ra(k)*rd-m.Xqp(k)*rq)/den;
Iq=(m.Xdp(k)*rd-m.Ra(k)*rq)/den;
end

function Pe=electrical_power(x,y,init,m)
Pe=zeros(m.ng,1);
for k=1:m.ng
    [Id,Iq,Vd,Vq]=machine_algebraic(x,y,init,m,k);
    Pe(k)=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
end
end

function Q=reactive_power(x,y,init,m)
Q=zeros(m.ng,1);
for k=1:m.ng
    [Id,Iq,~,~,V]=machine_algebraic(x,y,init,m,k);
    ii=(k-1)*init.states_per_machine;
    I=from_dq_current(Id,Iq,x(ii+1)); Q(k)=imag(V*conj(I));
end
end

function I=all_currents(x,y,init,m)
I=zeros(m.ng,1);
for k=1:m.ng
    [Id,Iq]=machine_algebraic(x,y,init,m,k);
    ii=(k-1)*init.states_per_machine; I(k)=from_dq_current(Id,Iq,x(ii+1));
end
end

function [d,q]=to_dq(z,delta)
d=sin(delta)*real(z)-cos(delta)*imag(z);
q=cos(delta)*real(z)+sin(delta)*imag(z);
end

function I=from_dq_current(Id,Iq,delta)
I=(sin(delta)*Id+cos(delta)*Iq)+1i*(-cos(delta)*Id+sin(delta)*Iq);
end

function [Y,load]=network_model(c,pf)
nb=numel(pf.external_bus_ids); Y=complex(zeros(nb)); L=c.line_data;
for l=1:size(L,1)
    i=find(pf.external_bus_ids==L(l,1),1); j=find(pf.external_bus_ids==L(l,2),1);
    ys=1/(L(l,3)+1i*L(l,4)); bh=L(l,5);
    Y(i,i)=Y(i,i)+ys+1i*bh; Y(j,j)=Y(j,j)+ys+1i*bh;
    Y(i,j)=Y(i,j)-ys; Y(j,i)=Y(j,i)-ys;
end
B=c.bus_data; load.P=B(:,7); load.Q=B(:,8); load.V0=pf.bus_voltage;
for b=1:nb
    Y(b,b)=Y(b,b)+B(b,9)+1i*B(b,10);
    Y(b,b)=Y(b,b)+(load.P(b)-1i*load.Q(b))/load.V0(b)^2;
end
end
