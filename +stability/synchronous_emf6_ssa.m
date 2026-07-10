function result = synchronous_emf6_ssa(case_data, options)
%SYNCHRONOUS_EMF6_SSA Operational sixth-order synchronous-machine DAE.
% States per machine: [delta, omega, E'q, E'd, E''q, E''d].
% The differential equations are the six-equation Kundur/GENTPJ form used
% in the project report and requested for the benchmark comparison.

if nargin < 1 || isempty(case_data)
    error('synchronous_emf6_ssa:caseRequired','case_data is required.');
end
if nargin < 2 || isempty(options), options=struct(); end
options=defaults(options,case_data);
pf_init_paths();

pf=pfsolver.powerflow_newton_raphson(case_data,struct('verbose',false, ...
    'plot_results',false,'tolerance',options.equilibrium_tolerance, ...
    'max_iter',options.newton_max_iterations,'enforce_q_limits',false));
if ~pf.converged
    error('synchronous_emf6_ssa:powerFlow','FSOLVE power flow did not converge.');
end

[m,u]=machine_parameters(case_data,pf);
[Ynet,load]=network_model(case_data,pf,options);
[init,x0,y0]=initialize_equilibrium(case_data,pf,m,u,options);
f=@(x,y) differential_residual(x,y,init,m,u);
g=@(x,y) network_residual(x,y,init,m,Ynet,load,options);
g_with_network=@(x,y,Y) network_residual(x,y,init,m,Y,load,options);
rf=f(x0,y0); rg=g(x0,y0);
nr=norm([rf;rg],inf);
if nr>100*options.equilibrium_tolerance
    error('synchronous_emf6_ssa:equilibrium', ...
        'EMF6 equilibrium residual %.3e exceeds tolerance.',nr);
end

[Jxx,Jxy,Jyx,Jyy]=numerical_jacobian(f,g,x0,y0,options.fd_eps);
model=struct('x0',x0,'y0',y0,'f',f,'g',g, ...
    'Jxx',Jxx,'Jxy',Jxy,'Jyx',Jyx,'Jyy',Jyy, ...
    'free_y',1:numel(y0),'reduction','coi','ng',init.ng, ...
    'states_per_machine',6,'angle_state_index',1,'speed_state_index',2, ...
    'inertia',u.H_system,'state_names',{init.state_names}, ...
    'metadata',struct('engine','stability.multimachine_ssa', ...
    'model','operational sixth-order EMF', ...
    'power_flow','pfsolver.powerflow_newton_raphson', ...
    'benchmark',char(case_data.system_name)));
result=stability.multimachine_ssa(model);
result.init=init; result.machine=m; result.Ynet=Ynet; result.pf=pf;
result.debug_residual_f=rf; result.debug_residual_g=rg;
result.fd_eps=options.fd_eps; result.case_data=case_data;
result.newton_iterations=init.newton_iterations;
result.newton_residual=nr; result.dae_f=f; result.dae_g=g_with_network;
result.electrical_power=@(x,y) electrical_power_from_swing(x,y,f,init,u);
result.units=u; result.options=options;
result.coefficients=struct('c_d',m.c_d,'d_d',m.d_d, ...
    'c_q',m.c_q,'d_q',m.d_q);
result.state_layout=struct('states_per_machine',6, ...
    'delta_index',1,'speed_index',2, ...
    'names',{{'delta','omega','Eqp','Edp','Eqpp','Edpp'}});
angle_shift=zeros(numel(x0),1); angle_shift(1:6:end)=1;
result.angle_shift_residual=norm(result.Afull*angle_shift);
end

function opt=defaults(opt,c)
if ~isfield(opt,'fd_eps'), opt.fd_eps=3e-6; end
if ~isfield(opt,'equilibrium_tolerance'), opt.equilibrium_tolerance=1e-10; end
if ~isfield(opt,'newton_max_iterations'), opt.newton_max_iterations=300; end
if ~isfield(opt,'load_model')
    if isfield(c,'operating_point') && isfield(c.operating_point,'load_model')
        opt.load_model=c.operating_point.load_model;
    else
        opt.load_model='cz_p_cz_q';
    end
end
end

function [m,u]=machine_parameters(c,pf)
M=c.machines; ng=numel(M.units); Sbase=c.base_values.S_base_MVA;
Sm=expand(M.base.S_MVA,ng); scale=Sbase./Sm; R=M.reactances; T=M.time_constants;
m.Xd=expand(R.Xd,ng).*scale; m.Xdp=expand(R.Xdp,ng).*scale;
m.Xdpp=expand(R.Xdpp,ng).*scale; m.Xq=expand(R.Xq,ng).*scale;
m.Xqp=expand(R.Xqp,ng).*scale; m.Xqpp=expand(R.Xqpp,ng).*scale;
m.Ra=expand(R.Ra,ng).*scale;
m.Tpd0=expand(T.Tpd0,ng); m.Tppd0=expand(T.Tppd0,ng);
m.Tpq0=expand(T.Tpq0,ng); m.Tppq0=expand(T.Tppq0,ng);
m.c_d=(m.Xd-m.Xdp)./(m.Xdp-m.Xdpp);
m.d_d=(m.Xd-m.Xdpp)./(m.Xdp-m.Xdpp);
m.c_q=(m.Xq-m.Xqp)./(m.Xqp-m.Xqpp);
m.d_q=(m.Xq-m.Xqpp)./(m.Xqp-m.Xqpp);
m.w0=2*pi*c.base_values.frequency_Hz; m.ng=ng;
u.bus_idx=zeros(ng,1); u.H_system=zeros(ng,1); u.D_system=zeros(ng,1);
u.H_machine=zeros(ng,1); u.D_machine=zeros(ng,1); u.id=cell(ng,1);
for k=1:ng
    u.bus_idx(k)=find(pf.external_bus_ids==M.units(k).bus,1);
    u.H_system(k)=M.units(k).H/scale(k); u.D_system(k)=M.units(k).D/scale(k);
    u.H_machine(k)=M.units(k).H; u.D_machine(k)=M.units(k).D;
    u.id{k}=M.units(k).gen_id;
end
end

function v=expand(v,n)
v=v(:); if numel(v)==1, v=repmat(v,n,1); end
if numel(v)~=n
    error('synchronous_emf6_ssa:machineData','Machine parameter length mismatch.');
end
end

function [init,x0,y0]=initialize_equilibrium(~,pf,m,u,opt)
ng=m.ng; nb=numel(pf.external_bus_ids); x0=zeros(6*ng,1); y0=zeros(2*nb,1);
for b=1:nb
    V=pf.bus_voltage(b)*exp(1i*deg2rad(pf.bus_angle_deg(b)));
    y0(2*b-1:2*b)=[real(V);imag(V)];
end
init=struct('ng',ng,'bus_idx',u.bus_idx,'Efd',zeros(ng,1), ...
    'Tm',zeros(ng,1),'Id',zeros(ng,1),'Iq',zeros(ng,1), ...
    'state_names',{cell(6*ng,1)},'newton_iterations',0);
nopt=struct('tolerance',opt.equilibrium_tolerance, ...
    'max_iter',opt.newton_max_iterations,'fd_eps',opt.fd_eps);
for k=1:ng
    b=u.bus_idx(k); V=complex(y0(2*b-1),y0(2*b));
    S=pf.P_generation(b)+1i*pf.Q_generation(b); It=conj(S/V);
    seed=angle(V+(m.Ra(k)+1i*m.Xq(k))*It);
    [delta,rv,info]=nonlinear_newton(@(d) angle_residual(d,V,It,m,k),seed,nopt);
    if ~info.converged || abs(rv)>1e-9
        error('synchronous_emf6_ssa:angleInit','Machine %d initialization failed.',k);
    end
    init.newton_iterations=init.newton_iterations+info.iterations;
    [Id,Iq]=stability.kundur_book_dq(It,delta);
    [Vd,Vq]=stability.kundur_book_dq(V,delta);
    Eqpp=Vq+m.Ra(k)*Iq+m.Xdpp(k)*Id;
    Edpp=Vd+m.Ra(k)*Id-m.Xqpp(k)*Iq;
    Eqp=Eqpp+(m.Xdp(k)-m.Xdpp(k))*Id;
    Edp=Edpp-(m.Xqp(k)-m.Xqpp(k))*Iq;
    Efd=m.d_d(k)*Eqp-m.c_d(k)*Eqpp;
    Te=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
    ii=(k-1)*6; x0(ii+(1:6))=[delta;0;Eqp;Edp;Eqpp;Edpp];
    init.Efd(k)=Efd; init.Tm(k)=Te; init.Id(k)=Id; init.Iq(k)=Iq;
    id=u.id{k}; init.state_names(ii+(1:6))={sprintf('\\delta_{%s}',id); ...
        sprintf('\\omega_{%s}',id);sprintf('E''_{q,%s}',id); ...
        sprintf('E''_{d,%s}',id);sprintf('E''''_{q,%s}',id); ...
        sprintf('E''''_{d,%s}',id)};
end
init.x0=x0; init.y0=y0;
end

function value=angle_residual(delta,V,I,m,k)
[Id,Iq]=stability.kundur_book_dq(I,delta);
[Vd,~]=stability.kundur_book_dq(V,delta);
value=Vd+m.Ra(k)*Id-m.Xq(k)*Iq;
end

function dx=differential_residual(x,y,init,m,u)
dx=zeros(size(x));
for k=1:m.ng
    ii=(k-1)*6; [Id,Iq,Vd,Vq]=machine_algebraic(x,y,init,m,k);
    w=x(ii+2); Eqp=x(ii+3); Edp=x(ii+4); Eqpp=x(ii+5); Edpp=x(ii+6);
    Te=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
    dx(ii+1)=m.w0*w;
    dx(ii+2)=(init.Tm(k)-Te-u.D_system(k)*w)/(2*u.H_system(k));
    dx(ii+3)=(init.Efd(k)+m.c_d(k)*Eqpp-m.d_d(k)*Eqp)/m.Tpd0(k);
    dx(ii+4)=(m.c_q(k)*Edpp-m.d_q(k)*Edp)/m.Tpq0(k);
    dx(ii+5)=(Eqp-Eqpp-(m.Xdp(k)-m.Xdpp(k))*Id)/m.Tppd0(k);
    dx(ii+6)=(Edp-Edpp+(m.Xqp(k)-m.Xqpp(k))*Iq)/m.Tppq0(k);
end
end

function g=network_residual(x,y,init,m,Ynet,load,opt)
V=complex(y(1:2:end),y(2:2:end)); Inet=Ynet*V; nb=numel(V);
g=zeros(2*nb,1); g(1:2:end)=-real(Inet); g(2:2:end)=-imag(Inet);
for b=1:nb
    if load.P(b)==0 && load.Q(b)==0, continue; end
    switch lower(opt.load_model)
        case {'cz','cz_p_cz_q'}, Iload=0;
        case {'cc_p_cz_q'}, Iload=(load.P(b)/load.V0(b))*(V(b)/abs(V(b)));
        otherwise, Iload=conj((load.P(b)+1i*load.Q(b))/V(b));
    end
    g(2*b-1:2*b)=g(2*b-1:2*b)-[real(Iload);imag(Iload)];
end
for k=1:m.ng
    [Id,Iq]=machine_algebraic(x,y,init,m,k);
    Ig=stability.kundur_book_network_current(Id,Iq,x((k-1)*6+1));
    b=init.bus_idx(k); g(2*b-1:2*b)=g(2*b-1:2*b)+[real(Ig);imag(Ig)];
end
end

function [Id,Iq,Vd,Vq]=machine_algebraic(x,y,init,m,k)
ii=(k-1)*6; delta=x(ii+1); Eqpp=x(ii+5); Edpp=x(ii+6);
b=init.bus_idx(k); V=complex(y(2*b-1),y(2*b));
[Vd,Vq]=stability.kundur_book_dq(V,delta);
rhs_d=Vd-Edpp; rhs_q=Vq-Eqpp;
det=m.Xdpp(k)*m.Xqpp(k)+m.Ra(k)^2;
Id=(-m.Ra(k)*rhs_d-m.Xqpp(k)*rhs_q)/det;
Iq=(m.Xdpp(k)*rhs_d-m.Ra(k)*rhs_q)/det;
end

function [Y,load]=network_model(c,pf,opt)
nb=numel(pf.external_bus_ids); Y=complex(zeros(nb)); LD=c.line_data;
for l=1:size(LD,1)
    i=find(pf.external_bus_ids==LD(l,1),1); j=find(pf.external_bus_ids==LD(l,2),1);
    ys=1/(LD(l,3)+1i*LD(l,4)); bh=0; if size(LD,2)>=5, bh=LD(l,5); end
    Y(i,i)=Y(i,i)+ys+1i*bh; Y(j,j)=Y(j,j)+ys+1i*bh;
    Y(i,j)=Y(i,j)-ys; Y(j,i)=Y(j,i)-ys;
end
BD=c.bus_data; load.P=BD(:,7); load.Q=BD(:,8); load.V0=pf.bus_voltage;
for b=1:nb
    if size(BD,2)>=10, Y(b,b)=Y(b,b)+BD(b,9)+1i*BD(b,10); end
    switch lower(opt.load_model)
        case {'cz','cz_p_cz_q'}
            Y(b,b)=Y(b,b)+(load.P(b)-1i*load.Q(b))/load.V0(b)^2;
        case {'cc_p_cz_q'}
            Y(b,b)=Y(b,b)-1i*load.Q(b)/load.V0(b)^2;
    end
end
end

function [Jxx,Jxy,Jyx,Jyy]=numerical_jacobian(f,g,x,y,h)
nx=numel(x); ny=numel(y); Jxx=zeros(nx); Jxy=zeros(nx,ny);
Jyx=zeros(ny,nx); Jyy=zeros(ny);
for i=1:nx
    xp=x; xm=x; xp(i)=xp(i)+h; xm(i)=xm(i)-h;
    Jxx(:,i)=(f(xp,y)-f(xm,y))/(2*h); Jyx(:,i)=(g(xp,y)-g(xm,y))/(2*h);
end
for j=1:ny
    yp=y; ym=y; yp(j)=yp(j)+h; ym(j)=ym(j)-h;
    Jxy(:,j)=(f(x,yp)-f(x,ym))/(2*h); Jyy(:,j)=(g(x,yp)-g(x,ym))/(2*h);
end
end

function Pe=electrical_power_from_swing(x,y,f,init,u)
dx=f(x,y); Pe=zeros(init.ng,1);
for k=1:init.ng
    ii=(k-1)*6; w=x(ii+2);
    Pe(k)=init.Tm(k)-u.D_system(k)*w-2*u.H_system(k)*dx(ii+2);
end
end
