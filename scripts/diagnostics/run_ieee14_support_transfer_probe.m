function run_ieee14_support_transfer_probe
%RUN_IEEE14_SUPPORT_TRANSFER_PROBE  Stop at the SG-off AGSI right limit.
% Diagnostic only: no result feeds production.  It isolates the accepted
% n=1 -> n=4 transfer and reports the immediate differential residual by
% device/state before attempting any following time step.

pf_init_paths();
pfile='output/diagnostics/support_transfer_probe_progress.log';
mfile='output/diagnostics/support_transfer_probe_result.mat';
if exist(pfile,'file'), delete(pfile); end
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
ev=struct('enabled',true,'event_profile','sg_cycle', ...
    'sg_trip',20,'sg_on',22.2,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',5,'dwell_s',0.5));
sys=ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4",sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);
opt=struct('t_end',22.2,'dt',0.1,'verbose',false,'ibr_events',ev, ...
    'plot_results',false,'max_step_subdivisions',8, ...
    'progress_every',1.0,'progress_file',pfile, ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
r=stability.run_hybrid_case(s,opt);
probe=struct('available',false);
if ~isempty(r.t) && isfield(r,'event_context_history') && ...
        ~isempty(r.event_context_history)
    devices=r.equilibrium.devices;
    dae=stability.composite_dae(s.case_data,devices,struct('load_model','cz_p_cz_q'));
    x=r.x_traj(:,end); y=r.y_traj(:,end); u=r.u_history(:,end);
    ec=r.event_context_history{end}; t=r.t(end);
    dx=dae.dae_f(t,x,y,u,ec);
    active=stability.ts_dynamic_state_indices(dae,ec);
    rows=repmat(struct('device_id','','mode','','max_abs_dx',NaN, ...
        'state_name','','state_index',NaN,'state_dx',NaN),numel(devices),1);
    for k=1:numel(devices)
        dev=devices(k); xi=dae.device_offsets(k)+(1:dev.nx);
        [v,j]=max(abs(dx(xi)));
        key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
        rows(k).device_id=char(dev.device_id);
        rows(k).mode=char(ec.hybrid_state.device_modes.(key));
        rows(k).max_abs_dx=v; rows(k).state_name=dev.state_names{j};
        rows(k).state_index=j; rows(k).state_dx=dx(xi(j));
    end
    probe=struct('available',true,'t',t,'dx',dx,'active',active,'rows',rows);
end
save(mfile,'r','opt','probe','-v7.3');
fprintf('SUPPORT_TRANSFER_PROBE converged=%d t_end=%.6f available=%d\n', ...
    r.converged,last_time(r),probe.available);
if probe.available
    for k=1:numel(probe.rows)
        q=probe.rows(k);
        fprintf('  %s mode=%s max_abs_dx=%.12g state=%s local_index=%d dx=%.12g\n', ...
            q.device_id,q.mode,q.max_abs_dx,q.state_name,q.state_index,q.state_dx);
    end
end
end

function t=last_time(r)
t=NaN;
if isfield(r,'t') && ~isempty(r.t), t=r.t(end); end
end
