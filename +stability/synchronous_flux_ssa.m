function result = synchronous_flux_ssa(case_data, options)
%SYNCHRONOUS_FLUX_SSA Generic primitive-flux multimachine SSSA engine.
%   The machine states are [delta, omega, psi_fd, psi_1d, psi_1q, psi_2q].
%   Rotor circuit parameters are derived from each case's published
%   transient/subtransient reactances and open-circuit time constants.

if nargin < 1 || isempty(case_data)
    error('synchronous_flux_ssa:caseRequired', 'case_data is required.');
end
if nargin < 2 || isempty(options), options = struct(); end
options = defaults(options, case_data);
pf_init_paths();

pf = pfsolver.powerflow_fsolve(case_data, struct('verbose',false, ...
    'plot_results',false,'tolerance',options.equilibrium_tolerance, ...
    'max_iter',options.fsolve_max_iterations));
if ~pf.converged
    error('synchronous_flux_ssa:powerFlow', 'FSOLVE power flow did not converge.');
end

[machine, units] = machine_parameters(case_data, pf);
[Ynet, load] = network_model(case_data, pf, options);
[init, x0, y0] = initialize_equilibrium(case_data, pf, machine, units, options);

f = @(x,y) differential_residual(x,y,init,machine,units,options);
g = @(x,y) network_residual(x,y,init,machine,Ynet,load,options);
residual_f = f(x0,y0); residual_g = g(x0,y0);
if norm([residual_f;residual_g],inf) > 100*options.equilibrium_tolerance
    error('synchronous_flux_ssa:equilibrium', ...
        'Flux-state equilibrium residual %.3e exceeds tolerance.', ...
        norm([residual_f;residual_g],inf));
end

[Jxx,Jxy,Jyx,Jyy] = numerical_jacobian(f,g,x0,y0,options.fd_eps);
model = struct('x0',x0,'y0',y0,'f',f,'g',g, ...
    'Jxx',Jxx,'Jxy',Jxy,'Jyx',Jyx,'Jyy',Jyy, ...
    'free_y',1:numel(y0),'reduction','coi','ng',init.ng, ...
    'states_per_machine',6,'angle_state_index',1,'speed_state_index',2, ...
    'inertia',units.H_system,'state_names',{init.state_names}, ...
    'metadata',struct('engine','stability.multimachine_ssa', ...
        'model','primitive rotor flux linkage', ...
        'power_flow','pfsolver.powerflow_fsolve', ...
        'benchmark',char(case_data.system_name)));
result = stability.multimachine_ssa(model);
result.init = init;
result.machine = machine;
result.Ynet = Ynet;
result.pf = pf;
result.debug_residual_f = residual_f;
result.debug_residual_g = residual_g;
result.fd_eps = options.fd_eps;
result.case_data = case_data;
angle_shift = zeros(numel(x0),1); angle_shift(1:6:end)=1;
result.angle_shift_residual = norm(result.Afull*angle_shift);
result.equilibrium_solver = 'fsolve';
result.newton_iterations = init.fsolve_iterations;
end

function options = defaults(options, case_data)
if ~isfield(options,'fd_eps'), options.fd_eps=3e-6; end
if ~isfield(options,'equilibrium_tolerance'), options.equilibrium_tolerance=1e-10; end
if ~isfield(options,'fsolve_max_iterations'), options.fsolve_max_iterations=300; end
if ~isfield(options,'load_model')
    if isfield(case_data,'operating_point') && isfield(case_data.operating_point,'load_model')
        options.load_model=case_data.operating_point.load_model;
    else
        options.load_model='cz_p_cz_q';
    end
end
if ~isfield(options,'use_saturation'), options.use_saturation=isfield(case_data,'saturation'); end
if ~isfield(options,'sat_q_axis'), options.sat_q_axis=true; end
if ~isfield(options,'saturation')
    if isfield(case_data,'saturation'), options.saturation=case_data.saturation;
    else, options.saturation=struct('Asat',0,'Bsat',0,'PsiT1',inf); end
end
end

function [m,u] = machine_parameters(c,pf)
M=c.machines; ng=numel(M.units); Sbase=c.base_values.S_base_MVA;
Sm=expand(M.base.S_MVA,ng); scale=Sbase./Sm;
R=M.reactances; T=M.time_constants;
m.Xd=expand(R.Xd,ng).*scale; m.Xq=expand(R.Xq,ng).*scale;
m.Xl=expand(R.Xl,ng).*scale; m.Xdp=expand(R.Xdp,ng).*scale;
m.Xqp=expand(R.Xqp,ng).*scale; m.Xdpp=expand(R.Xdpp,ng).*scale;
m.Xqpp=expand(R.Xqpp,ng).*scale; m.Ra=expand(R.Ra,ng).*scale;
m.Tpd0=expand(T.Tpd0,ng); m.Tpq0=expand(T.Tpq0,ng);
m.Tppd0=expand(T.Tppd0,ng); m.Tppq0=expand(T.Tppq0,ng);
m.Xad=m.Xd-m.Xl; m.Xaq=m.Xq-m.Xl;
m.Xfdl=m.Xad.*(m.Xdp-m.Xl)./(m.Xd-m.Xdp);
m.X1dl=1./(1./(m.Xdpp-m.Xl)-1./m.Xad-1./m.Xfdl);
m.X1ql=m.Xaq.*(m.Xqp-m.Xl)./(m.Xq-m.Xqp);
m.X2ql=1./(1./(m.Xqpp-m.Xl)-1./m.Xaq-1./m.X1ql);
w=2*pi*c.base_values.frequency_Hz;
m.Rfd=(m.Xad+m.Xfdl)./(w*m.Tpd0);
m.R1d=(m.X1dl+1./(1./m.Xad+1./m.Xfdl))./(w*m.Tppd0);
m.R1q=(m.Xaq+m.X1ql)./(w*m.Tpq0);
m.R2q=(m.X2ql+1./(1./m.Xaq+1./m.X1ql))./(w*m.Tppq0);
m.w0=w; m.ng=ng;

u.bus_idx=zeros(ng,1); u.H_system=zeros(ng,1); u.D_system=zeros(ng,1);
u.id=cell(ng,1);
for k=1:ng
    u.bus_idx(k)=find(pf.external_bus_ids==M.units(k).bus,1);
    u.H_system(k)=M.units(k).H/scale(k);
    u.D_system(k)=M.units(k).D/scale(k);
    u.id{k}=M.units(k).gen_id;
end
end

function v = expand(v,n)
v=v(:); if numel(v)==1, v=repmat(v,n,1); end
if numel(v)~=n, error('synchronous_flux_ssa:machineData','Machine parameter length mismatch.'); end
end

function [init,x0,y0] = initialize_equilibrium(c,pf,m,u,opt)
ng=m.ng; nb=numel(pf.external_bus_ids); x0=zeros(6*ng,1); y0=zeros(2*nb,1);
for b=1:nb
    V=pf.bus_voltage(b)*exp(1i*deg2rad(pf.bus_angle_deg(b)));
    y0(2*b-1:2*b)=[real(V);imag(V)];
end
init=struct('ng',ng,'bus_idx',u.bus_idx,'Efd',zeros(ng,1), ...
    'Tm',zeros(ng,1),'Id',zeros(ng,1),'Iq',zeros(ng,1), ...
    'psi_ad',zeros(ng,1),'psi_aq',zeros(ng,1), ...
    'state_names',{cell(6*ng,1)},'fsolve_iterations',0);
fsopt=optimoptions('fsolve','Display','off', ...
    'FunctionTolerance',opt.equilibrium_tolerance, ...
    'OptimalityTolerance',opt.equilibrium_tolerance, ...
    'StepTolerance',1e-13,'MaxIterations',opt.fsolve_max_iterations, ...
    'MaxFunctionEvaluations',3000);
for k=1:ng
    b=u.bus_idx(k); V=complex(y0(2*b-1),y0(2*b));
    S=pf.P_generation(b)+1i*pf.Q_generation(b); It=conj(S/V);
    seed=angle(V+(m.Ra(k)+1i*m.Xq(k))*It);
    [delta,rv,flag,out]=fsolve(@(d) initial_angle_residual(d,V,It,m,k,opt),seed,fsopt);
    if flag<=0 || abs(rv)>1e-9
        error('synchronous_flux_ssa:angleInit','Machine %d initialization failed.',k);
    end
    init.fsolve_iterations=init.fsolve_iterations+out.iterations;
    [Id,Iq]=stability.kundur_book_dq(It,delta);
    [Vd,Vq]=stability.kundur_book_dq(V,delta);
    pad=Vq+m.Ra(k)*Iq+m.Xl(k)*Id;
    paq=-Vd-m.Ra(k)*Id+m.Xl(k)*Iq;
    [Sd,~]=saturation(pad,paq,m,k,opt);
    Ifd=Id+(pad+Sd)/m.Xad(k);
    psifd=pad+m.Xfdl(k)*Ifd; psi1d=pad; psi1q=paq; psi2q=paq;
    Te=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
    ii=(k-1)*6;
    x0(ii+(1:6))=[delta;0;psifd;psi1d;psi1q;psi2q];
    init.Efd(k)=m.Rfd(k)*Ifd; init.Tm(k)=Te;
    init.Id(k)=Id; init.Iq(k)=Iq; init.psi_ad(k)=pad; init.psi_aq(k)=paq;
    id=u.id{k}; init.state_names(ii+(1:6))={sprintf('\\delta_{%s}',id); ...
        sprintf('\\omega_{%s}',id);sprintf('\\psi_{fd,%s}',id); ...
        sprintf('\\psi_{1d,%s}',id);sprintf('\\psi_{1q,%s}',id); ...
        sprintf('\\psi_{2q,%s}',id)};
end
init.x0=x0; init.y0=y0;
end

function value = initial_angle_residual(delta,V,It,m,k,opt)
[id,iq]=stability.kundur_book_dq(It,delta);
[vd,vq]=stability.kundur_book_dq(V,delta);
ad=vq+m.Ra(k)*iq+m.Xl(k)*id;
aq=-vd-m.Ra(k)*id+m.Xl(k)*iq;
[~,Sq]=saturation(ad,aq,m,k,opt);
value=aq-m.Xaq(k)*(-iq)+Sq;
end

function dx = differential_residual(x,y,init,m,u,opt)
dx=zeros(size(x));
for k=1:m.ng
    ii=(k-1)*6; w=x(ii+2);
    [Id,Iq,Vd,Vq,pad,paq,Ifd,I1d,I1q,I2q]=machine_algebraic(x,y,init,m,k,opt);
    Te=Vd*Id+Vq*Iq+m.Ra(k)*(Id^2+Iq^2);
    dx(ii+1)=m.w0*w;
    dx(ii+2)=(init.Tm(k)-Te-u.D_system(k)*w)/(2*u.H_system(k));
    dx(ii+3)=m.w0*(init.Efd(k)-m.Rfd(k)*Ifd);
    dx(ii+4)=-m.w0*m.R1d(k)*I1d;
    dx(ii+5)=-m.w0*m.R1q(k)*I1q;
    dx(ii+6)=-m.w0*m.R2q(k)*I2q;
end
end

function g = network_residual(x,y,init,m,Ynet,load,opt)
V=complex(y(1:2:end),y(2:2:end)); Inet=Ynet*V; nb=numel(V);
g=zeros(2*nb,1); g(1:2:end)=-real(Inet); g(2:2:end)=-imag(Inet);
for b=1:nb
    if load.P(b)==0 && load.Q(b)==0, continue; end
    switch lower(opt.load_model)
        case {'cz','cz_p_cz_q'}
            Iload=0;
        case {'cc_p_cz_q'}
            Iload=(load.P(b)/load.V0(b))*(V(b)/abs(V(b)));
        otherwise
            Iload=conj((load.P(b)+1i*load.Q(b))/V(b));
    end
    g(2*b-1:2*b)=g(2*b-1:2*b)-[real(Iload);imag(Iload)];
end
for k=1:m.ng
    [Id,Iq]=machine_algebraic(x,y,init,m,k,opt);
    Ig=stability.kundur_book_network_current(Id,Iq,x((k-1)*6+1));
    b=init.bus_idx(k); g(2*b-1:2*b)=g(2*b-1:2*b)+[real(Ig);imag(Ig)];
end
end

function [Id,Iq,Vd,Vq,pad,paq,Ifd,I1d,I1q,I2q] = machine_algebraic(x,y,init,m,k,opt)
ii=(k-1)*6; delta=x(ii+1); psifd=x(ii+3); psi1d=x(ii+4);
psi1q=x(ii+5); psi2q=x(ii+6); b=init.bus_idx(k);
V=complex(y(2*b-1),y(2*b)); [Vd,Vq]=stability.kundur_book_dq(V,delta);
z0=[init.Id(k);init.Iq(k);init.psi_ad(k);init.psi_aq(k)];
fsopt=optimoptions('fsolve','Display','off','FunctionTolerance',1e-12, ...
    'OptimalityTolerance',1e-12,'StepTolerance',1e-13, ...
    'MaxIterations',100,'MaxFunctionEvaluations',1000);
[z,res,flag]=fsolve(@residual,z0,fsopt);
if flag<=0 || norm(res,inf)>1e-8
    error('synchronous_flux_ssa:statorSolve','Machine %d stator solve failed.',k);
end
Id=z(1); Iq=z(2); pad=z(3); paq=z(4);
Ifd=(psifd-pad)/m.Xfdl(k); I1d=(psi1d-pad)/m.X1dl(k);
I1q=(psi1q-paq)/m.X1ql(k); I2q=(psi2q-paq)/m.X2ql(k);
    function r=residual(q)
        id=q(1); iq=q(2); ad=q(3); aq=q(4);
        ifd=(psifd-ad)/m.Xfdl(k); i1d=(psi1d-ad)/m.X1dl(k);
        i1q=(psi1q-aq)/m.X1ql(k); i2q=(psi2q-aq)/m.X2ql(k);
        [Sd,Sq]=saturation(ad,aq,m,k,opt);
        r=[ad-m.Xl(k)*id-Vq-m.Ra(k)*iq; ...
            Vd+m.Ra(k)*id-m.Xl(k)*iq+aq; ...
            ad-m.Xad(k)*(-id+ifd+i1d)+Sd; ...
            aq-m.Xaq(k)*(-iq+i1q+i2q)+Sq];
    end
end

function [Sd,Sq] = saturation(pad,paq,m,k,opt)
Sd=0; Sq=0; if ~opt.use_saturation, return; end
mag=hypot(pad,paq); p=opt.saturation;
if mag<=p.PsiT1, return; end
psiI=p.Asat*exp(p.Bsat*(mag-p.PsiT1));
Sd=psiI*pad/mag;
Sq=psiI*paq/mag*(m.Xaq(k)/m.Xad(k));
if ~opt.sat_q_axis, Sq=0; end
end

function [Y,load] = network_model(c,pf,opt)
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

function [Jxx,Jxy,Jyx,Jyy] = numerical_jacobian(f,g,x,y,h)
nx=numel(x); ny=numel(y); Jxx=zeros(nx); Jxy=zeros(nx,ny);
Jyx=zeros(ny,nx); Jyy=zeros(ny);
for i=1:nx
    xp=x; xm=x; xp(i)=xp(i)+h; xm(i)=xm(i)-h;
    Jxx(:,i)=(f(xp,y)-f(xm,y))/(2*h); Jyx(:,i)=(g(xp,y)-g(xm,y))/(2*h);
end
for j=1:ny
    yp=y; ym=y; yp(j)=yp(j)+h; ym=y; ym(j)=ym(j)-h;
    Jxy(:,j)=(f(x,yp)-f(x,ym))/(2*h); Jyy(:,j)=(g(x,yp)-g(x,ym))/(2*h);
end
end
