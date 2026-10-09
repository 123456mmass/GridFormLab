function folder=probe_ne39_right_step_refinement(raw_file)
%PROBE_NE39_RIGHT_STEP_REFINEMENT stencil diagnostic จาก private right state จริง.
arguments
    raw_file (1,1) string
end
root=pf_init_paths(); data=load(raw_file,'request','result'); s=data.request.scenario;
a=data.result.controller_audit.ne39_transition.trial_initial_conditions;
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
d=stability.composite_dae(s.case_data,dev,struct('load_model','cz_p_cz_q'));
active=stability.ts_dynamic_state_indices(d,a.event_context);
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_right_stencil_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder); rows=struct('dt',{},'error',{},'argmax',{},'converged',{});
for factor=2.^(0:9)
    h=a.options.dt/factor;
    op=struct('t_now',a.t,'newton_tol',a.options.newton_tol, ...
        'max_iter',a.options.max_iter,'fd_eps',a.options.fd_eps,'verbose',false, ...
        'full_kcl',true,'domain_preserving_trials',true);
    coarse=stability.ts_step_composite(a.x,a.y,h,d,a.Y,a.u,a.event_context,active,op);
    first=stability.ts_step_composite(a.x,a.y,h/2,d,a.Y,a.u,a.event_context,active,op);
    op.t_now=a.t+h/2;
    fine=stability.ts_step_composite(first.x_full,first.y_full,h/2,d,a.Y,a.u,a.event_context,active,op);
    err=abs([fine.x_full(active)-coarse.x_full(active);fine.y_full-coarse.y_full]);
    [worst,j]=max(err);
    rows(end+1)=struct('dt',h,'error',worst,'argmax',j, ...
        'converged',coarse.converged && first.converged && fine.converged); %#ok<AGROW>
    fprintf('[NE39-stencil] h=%.9g error=%.9g argmax=%d converged=%d\n', ...
        h,worst,j,rows(end).converged);
end
classification='DIAGNOSTIC_ONLY_NO_TRANSITION_OR_COMMIT_AUTHORITY';
save(fullfile(folder,'stencil.mat'),'raw_file','rows','classification');
fprintf('artifact=%s\n',folder);
end
