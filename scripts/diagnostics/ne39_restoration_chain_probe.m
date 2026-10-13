function report=ne39_restoration_chain_probe(preflight_file)
%NE39_RESTORATION_CHAIN_PROBE Private sequential transfers, no state reseeding.
% This is an SG_ON diagnostic, not the trip/fault/reclose chronology.
S=load(preflight_file,'report'); cfg=S.report.selector_table.sg_on.configurations;
[design,analysis]=ne39_endpoint_design_options();
c=cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(),design);
s=cases.scenario_ne39_tamu_mixed(c,struct('sg_reclose_plant',true, ...
    'initial_modes',analysis.initial_modes));
[devices,~]=stability.build_mixed_resource_devices(c,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(c,struct('devices',devices), ...
    struct('verbose',false,'tolerance',1e-8));
assert(eq.converged,'Incumbent equilibrium failed.');
dae=stability.composite_dae(c,devices,struct());
x=eq.x0; y=eq.y0; u=eq.u_eq; ec=eq.equilibrium_context; t=0;
selected=find(strcmpi({s.resources.initial_mode},'gfm'));
assert(numel(selected)==9);
% Follow the evaluated prefix path; do not let a greedy first edge leave it.
path=cell(1,9);
for n=8:-1:0
    target=selected(1:n);
    hit=find(arrayfun(@(a)isequal(a.ready_to_commit,true) && ...
        isequal(sort(a.selected_gfm_indices(:).'),sort(target)),cfg));
    assert(numel(hit)==1,'Required unique certified path row missing.');
    path{9-n}=cfg(hit);
end
folder=fullfile(fileparts(preflight_file), ...
    ['chain_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
report=struct('status','CHAIN_IN_PROGRESS','completed_edges',0,'initial_gfm_count',9, ...
    'final_gfm_count',9,'final_time',0,'edges',{{}},'production_certified',false, ...
    'scope','PRIVATE_SG_ON_CONTINUATION_NOT_FULL_CHRONOLOGY', ...
    'damping_floor',c.selector.zeta_min_damping,'artifact_folder',folder);
for j=1:numel(path)
    candidate=path{j}; target=candidate.selected_gfm_indices(:).';
    removed=setdiff(selected,target); assert(numel(removed)==1);
    right=ec; right.hybrid_state=stability.ts_hybrid_state_snapshot(ec.hybrid_state);
    k=removed(1); dev=devices(k);
    key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    right.hybrid_state.device_modes.(key)='gfl';
    right.hybrid_state.selected_gfm_indices=target;
    right.hybrid_state.n_gfm_required=numel(target);
    ur=u;
    for q=1:numel(devices)
        if ~isfield(devices(q),'device_type') || ~strcmpi(devices(q).device_type,'ibr_eecon49_dual'), continue; end
        for name=["P_ref","Q_ref"]
            slot=find(strcmpi(string(devices(q).input_names),name));
            assert(numel(slot)==1,'Certified input slot missing.');
            gi=dae.u_offsets(q)+slot; ur(gi)=candidate.eq_u_eq(gi);
        end
    end
    xr=x; ix=dae.device_offsets(k)+(1:dev.nx); ui=dae.u_offsets(k)+(1:dev.nu);
    [xr(ix),~]=dev.mode_transfer_state(x(ix),y,ur(ui),ec,'gfl',right,struct('AbsTol',1e-10));
    g=@(xx,yy,YY)dae.dae_g(t,xx,yy,YY,ur,right);
    [yr,info]=stability.ts_algebraic_solve(xr,y,dae.Ynet,g,@stability.ts_jac_y_fd,1e-8);
    right_kcl=norm(g(xr,yr,dae.Ynet),inf);
    assert(info.converged && right_kcl<=1e-8,'Right-limit KCL failed.');
    T=max(log(1/c.delays.rho)/(-candidate.omega),c.synchronism.dwell_s);
    osc=candidate.physical_eigenvalues(imag(candidate.physical_eigenvalues)~=0);
    if ~isempty(osc)
        [~,z]=max(real(osc)); period=2*pi/abs(imag(osc(z))); T=ceil(T/period)*period;
    end
    bounds=struct('v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5);
    opt=struct('dt',.01,'max_steps',ceil(2*T/.01)+16,'rho',c.delays.rho, ...
        'sync_dwell',c.synchronism.dwell_s,'newton_tol',1e-8,'max_iter',50, ...
        'fd_eps',3e-6,'kcl_tol',1e-8,'energy_tol_pu_s',1e-6, ...
        'refinement_tol',1e-5,'slip_limit_deg',180,'timestep_strategy','adaptive', ...
        'assessment_policy','strict','progress_interval_s',60);
    fprintf('CHAIN edge=%d %d->%d removed=%s t=%g trial_horizon=%g\n', ...
        j,numel(selected),numel(target),dev.device_id,t,T);
    [ok,audit,final]=stability.certify_ne39_transition(t,xr,yr,ur,right,dae.Ynet, ...
        dae,s.resources,c,bounds,candidate,opt);
    report.edges{end+1}=struct('from',selected,'to',target,'right_kcl',right_kcl, ...
        'passed',ok,'audit',audit);
    if ~ok
        report.status='CHAIN_REFUSED';
        save(fullfile(folder,'chain.mat'),'report','-v7.3');
        fprintf('CHAIN refused edge=%d reason=%s\n',j,audit.reason); return;
    end
    % Refined terminal state of the preceding trial is the next left state.
    x=final.x; y=final.y; u=final.u; ec=final.event_context; t=final.t;
    selected=target;
    report.completed_edges=j; report.final_gfm_count=numel(selected); report.final_time=t;
    save(fullfile(folder,'chain.mat'),'report','x','y','u','ec','-v7.3');
    fprintf('CHAIN completed=%d remaining_gfm=%d t=%g\n',j,numel(selected),t);
end
report.status='PRIVATE_CHAIN_ALL_GFL_PASS';
report.final_kcl=norm(dae.dae_g(t,x,y,dae.Ynet,u,ec),inf);
report.final_snapshot=stability.ne39_transition_snapshot(t,x,y,u,ec,dae,s.resources,c,bounds);
report.final_physical_rhs=dae.dae_f(t,x,y,dae.Ynet,u,ec);
% Derivatives are evidence only; no unapproved recovery tolerance grants PASS.
save(fullfile(folder,'chain.mat'),'report','x','y','u','ec','-v7.3');
fprintf('CHAIN status=%s gfm=%d kcl=%g artifact=%s\n', ...
    report.status,report.final_gfm_count,report.final_kcl,folder);
end
