function folder=probe_ne39_adaptive_private_trial(raw_file,extra)
%PROBE_NE39_ADAPTIVE_PRIVATE_TRIAL ตรวจ private trajectory เดิมบน adaptive mesh.
% ไม่มี commit authority; candidate ใช้ SG_OFF row ที่ raw run บันทึกไว้จริง.
arguments
    raw_file (1,1) string
    extra (1,1) struct = struct()
end
root=pf_init_paths(); data=load(raw_file,'request','result'); s=data.request.scenario;
a=data.result.controller_audit.ne39_transition.trial_initial_conditions;
candidate=data.result.selector_table.sg_off.selected_config;
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
d=stability.composite_dae(s.case_data,dev,struct('load_model','cz_p_cz_q'));
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_adaptive_trial_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
opt=a.options; opt.timestep_strategy='adaptive'; opt.max_steps=32000;
opt.progress_interval_s=15;
for name=fieldnames(extra)'
    opt.(name{1})=extra.(name{1});
end
request=struct('raw_file',raw_file,'options',opt,'candidate',candidate, ...
    'classification','DIAGNOSTIC_PRIVATE_TRIAL_NO_COMMIT_AUTHORITY');
save(fullfile(folder,'request.mat'),'request','-v7.3');
fprintf('[NE39-adaptive-trial] start artifact=%s dt=%g max_steps=%d\n', ...
    folder,opt.dt,opt.max_steps);
timer=tic;
[ok,audit]=stability.certify_ne39_transition(a.t,a.x,a.y,a.u,a.event_context, ...
    a.Y,d,s.resources,s.case_data,a.bounds,candidate,opt);
elapsed=toc(timer);
classification='DIAGNOSTIC_PRIVATE_TRIAL_NO_COMMIT_AUTHORITY';
save(fullfile(folder,'trial.mat'),'raw_file','opt','candidate','ok','audit', ...
    'elapsed','classification','-v7.3');
fprintf('[NE39-adaptive-trial] ok=%d status=%s reason=%s elapsed=%g\n', ...
    ok,audit.status,audit.reason,elapsed);
for k=1:numel(audit.passes)
    p=audit.passes{k};
    fprintf(['pass=%d reached=%g steps=%d attempts=%d rejected=%d ' ...
        'min_dt=%g max_dt=%g energy_error=%g reason=%s\n'], ...
        k,p.t_reached,p.steps,p.step_attempts,p.rejected_steps, ...
        p.min_dt,p.max_dt,p.energy_error_pu_s,p.reason);
end
if isfield(audit,'refinement_error')
    fprintf('refinement_error=%g samples=%d\n',audit.refinement_error,audit.refinement_samples);
end
fprintf('artifact=%s\n',folder);
end
