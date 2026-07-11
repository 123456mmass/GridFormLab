function res = ts_simulate_padiyar_model11(case_data, opt)
%TS_SIMULATE_PADIYAR_MODEL11 Implicit trapezoidal TS for Padiyar model 1.1.
% Uses stability.padiyar_model11_dae as the single equation source.
if nargin<1 || isempty(case_data), case_data=cases.case_padiyar_two_area_4m_avr(); end
if nargin<2 || isempty(opt), opt=struct(); end
opt=defaults(opt);
dae=stability.padiyar_model11_dae(case_data,opt);
x=dae.x0(:); y=dae.y0(:); ns=dae.ns; ng=dae.ng; nb=dae.nb;
f=dae.dae_f; g=dae.dae_g; Ypre=dae.Ynet; Ypost=Ypre;

fb=find(dae.bus_ids==opt.fault_bus,1);
if isempty(fb), error('ts_simulate_padiyar_model11:faultBus','Unknown fault bus.'); end
Yfault=Ypre;
if opt.fault_enabled
    if isempty(opt.Zf)
        Yfault(fb,:)=0; Yfault(:,fb)=0; Yfault(fb,fb)=1;
    else
        Yfault(fb,fb)=Yfault(fb,fb)+1/opt.Zf;
    end
end

t=(0:opt.dt:opt.t_end).';
if t(end)<opt.t_end, t=[t;opt.t_end]; end %#ok<AGROW>
events=[];
if opt.fault_enabled
    events=[opt.t_fault opt.t_clear];
    for et=events
        if et>t(1) && et<t(end)
            [~,j]=min(abs(t-et)); t(j)=et;
        end
    end
end
t=unique(t,'stable'); nt=numel(t);

delta=zeros(nt,ng); omega=zeros(nt,ng); Eqp=zeros(nt,ng); Edp=zeros(nt,ng);
Efd=nan(nt,ng); Pe=zeros(nt,ng); Qe=zeros(nt,ng); Vbus=zeros(nt,nb);
citer=zeros(nt-1,1); cres=zeros(nt-1,1); cupd=zeros(nt-1,1);
cconv=true(nt-1,1); nonconv=0;
kopt=struct('algebraic_tolerance',opt.algebraic_tolerance, ...
    'max_corrector_iter',opt.max_corrector_iter, ...
    'corrector_abs_tol',opt.corrector_abs_tol, ...
    'corrector_rel_tol',opt.corrector_rel_tol);
Ynow=Ypre;

for it=1:nt-1
    h=t(it+1)-t(it); Yn=topology(t(it),opt,Ypre,Yfault,Ypost);
    Ynow=Yn; Jyy=jac_y(x,y,Ynow,g);
    y=solve_g(x,y,Ynow,g,Jyy,opt.algebraic_tolerance);
    f0=f(x,y); record(it);
    step=stability.ts_step_kernel(x,y,h,f,g,Ynow,Jyy,kopt);
    citer(it)=step.corrector_iterations; cres(it)=step.corrector_residual;
    cupd(it)=step.corrector_update; cconv(it)=step.corrector_converged;
    if ~step.corrector_converged
        nonconv=nonconv+1;
        if strcmp(opt.corrector_failure,'error')
            error('ts_simulate_padiyar_model11:corrector', ...
                'Corrector failed at t=%.6g: update %.3e residual %.3e.',t(it+1),cupd(it),cres(it));
        end
    end
    x=step.x_full;
    Ynext=topology(t(it+1),opt,Ypre,Yfault,Ypost);
    Ynow=Ynext; Jyy=jac_y(x,step.y_full,Ynow,g);
    y=solve_g(x,step.y_full,Ynow,g,Jyy,opt.algebraic_tolerance);
end
record(nt);

res=struct('t',t,'delta',delta,'omega',omega,'Eqp',Eqp,'Edp',Edp,'Efd',Efd, ...
    'Pe_pu',Pe,'Pe_MW',Pe*case_data.base_values.S_base_MVA,'Qe_pu',Qe, ...
    'Vbus',Vbus,'bus_ids',dae.bus_ids,'gen_buses',dae.gen_buses, ...
    'pf',dae.pf,'model','padiyar_model_1_1','excitation',dae.excitation, ...
    'method','trapezoidal','dt',opt.dt,'t_end',opt.t_end, ...
    'H',dae.units.H,'D',dae.units.D,'omega_is_deviation',false, ...
    'fault_enabled',opt.fault_enabled,'fault_bus',opt.fault_bus, ...
    't_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'initial_dae_residual',dae.initial_residual, ...
    'corrector_iterations',citer,'corrector_residual',cres, ...
    'corrector_update_norm',cupd,'corrector_converged',cconv, ...
    'nonconverged_step_count',nonconv,'max_corrector_residual',max(cres), ...
    'dae',dae);

    function record(k)
        delta(k,:)=x(1:ns:end).'; omega(k,:)=x(2:ns:end).';
        Eqp(k,:)=x(3:ns:end).'; Edp(k,:)=x(4:ns:end).';
        if ns==5, Efd(k,:)=x(5:ns:end).'; end
        Pe(k,:)=dae.electrical_power(x,y).'; Qe(k,:)=dae.reactive_power(x,y).';
        Vbus(k,:)=abs(complex(y(1:2:end),y(2:2:end))).';
    end
end

function opt=defaults(opt)
d=struct('excitation','avr','t_end',10,'dt',0.01,'fault_enabled',true, ...
    'fault_bus',3,'t_fault',1,'t_clear',1.1,'Zf',1i*0.1, ...
    'max_corrector_iter',12,'corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'corrector_failure','error', ...
    'algebraic_tolerance',1e-11,'equilibrium_tolerance',1e-10,'fd_eps',1e-6);
f=fieldnames(d); for k=1:numel(f), if ~isfield(opt,f{k}), opt.(f{k})=d.(f{k}); end, end
end

function Y=topology(t,opt,Ypre,Yfault,Ypost)
if ~opt.fault_enabled, Y=Ypre;
elseif t<opt.t_fault, Y=Ypre;
elseif t<opt.t_clear, Y=Yfault;
else, Y=Ypost; end
end

function y=solve_g(x,y,Y,g,J,tol)
for k=1:30
    r=g(x,y,Y); nr=norm(r,inf); if nr<=tol, return; end
    step=-(J\r); alpha=1; accepted=false;
    while alpha>=2^-16
        yt=y+alpha*step; rt=g(x,yt,Y);
        if all(isfinite(rt)) && norm(rt,inf)<nr, y=yt; accepted=true; break; end
        alpha=alpha/2;
    end
    if ~accepted, J=jac_y(x,y,Y,g); end
end
if norm(g(x,y,Y),inf)>100*tol
    error('ts_simulate_padiyar_model11:algebraic','Algebraic solve failed.');
end
end

function J=jac_y(x,y,Y,g)
n=numel(y); J=zeros(n);
for j=1:n
    h=1e-7*(1+abs(y(j))); yp=y; ym=y; yp(j)=yp(j)+h; ym(j)=ym(j)-h;
    J(:,j)=(g(x,yp,Y)-g(x,ym,Y))/(2*h);
end
end
