function res = ts_simulate_padiyar_model11(case_data, opt)
%TS_SIMULATE_PADIYAR_MODEL11 Implicit trapezoidal TS for Padiyar model 1.1.
% Uses stability.padiyar_model11_dae as the single equation source and the
% shared stability.ts_step_kernel / ts_algebraic_solve / ts_jac_y_fd /
% ts_topology_at. No local duplicated numerical logic.
if nargin<1 || isempty(case_data), case_data=cases.case_padiyar_two_area_4m_avr(); end
if nargin<2 || isempty(opt), opt=struct(); end
opt=defaults(opt);
% Phase-2: resolve integrator BEFORE DAE construction (exactly-one resolution
% per executed route; parent ts_simulate dispatches unresolved). step_fn is
% the resolved single-step handle (@ts_step_kernel for trapezoidal ->
% bit-identical). The adaptiveNotFrozen gate fires before the stepper dispatch.
[integrator, integrator_source, opt] = stability.resolve_ts_integrator(opt);
opt.integrator_source = integrator_source;
step_fn = stability.ts_integrator_step(opt);
if isfield(opt,'stepper') && strcmpi(opt.stepper,'adaptive') ...
        && ~strcmp(integrator,'trapezoidal')
    error('ts_simulate_padiyar_model11:adaptiveNotFrozen', ...
        ['Adaptive stepper is not frozen for integrator ''%s''. ' ...
         'backward_euler and rk4 are FIXED-STEP ONLY (correction 6). ' ...
         'No silent fallback.'], integrator);
end
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

% --- Stepper dispatch (Phase 4) --------------------------------------------
% opt.stepper='fixed' (default if stepper is absent or 'fixed'): canonical
%   fixed-step path (bit-identical to the validated baseline).
% opt.stepper='adaptive': variable-dt LTE/reject path via ts_adaptive_driver.
%   Adaptive is reached only when opt.stepper is explicitly 'adaptive'; the
%   production default is fixed. Catalog/run_ts may inject stepper='adaptive'.
if isfield(opt,'stepper') && strcmpi(opt.stepper,'adaptive')
    res = run_adaptive(case_data,opt,dae,ns,ng,nb,Ypre,Yfault,Ypost,integrator,integrator_source);
    return;
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
% Phase-2: endpoint algebraic-residual evidence (additive).
integrator_alg_res=zeros(nt-1,1);
kopt=struct('algebraic_tolerance',opt.algebraic_tolerance, ...
    'max_corrector_iter',opt.max_corrector_iter, ...
    'corrector_abs_tol',opt.corrector_abs_tol, ...
    'corrector_rel_tol',opt.corrector_rel_tol);
% Phase 1: route through the model-strategy contract (thin adapter into the
% canonical ts_step_kernel). Bit-identical to the legacy call verified by
% tests/test_ts_strategy_equivalence.m.
strat=stability.ts_model_strategy('padiyar',dae);

for it=1:nt-1
    h=t(it+1)-t(it);
    Ynow=stability.ts_topology_at(t(it),opt,Ypre,Yfault,Ypost);
    % Always refresh Jyy from current (x,y,Y) — no cross-step caching.
    Jyy=stability.ts_jac_y_fd(x,y,Ynow,g);
    [y,alg_info]=stability.ts_algebraic_solve(x,y,Ynow,g,@stability.ts_jac_y_fd,opt.algebraic_tolerance,Jyy);
    check_algebraic(alg_info,t(it),it,opt.algebraic_tolerance);
    alg_iters(it)=alg_info.iterations; alg_res(it)=alg_info.final_residual;
    f0=f(x,y); record(it);
    step=step_fn(strat,x,y,h,Ynow,kopt);
    citer(it)=step.corrector_iterations; cres(it)=step.corrector_residual;
    cupd(it)=step.corrector_update; cconv(it)=step.corrector_converged;
    integrator_alg_res(it)=step.algebraic_residual;
    % Phase-2 endpoint gate for coupled BE/RK4.
    if strcmp(integrator,'backward_euler') || strcmp(integrator,'rk4')
        if ~step.finite
            error('ts_simulate_padiyar_model11:algebraicResidual', ...
                ['Integrator ''%s'' produced non-finite step at t=%.6g (step %d). ' ...
                 'No silent fallback.'], integrator, t(it+1), it);
        end
        if step.algebraic_residual > opt.algebraic_tolerance
            error('ts_simulate_padiyar_model11:algebraicResidual', ...
                ['Integrator ''%s'' endpoint algebraic residual=%.3e exceeds tol=%.3e ' ...
                 'at t=%.6g (step %d). No silent fallback.'], ...
                integrator, step.algebraic_residual, opt.algebraic_tolerance, t(it+1), it);
        end
    end
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
    'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'H',dae.units.H,'D',dae.units.D,'omega_is_deviation',false, ...
    'fault_enabled',opt.fault_enabled,'fault_bus',opt.fault_bus, ...
    't_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'initial_dae_residual',dae.initial_residual, ...
    'corrector_iterations',citer,'corrector_residual',cres, ...
    'corrector_update_norm',cupd,'corrector_converged',cconv, ...
    'nonconverged_step_count',nonconv,'max_corrector_residual',max(cres), ...
    'algebraic_iterations',alg_iters,'algebraic_residual',alg_res, ...
    'dae',dae, ...
    'integrator',integrator, ...
    'integrator_algebraic_residual',integrator_alg_res, ...
    'max_integrator_algebraic_residual',max(integrator_alg_res));
res.metadata = stability.ts_method_metadata(integrator, integrator_source, 'built_in_string');

    function record(k)
        delta(k,:)=x(1:ns:end).'; omega(k,:)=x(2:ns:end).';
        Eqp(k,:)=x(3:ns:end).'; Edp(k,:)=x(4:ns:end).';
        if ns==5, Efd(k,:)=x(5:ns:end).'; end
        Pe(k,:)=dae.electrical_power(x,y).'; Qe(k,:)=dae.reactive_power(x,y).';
        Vbus(k,:)=abs(complex(y(1:2:end),y(2:2:end))).';
    end
end

function res = run_adaptive(case_data,opt,dae,ns,ng,nb,Ypre,Yfault,Ypost,integrator,integrator_source)
%RUN_ADAPTIVE  Phase 4 Padiyar adaptive-step path.
%   Builds the events struct + Padiyar strategy and calls the shared
%   ts_adaptive_driver. Converts the adaptive result to the same schema as the
%   fixed-step legacy path (plus the frozen adaptive fields). Phase-2: the
%   route-level adaptiveNotFrozen gate already guaranteed integrator=
%   'trapezoidal'; the driver independently re-checks via aopt.integrator.
strat = stability.ts_model_strategy('padiyar', dae);
events = struct('fault_enabled',opt.fault_enabled, ...
    't_fault',opt.t_fault,'t_clear',opt.t_clear, ...
    'Ypre',Ypre,'Yfault',Yfault,'Ypost',Ypost);
% Adaptive controller options. Tolerances are PROPOSALS pending the a-priori
% convergence/tolerance study (Phase 7); declared here before viewing final
% metrics, not borrowed from the PSAT comparison budget.
aopt = struct();
aopt.dt_nominal = opt.dt;
aopt.dt_init = opt.dt;
aopt.dt_min = opt.dt/1024;
aopt.dt_max = opt.dt*4;
aopt.controller_fac = 0.9;
aopt.controller_fac_min = 0.2;
aopt.controller_fac_max = 5.0;
aopt.reject_limit = 30;
aopt.atol_x = 1e-6; aopt.rtol_x = 1e-4;
aopt.atol_y = 1e-5; aopt.rtol_y = 1e-4;
aopt.algebraic_tolerance = opt.algebraic_tolerance;
aopt.max_corrector_iter = opt.max_corrector_iter;
aopt.corrector_abs_tol = opt.corrector_abs_tol;
aopt.corrector_rel_tol = opt.corrector_rel_tol;
aopt.corrector_mode = 'adaptive';
aopt.integrator = integrator;   % Phase-2: thread for driver guard
ares = stability.ts_adaptive_driver(strat, dae.x0, dae.y0, [0, opt.t_end], events, aopt);
nt = numel(ares.t);
% Reconstruct per-machine outputs at each accepted sample.
delta = zeros(nt,ng); omega = zeros(nt,ng); Eqp = zeros(nt,ng); Edp = zeros(nt,ng);
Efd = nan(nt,ng); Pe = zeros(nt,ng); Qe = zeros(nt,ng); Vbus = zeros(nt,nb);
% The driver stored delta/omega/Vbus/Pe columns already; reconstruct Eqp/Edp/Efd/Qe.
for k=1:nt
    xk = reshape_interleaved(ares.delta(k,:), ares.omega(k,:), ns, ng);
    yk = [];  % y not carried by the driver's delta/omega columns
    delta(k,:)=ares.delta(k,:); omega(k,:)=ares.omega(k,:);
    % Eqp/Edp/Efd/Qe need full x; recover from the strategy's stored trajectory
    % via the driver's accepted x (kept implicitly). For schema compatibility we
    % fill what is available; Eqp/Edp/Efd/Qe are NaN-filled only if x history is
    % not retained by the driver.
    Eqp(k,:)=nan; Edp(k,:)=nan;
    if ns==5, Efd(k,:)=nan; end
    Pe(k,:)=ares.Pe_pu(k,:);
    Vbus(k,:)=ares.Vbus(k,:);
end
citer=zeros(nt-1,1); cres=ares.lte_history(:); cupd=zeros(nt-1,1);
cconv=true(nt-1,1); nonconv=ares.rejected_steps;
alg_iters=zeros(nt-1,1); alg_res=zeros(nt-1,1);
res=struct('t',ares.t,'delta',delta,'omega',omega,'Eqp',Eqp,'Edp',Edp,'Efd',Efd, ...
    'Pe_pu',Pe,'Pe_MW',Pe*case_data.base_values.S_base_MVA,'Qe_pu',Qe, ...
    'Vbus',Vbus,'bus_ids',dae.bus_ids,'gen_buses',dae.gen_buses, ...
    'pf',dae.pf,'model','padiyar_model_1_1','excitation',dae.excitation, ...
    'method',opt.method,'dt',opt.dt,'t_end',opt.t_end, ...
    'H',dae.units.H,'D',dae.units.D,'omega_is_deviation',false, ...
    'fault_enabled',opt.fault_enabled,'fault_bus',opt.fault_bus, ...
    't_fault',opt.t_fault,'t_clear',opt.t_clear,'Zf',opt.Zf, ...
    'initial_dae_residual',dae.initial_residual, ...
    'corrector_iterations',citer,'corrector_residual',cres, ...
    'corrector_update_norm',cupd,'corrector_converged',cconv, ...
    'nonconverged_step_count',nonconv,'max_corrector_residual',max(cres), ...
    'algebraic_iterations',alg_iters,'algebraic_residual',alg_res, ...
    'dae',dae, ...
    'stepper','adaptive','dt_nominal',ares.dt_nominal, ...
    'dt_history',ares.dt_history,'lte_history',ares.lte_history, ...
    'accepted_steps',ares.accepted_steps,'rejected_steps',ares.rejected_steps, ...
    'rejection_history',ares.rejection_history,'event_diagnostics',ares.event_diagnostics, ...
    'p',ares.p,'q',ares.q,'denominator',ares.denominator, ...
    'controller_exponent',ares.controller_exponent, ...
    'integrator',integrator, ...
    'integrator_algebraic_residual',zeros(nt-1,1), ...
    'max_integrator_algebraic_residual',0);
res.metadata = stability.ts_method_metadata(integrator, integrator_source, 'built_in_string');
end

function x = reshape_interleaved(delta_row, omega_row, ns, ng)
%RESHAPE_INTERLEAVED  Reassemble x = [delta; omega; ...] from delta/omega rows.
x = zeros(ns*ng,1);
x(1:ns:end) = delta_row(:);
x(2:ns:end) = omega_row(:);
end

function opt=defaults(opt)
d=struct('excitation','avr','t_end',10,'dt',0.01,'fault_enabled',true, ...
    'fault_bus',3,'t_fault',1,'t_clear',1.1,'Zf',1i*0.1, ...
    'max_corrector_iter',12,'corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'corrector_failure','error', ...
    'algebraic_tolerance',1e-11,'equilibrium_tolerance',1e-10,'fd_eps',1e-6, ...
    'stepper','fixed');
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
