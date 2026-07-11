function res = ts_simulate_padiyar_model11(case_data, opt)
%TS_SIMULATE_PADIYAR_MODEL11 Implicit trapezoidal TS for Padiyar model 1.1.
% Uses stability.padiyar_model11_dae as the single equation source and the
% shared stability.ts_step_kernel / ts_algebraic_solve / ts_jac_y_fd /
% ts_topology_at. No local duplicated numerical logic.
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
alg_iters=zeros(nt-1,1); alg_res=zeros(nt-1,1);
kopt=struct('algebraic_tolerance',opt.algebraic_tolerance, ...
    'max_corrector_iter',opt.max_corrector_iter, ...
    'corrector_abs_tol',opt.corrector_abs_tol, ...
    'corrector_rel_tol',opt.corrector_rel_tol);

for it=1:nt-1
    h=t(it+1)-t(it);
    Ynow=stability.ts_topology_at(t(it),opt,Ypre,Yfault,Ypost);
    % Always refresh Jyy from current (x,y,Y) — no cross-step caching.
    Jyy=stability.ts_jac_y_fd(x,y,Ynow,g);
    [y,alg_info]=stability.ts_algebraic_solve(x,y,Ynow,g,@stability.ts_jac_y_fd,opt.algebraic_tolerance,Jyy);
    check_algebraic(alg_info,t(it),it,opt.algebraic_tolerance);
    alg_iters(it)=alg_info.iterations; alg_res(it)=alg_info.final_residual;
    f0=f(x,y); record(it);
    step=stability.ts_step_kernel(x,y,h,f,g,Ynow,Jyy,kopt);
    citer(it)=step.corrector_iterations; cres(it)=step.corrector_residual;
    cupd(it)=step.corrector_update; cconv(it)=step.corrector_converged;
    if ~step.corrector_converged
        nonconv=nonconv+1;
        if strcmp(opt.corrector_failure,'error')
            error('ts_simulate_padiyar_model11:corrector', ...
                ['Corrector failed at t=%.6g (step %d): update=%.3e, ' ...
                'trapezoidal residual=%.3e, algebraic residual=%.3e, ' ...
                'iters=%d, dt=%.4g.'], ...
                t(it+1),it,cupd(it),cres(it),step.algebraic_residual, ...
                step.corrector_iterations,h);
        end
    end
    x=step.x_full;
    Ynext=stability.ts_topology_at(t(it+1),opt,Ypre,Yfault,Ypost);
    Jyy=stability.ts_jac_y_fd(x,step.y_full,Ynext,g);
    [y,alg_info2]=stability.ts_algebraic_solve(x,step.y_full,Ynext,g,@stability.ts_jac_y_fd,opt.algebraic_tolerance,Jyy);
    check_algebraic(alg_info2,t(it+1),it,opt.algebraic_tolerance);
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
    'algebraic_iterations',alg_iters,'algebraic_residual',alg_res, ...
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
fns=fieldnames(d); for k=1:numel(fns), if ~isfield(opt,fns{k}), opt.(fns{k})=d.(fns{k}); end, end
end

function check_algebraic(info,t_now,it,tol)
% Requirement: caller MUST check algebraic convergence every time.
% Never return an unconverged algebraic state and continue.
if ~info.converged
    error('ts_simulate_padiyar_model11:algebraic', ...
        ['Algebraic solve did not converge at t=%.6g (step %d): ' ...
        'residual=%.3e (tol=%.3e), iterations=%d, line_search_failures=%d.'], ...
        t_now,it,info.final_residual,tol,info.iterations,info.line_search_failures);
end
end
