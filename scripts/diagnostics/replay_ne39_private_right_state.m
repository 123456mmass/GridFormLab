function folder = replay_ne39_private_right_state(raw_file,horizon,dt)
%REPLAY_NE39_PRIVATE_RIGHT_STATE diagnostic trajectory; ไม่ให้ commit authority.
% เดินสมการเดิมเพื่อวัด recovery ก่อนออกแบบ transient contract.
arguments
    raw_file (1,1) string
    horizon (1,1) double {mustBePositive} = 1
    dt (1,1) double {mustBePositive} = .0025
end
root=pf_init_paths(); data=load(raw_file,'request','result');
s=data.request.scenario;
a=data.result.controller_audit.ne39_transition.trial_initial_conditions;
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
d=stability.composite_dae(s.case_data,dev,struct('load_model','cz_p_cz_q'));
active=stability.ts_dynamic_state_indices(d,a.event_context);
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_right_replay_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
x=a.x; y=a.y; t=0; X=x; V=y; times=0; snapshots={};
reason=''; converged=true;
while true
    ev=stability.ne39_transition_snapshot(a.t+t,x,y,a.u,a.event_context, ...
        d,s.resources,s.case_data,a.bounds);
    snapshots{end+1}=ev; %#ok<AGROW>
    vm=abs(complex(y(1:2:end),y(2:2:end)));
    rows=ev.records;
    fprintf('t=%g Vmin=%g Vmax=%g fmin=%g fmax=%g Imax=%g status=%s\n', ...
        t,min(vm),max(vm),min([rows.f_Hz]),max([rows.f_Hz]), ...
        max([rows.I_converter_pu],[],'omitnan'),ev.status);
    if t>=horizon-1e-12, break; end
    op=struct('t_now',a.t+t,'newton_tol',a.options.newton_tol, ...
        'max_iter',a.options.max_iter,'fd_eps',a.options.fd_eps,'verbose',false, ...
        'full_kcl',true,'domain_preserving_trials',true);
    h=min(dt,horizon-t);
    step=stability.ts_step_composite(x,y,h,d,a.Y,a.u,a.event_context,active,op);
    if ~step.converged || ~step.finite
        converged=false; reason='NEWTON_NOT_CONVERGED'; break;
    end
    x=step.x_full; y=step.y_full; t=t+h;
    X(:,end+1)=x; V(:,end+1)=y; times(end+1)=t; %#ok<AGROW>
end
classification='DIAGNOSTIC_ONLY_NO_TRANSITION_OR_COMMIT_AUTHORITY';
save(fullfile(folder,'replay.mat'),'raw_file','horizon','dt','times','X','V', ...
    'snapshots','converged','reason','classification','-v7.3');
fprintf('reached=%g requested=%g converged=%d artifact=%s\n', ...
    t,horizon,converged,folder);
end
