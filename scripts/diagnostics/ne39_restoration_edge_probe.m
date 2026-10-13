function report=ne39_restoration_edge_probe(preflight_file)
%NE39_RESTORATION_EDGE_PROBE Actual device-owned 9->8 transfer, private trial.
% Starts at the certified SG_ON incumbent equilibrium, not an old raw replay.
S=load(preflight_file,'report'); table=S.report.selector_table;
cfg=table.sg_on.configurations;
[design,analysis]=ne39_endpoint_design_options();
c=cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(),design);
s=cases.scenario_ne39_tamu_mixed(c,struct('sg_reclose_plant',true, ...
    'initial_modes',analysis.initial_modes));
[devices,~]=stability.build_mixed_resource_devices(c,s.resources,s.scenario_opt);
ready=arrayfun(@(a)isequal(a.ready_to_commit,true),cfg);
counts=arrayfun(@(a)numel(a.selected_gfm_indices),cfg);
inc=cfg(find(ready & counts==9,1));
rows=find(ready & counts==8);
[~,order]=sort([cfg(rows).margin],'descend'); rows=rows(order);
eq=stability.mixed_equilibrium_solve(c,struct('devices',devices), ...
    struct('verbose',false,'tolerance',1e-8));
assert(eq.converged,'Incumbent equilibrium failed.');
dae=stability.composite_dae(c,devices,struct());
left=eq.equilibrium_context; x=eq.x0; y=eq.y0; u=eq.u_eq;
report=struct('status','EDGE_NOT_VERIFIED','selected',[], ...
    'trial',struct(),'right_kcl',Inf,'production_certified',false);
for j=reshape(rows(1:min(2,numel(rows))),1,[])
    candidate=cfg(j);
    removed=setdiff(inc.selected_gfm_indices,candidate.selected_gfm_indices);
    assert(numel(removed)==1);
    right=left; right.hybrid_state=stability.ts_hybrid_state_snapshot(left.hybrid_state);
    k=removed(1); dev=devices(k);
    key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    right.hybrid_state.device_modes.(key)='gfl';
    right.hybrid_state.selected_gfm_indices=candidate.selected_gfm_indices;
    right.hybrid_state.n_gfm_required=numel(candidate.selected_gfm_indices);
    ur=u;
    for q=1:numel(devices)
        if ~isfield(devices(q),'device_type') || ~strcmpi(devices(q).device_type,'ibr_eecon49_dual'), continue; end
        for name=["P_ref","Q_ref"]
            slot=find(strcmpi(string(devices(q).input_names),name));
            gi=dae.u_offsets(q)+slot; ur(gi)=candidate.eq_u_eq(gi);
        end
    end
    xr=x; ix=dae.device_offsets(k)+(1:dev.nx); ui=dae.u_offsets(k)+(1:dev.nu);
    [xr(ix),~]=dev.mode_transfer_state(x(ix),y,ur(ui),left,'gfl',right,struct('AbsTol',1e-10));
    g=@(xx,yy,YY)dae.dae_g(0,xx,yy,YY,ur,right);
    [yr,info]=stability.ts_algebraic_solve(xr,y,dae.Ynet,g,@stability.ts_jac_y_fd,1e-8);
    report.right_kcl=norm(g(xr,yr,dae.Ynet),inf);
    assert(info.converged && report.right_kcl<=1e-8);
    T=max(log(1/c.delays.rho)/(-candidate.omega),c.synchronism.dwell_s);
    bounds=struct('v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5);
    opt=struct('dt',.01,'max_steps',32000,'rho',c.delays.rho, ...
        'sync_dwell',c.synchronism.dwell_s,'newton_tol',1e-8,'max_iter',50, ...
        'fd_eps',3e-6,'kcl_tol',1e-8,'energy_tol_pu_s',1e-6, ...
        'refinement_tol',1e-5,'slip_limit_deg',180,'timestep_strategy','adaptive', ...
        'assessment_policy','strict','progress_interval_s',30);
    fprintf('EDGE selected=%s removed=%d nominal_horizon=%g\n',mat2str(candidate.selected_gfm_indices),k,T);
    [ok,audit]=stability.certify_ne39_transition(0,xr,yr,ur,right,dae.Ynet, ...
        dae,s.resources,c,bounds,candidate,opt);
    report.selected=candidate.selected_gfm_indices; report.trial=audit;
    if ok, report.status='PRIVATE_EDGE_TRIAL_PASS'; break; end
    fprintf('EDGE refused=%s\n',audit.reason);
end
folder=fileparts(preflight_file);
save(fullfile(folder,'edge_probe.mat'),'report','-v7.3');
fprintf('EDGE status=%s right_kcl=%g\n',report.status,report.right_kcl);
end
