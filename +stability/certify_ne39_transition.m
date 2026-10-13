function [ok,audit,private_final] = certify_ne39_transition(t,x,y,u,ec,Y,dae,resources,c,bounds,candidate,opt)
% Retry unresolved global refinement on finer meshes, never physical failures.
arguments
    t (1,1) double {mustBeFinite}
    x (:,1) double
    y (:,1) double
    u (:,1) double
    ec (1,1) struct
    Y double
    dae (1,1) struct
    resources struct
    c (1,1) struct
    bounds (1,1) struct
    candidate (1,1) struct
    opt (1,1) struct
end
adaptive=isfield(opt,'timestep_strategy') && strcmp(opt.timestep_strategy,'adaptive');
max_retries=0;
if adaptive, max_retries=6; end
if isfield(opt,'global_refinement_max_retries')
    validateattributes(opt.global_refinement_max_retries,{'numeric'}, ...
        {'scalar','real','finite','integer','nonnegative','<=',8});
    max_retries=opt.global_refinement_max_retries;
end
if ~adaptive, max_retries=0; end
attempt_opt=opt; history={}; used_steps=0; abs_end=NaN;
resume=struct('elapsed_s',NaN);
for attempt=0:max_retries
    if attempt>0
        attempt_opt.dt=attempt_opt.dt/2;
        if isfield(attempt_opt,'adaptive_dt_max')
            attempt_opt.adaptive_dt_max=attempt_opt.adaptive_dt_max/2;
        end
        % One shared accepted-step budget bounds all retries, not just each pass.
        attempt_opt.max_steps=max(1,opt.max_steps-used_steps);
        call_t=t; call_x=x; call_y=y;
        resumed_from=NaN;
        % Windowed refinement resume (2026-10-13): when the previous attempt
        % failed DT_REFINEMENT at ONE coarse time, its pass-2 walk had already
        % VERIFIED every coarse time before that point on the same mesh
        % (refinement, KCL, snapshot, energy, synchronism all green up to the
        % resume point). Re-walking that verified prefix on a finer mesh
        % re-pays work the finer mesh cannot change. Resume from the last
        % VERIFIED coarse state instead and walk ONLY the tail: the prefix
        % evidence stays the previous attempt's, the suffix is this attempt's
        % finer mesh, and the shared step budget is spent forward, not thrown
        % away. Slip/energy peaks are reported per window (prefix + suffix)
        % via the history entry, so no total is overstated OR hidden.
        if numel(audit.passes)>=2 && isstruct(audit.passes{2}) && ...
                isfield(audit.passes{2},'refinement_resume')
            resume=audit.passes{2}.refinement_resume;
        end
        if isfinite(abs_end) && isfinite(resume.elapsed_s)
            res_t=t+resume.elapsed_s;
            remain=abs_end-res_t;
            if remain>2*attempt_opt.dt
                active_here=stability.ts_dynamic_state_indices(dae,ec);
                call_t=res_t;
                call_x=x; call_x(active_here)=resume.x_active;
                call_y=resume.y;
                attempt_opt.horizon_override_s=remain;
                resumed_from=resume.elapsed_s;
            end
        end
        fprintf('[NE39-global-refinement] retry=%d dt=%.9g remaining_step_budget=%d', ...
            attempt,attempt_opt.dt,attempt_opt.max_steps);
        if isfinite(resumed_from)
            fprintf(' resume_from_s=%.9g remaining_horizon_s=%.9g', ...
                resumed_from,abs_end-call_t);
        end
        fprintf('\n');
    else
        call_t=t; call_x=x; call_y=y; resumed_from=NaN;
    end
    [ok,audit,private_final]=certify_once(call_t,call_x,call_y,u,ec,Y,dae, ...
        resources,c,bounds,candidate,attempt_opt);
    if ~isfinite(abs_end) && isfield(audit,'horizon_s') && isfinite(audit.horizon_s)
        % Absolute end of the FULL derived horizon (audit.horizon_s stores the
        % full value even when a screen bounded the walk; a resumed attempt's
        % horizon_s is the remaining span ending at the same absolute point).
        abs_end=call_t+audit.horizon_s;
    end
    steps=0;
    for k=1:numel(audit.passes), steps=steps+audit.passes{k}.steps; end
    used_steps=used_steps+steps;
    cap=NaN;
    if isfield(attempt_opt,'dt'), cap=attempt_opt.dt; end
    if isfield(attempt_opt,'adaptive_dt_max'), cap=attempt_opt.adaptive_dt_max; end
            entry=struct('attempt',attempt+1,'dt',cap,'status',audit.status, ...
        'reason',audit.reason,'accepted_steps',steps,'refinement_error',NaN, ...
        'resumed_from_s',resumed_from);
    if isfinite(resumed_from)
        entry.prefix_refinement_error=resume.prefix_refinement_error;
        entry.prefix_peak_excursion_deg=resume.prefix_peak_excursion_deg;
        entry.prefix_energy_error_pu_s=resume.prefix_energy_error_pu_s;
    end
    if isfield(audit,'refinement_error'), entry.refinement_error=audit.refinement_error; end
    history{end+1}=entry; %#ok<AGROW>
    if ok || ~strcmp(audit.reason,'DT_REFINEMENT_NOT_RESOLVED') || ...
            attempt==max_retries || (isfield(opt,'max_steps') && used_steps>=opt.max_steps)
        break;
    end
end
audit.global_refinement_attempts=history;
audit.global_refinement_retries=numel(history)-1;
audit.global_refinement_total_steps=used_steps;
end

function [ok,audit,private_final] = certify_once(t,x,y,u,ec,Y,dae,resources,c,bounds,candidate,opt)
%CERTIFY_NE39_TRANSITION private forward trial; ไม่เปลี่ยน live state หรือ timer.
% ตรวจ snapshot ทุก accepted trial sample และรัน dt/2 ยืนยัน energy accounting.
% PASS เป็นหลักฐาน trajectory เท่านั้น; caller ต้อง authenticate context/transfer.
% observe_voltage คืน study status แยก โดยคง strict evidence และ gates อื่น.
arguments
    t (1,1) double {mustBeFinite}
    x (:,1) double
    y (:,1) double
    u (:,1) double
    ec (1,1) struct
    Y double
    dae (1,1) struct
    resources struct
    c (1,1) struct
    bounds (1,1) struct
    candidate (1,1) struct
    opt (1,1) struct
end
policy=string(get_policy(opt));
ok=false;
private_final=struct(); % Diagnostic continuation only; never commit authority.
audit=struct('status','UNKNOWN','reason','ขาด certified spectrum/trial contract', ...
    'horizon_s',NaN,'passes',{{}},'commit_authorized',false, ...
    'refinement_scope','ALL_COARSE_ACCEPTED_TIMES','refinement_samples',0, ...
    'assessment_policy',char(policy),'strict_snapshot_pass',false, ...
    'horizon_capped',false);
if ~ismatrix(Y) || size(Y,1)~=size(Y,2) || ...
        size(Y,1)*2~=numel(y) || any(~isfinite(Y(:))) || ...
        ~isfield(dae,'devices') || ~isfield(dae,'device_offsets') || ...
        ~isfield(dae,'u_offsets') || ...
        numel(x)~=sum([dae.devices.nx]) || numel(u)~=sum([dae.devices.nu])
    audit.reason='INVALID_TRIAL_DIMENSIONS_OR_NETWORK'; return;
end
required={'dt','max_steps','rho','sync_dwell','newton_tol','max_iter', ...
    'fd_eps','kcl_tol','energy_tol_pu_s','refinement_tol','slip_limit_deg'};
if ~all(isfield(opt,required)) || ...
        ~all(isfield(candidate,{'ready_to_commit','feasible','omega'})) || ...
        ~isequal(candidate.ready_to_commit,true) || ~isequal(candidate.feasible,true) || ...
        ~isscalar(candidate.omega) || ~isfinite(candidate.omega) || candidate.omega>=0
    return;
end
for name=required
    validateattributes(opt.(name{1}),{'numeric'},{'scalar','real','finite','positive'});
end
if opt.rho>=1 || opt.max_steps~=fix(opt.max_steps)
    error('stability:certify_ne39_transition:options','rho/budget ไม่ถูกต้อง');
end
T=max(log(1/opt.rho)/(-candidate.omega),opt.sync_dwell);
if isfield(candidate,'physical_eigenvalues')
    lam=candidate.physical_eigenvalues;
    if ~isnumeric(lam) || isempty(lam) || ~isvector(lam) || ...
            any(~isfinite(lam(:))) || any(real(lam(:))>=0) || ...
            candidate.omega<max(real(lam(:)))
        audit.reason='INVALID_OR_INCONSISTENT_PHYSICAL_SPECTRUM'; return;
    end
    lam=lam(:);
    osc=lam(imag(lam)~=0);
    if ~isempty(osc)
        [~,j]=max(real(osc)); period=2*pi/abs(imag(osc(j)));
        T=ceil(T/period)*period;
    end
end
% Opt-in sub-call horizon override (windowed refinement resume): a retry that
% resumes from a stored mid-window state walks ONLY the remaining horizon, so
% the total window stays the horizon attempt 0 was built for. The derived
% horizon and its oscillator-period rounding already happened on attempt 0;
% sub-calls therefore skip the rounding. Present only on retry sub-calls.
used_override=false;
if isfield(opt,'horizon_override_s') && ~isempty(opt.horizon_override_s)
    validateattributes(opt.horizon_override_s,{'numeric'},{'scalar','real','finite','positive'});
    T=opt.horizon_override_s;
    audit.horizon_override_s=T;
    used_override=true;
end
audit.horizon_s=T;
% Opt-in SCREEN horizon (speed only, attempt 0 only): the full horizon stays in
% the audit and every gate still runs on the walked window. The screen only
% bounds the WALK, so a screen PASS is evidence on t in [t, t+T_screen], never
% a claim about [t+T_screen, t+T]. The audit reason names the screen; commit
% gates read commit_authorized=false either way. Absent = full walk.
if ~used_override && isfield(opt,'screen_horizon_s') && ~isempty(opt.screen_horizon_s)
    validateattributes(opt.screen_horizon_s,{'numeric'},{'scalar','real','finite','positive'});
    if opt.screen_horizon_s<T
        T=max(opt.screen_horizon_s,opt.dt);
        audit.horizon_screened_s=T;
        audit.horizon_capped=true;
    end
end
% เก็บ private right-state สำหรับ replay; ไม่ใช่ sample ที่อนุญาตให้ publish.
audit.trial_initial_conditions=struct('t',t,'x',x,'y',y,'u',u, ...
    'event_context',ec,'Y',Y,'bounds',bounds,'options',opt);
if ~isfinite(T) || ceil(T/(opt.dt/2))>opt.max_steps
    audit.reason='TRIAL_BUDGET_EXHAUSTED'; return;
end
active=stability.ts_dynamic_state_indices(dae,ec);
strategy='fixed';
if isfield(opt,'timestep_strategy'), strategy=char(opt.timestep_strategy); end
if ~any(strcmp(strategy,{'fixed','adaptive'}))
    error('stability:certify_ne39_transition:options','timestep_strategy ไม่ถูกต้อง');
end
% Adaptive mesh ใช้ step doubling เพื่อเลือก h เท่านั้น; global path refinement
% และ physical/energy gates เดิมยังตัดสินทั้งสอง passes ทุก coarse accepted time.
audit.timestep_strategy=strategy;
% Opt-in larger adaptive proposal cap for the pass-1 mesh. Omitted -> cap=opt.dt
% (legacy). Pass-2 refinement still halves every actual coarse interval, so a
% larger cap only changes the coarse mesh; tolerances and gates are unchanged.
adaptive_cap=opt.dt;
if isfield(opt,'adaptive_dt_max')
    validateattributes(opt.adaptive_dt_max,{'numeric'},{'scalar','real','finite','positive'});
    if opt.adaptive_dt_max<opt.dt
        error('stability:certify_ne39_transition:options','adaptive_dt_max must be at least dt.');
    end
    adaptive_cap=opt.adaptive_dt_max;
end
% Island labels depend only on Y, which is fixed for this trial: compute once.
adjacency=abs(Y)>0; adjacency(1:size(Y,1)+1:end)=false;
island_labels=conncomp(graph(adjacency | adjacency.'));
progress_interval=Inf;
if isfield(opt,'progress_interval_s')
    validateattributes(opt.progress_interval_s,{'numeric'},{'scalar','real','finite','positive'});
    progress_interval=opt.progress_interval_s;
end
progress_clock=tic; progress_last=-Inf;
coarse_t=[]; coarse_state=[]; path_refinement_error=0;
for pass=1:2
    try
        [a,xx,yy]=trial(opt.dt/2^(pass-1),pass);
    catch me
        audit.reason=['TRIAL_EVIDENCE_UNAVAILABLE: ' me.message]; return;
    end
    audit.passes{pass}=a;
    if pass==1
        % Keep the pass-1 audit struct for the windowed-resume evidence: when
        % pass 2 fails DT_REFINEMENT, the nested trial() no longer sees this
        % copy through audit.passes{1} after the reassignment below, and the
        % resume record must describe THIS pass-1 walk, not a later one.
        pass1_audit=a;
    end
    if ~any(strcmp(a.status,{'PASS','STUDY_TRIAL_COMPLETE'}))
        audit.status=a.status; audit.reason=a.reason;
        if strcmp(a.reason,'DT_REFINEMENT_NOT_RESOLVED')
            audit.refinement_error=path_refinement_error;
        end
        return;
    end
    if pass==1, xc=xx; yc=yy; else, xf=xx; yf=yy; end
end
if audit.refinement_samples~=audit.passes{1}.steps
    audit.reason='DT_REFINEMENT_COVERAGE_INCOMPLETE'; return;
end
audit.refinement_error=max(path_refinement_error,max(abs([xf(active)-xc(active);yf-yc])));
if audit.refinement_error>opt.refinement_tol
    audit.reason='DT_REFINEMENT_NOT_RESOLVED'; return;
end
private_final=struct('t',t+T,'x',xf,'y',yf,'u',u,'event_context',ec, ...
    'commit_authorized',false);
ok=true; audit.status='PASS'; audit.reason='PRIVATE_TRIAL_AND_REFINEMENT_PASS';
if audit.horizon_capped
    % The walk was bounded by the screen; never let a screen PASS read as a
    % full-horizon commitment. The status string names itself.
    audit.reason='PRIVATE_TRIAL_AND_REFINEMENT_PASS_SCREEN_HORIZON';
end
audit.strict_snapshot_pass=all(cellfun(@(a)a.strict_snapshot_pass,audit.passes));
if policy=="observe_voltage"
    audit.status='STUDY_TRIAL_COMPLETE'; audit.reason='STUDY_TRIAL_AND_REFINEMENT_COMPLETE';
end

    function [a,X,yy]=trial(dt,pass)
        X=x; yy=y; elapsed=0; next_coarse=2; proposed_h=dt;
        if pass==1
            % Preallocation is a hint sized from the largest proposal (adaptive cap or
            % fixed dt). A shrunk mesh can exceed it; MATLAB grows the array, and the
            % in-loop budget check bounds the total step count.
            if strcmp(strategy,'adaptive'), max_step=adaptive_cap; else, max_step=dt; end
            coarse_t=zeros(1,ceil(T/max_step)+1);
            coarse_state=zeros(numel(active)+numel(y),numel(coarse_t));
            coarse_state(:,1)=[X(active);yy];
        end
        a=struct('status','UNKNOWN','reason','','dt',dt,'steps',0, ...
            't_reached',0,'energy_error_pu_s',0,'peak_angle_excursion_deg',0, ...
            'step_attempts',0,'rejected_steps',0,'min_dt',Inf,'max_dt',0, ...
            'peak_local_refinement_error',0,'strict_snapshot_pass',true, ...
            'voltage_excursion_samples',0,'voltage_min_pu',Inf,'voltage_max_pu',0);
        e=stability.ne39_transition_snapshot(t,X,yy,u,ec,dae,resources,c,bounds);
        if ~observe_snapshot(e)
            a.status=e.status; a.reason=e.reason; a.failed_snapshot=e; return;
        end
        residual=dae.dae_g(t,X,yy,Y,u,ec);
        if any(~isfinite(residual)) || norm(residual,inf)>opt.kcl_tol
            a.reason='RIGHT_KCL_NOT_RESOLVED'; return;
        end
        % กำหนดคู่ synchronism เฉพาะ SG/GFM ที่อยู่ energized island เดียวกัน.
        [angle0,former,component]=angles(X,yy,t);
        if isempty(former) || ~all(ismember(unique(island_labels),component))
            a.reason='NO_VOLTAGE_FORMING_SOURCE'; return;
        end
        previous_angle=angle0; unwrapped=angle0; initial_angle=angle0;
        rows=e.records(startsWith({e.records.resource_id},'IBR'));
        E0=[rows.capacitor_energy_pu_s]+[rows.source_inductor_energy_pu_s];
        flow=[rows.source_minus_losses_pu]; integral=zeros(size(flow));
        active_idx=stability.ts_dynamic_state_indices(dae,ec);
        while elapsed<T-1e-12
            if a.steps>=opt.max_steps, a.reason='TRIAL_BUDGET_EXHAUSTED'; return; end
            progress();
            h=min(proposed_h,T-elapsed);
            if pass==2
                if strcmp(strategy,'adaptive')
                    interval=coarse_t(next_coarse)-coarse_t(next_coarse-1);
                    % Pass 2 halves the ACTUAL pass-1 interval I, not dt/2: the fine
                    % cap follows the coarse mesh, so a larger adaptive mesh keeps its
                    % benefit. Legacy adaptive meshes have I<=dt, so this equals
                    % min(dt/2,T-elapsed,I/2) exactly.
                    h=min(T-elapsed,interval/2);
                end
                h=min(h,coarse_t(next_coarse)-elapsed);
            end
            sopt=struct('t_now',t+elapsed,'newton_tol',opt.newton_tol, ...
                'max_iter',opt.max_iter,'fd_eps',opt.fd_eps,'verbose',false, ...
                'full_kcl',true,'domain_preserving_trials',true);
            % With-step Jacobian reuse (opt-in) ถูก forwarding มากับ trial opt;
            % ปกติ absent = false = legacy loop. ไปถึง ts_step_composite โดยตรง.
            if isfield(opt,'jacobian_reuse'), sopt.jacobian_reuse=opt.jacobian_reuse; end
            if isfield(opt,'jacobian_reuse_ratio'), sopt.jacobian_reuse_ratio=opt.jacobian_reuse_ratio; end
            try
                if pass==1 && strcmp(strategy,'adaptive')
                    % รับ full step บน mesh ที่ local step-doubling ผ่านเท่านั้น.
                    % pass2 เดินครึ่งทุก interval เดิมเพื่อทดสอบ global path จริง.
                    local_tol=opt.refinement_tol/20;
                    while true
                        progress();
                        step=stability.ts_step_composite(X,yy,h,dae,Y,u,ec,active_idx,sopt);
                        a.step_attempts=a.step_attempts+1;
                        local_error=Inf;
                        if step.converged && step.finite
                            half=stability.ts_step_composite(X,yy,h/2,dae,Y,u,ec,active_idx,sopt);
                            a.step_attempts=a.step_attempts+1;
                            if half.converged && half.finite
                                sop2=sopt; sop2.t_now=t+elapsed+h/2;
                                fine=stability.ts_step_composite(half.x_full,half.y_full,h/2, ...
                                    dae,Y,u,ec,active_idx,sop2);
                                a.step_attempts=a.step_attempts+1;
                                if fine.converged && fine.finite
                                    local_error=max(abs([fine.x_full(active)-step.x_full(active); ...
                                        fine.y_full-step.y_full]));
                                end
                            end
                        end
                        if local_error<=local_tol, break; end
                        a.rejected_steps=a.rejected_steps+1;
                        if h<=opt.dt/4096
                            a.reason='ADAPTIVE_TRIAL_STEP_NOT_RESOLVED'; return;
                        end
                        h=h/2;
                    end
                    factor=1.5;
                    if local_error>0
                        factor=min(1.5,max(.5,.8*(local_tol/local_error)^(1/3)));
                    end
                    proposed_h=min(adaptive_cap,h*factor);
                    a.peak_local_refinement_error=max(a.peak_local_refinement_error,local_error);
                else
                    step=stability.ts_step_composite(X,yy,h,dae,Y,u,ec,active_idx,sopt);
                    a.step_attempts=a.step_attempts+1;
                end
            catch me
                a.reason=me.message; return;
            end
            if ~step.converged || ~step.finite
                a.reason='TRIAL_NEWTON_NOT_CONVERGED'; return;
            end
            X=step.x_full; yy=step.y_full; elapsed=elapsed+h;
            a.steps=a.steps+1; a.t_reached=elapsed;
            a.min_dt=min(a.min_dt,h); a.max_dt=max(a.max_dt,h);
            if pass==1
                coarse_t(a.steps+1)=elapsed;
                coarse_state(:,a.steps+1)=[X(active);yy];
            elseif abs(elapsed-coarse_t(next_coarse))<=1e-12
                err_state=max(abs([X(active);yy]-coarse_state(:,next_coarse)));
                prefix_err=path_refinement_error;
                path_refinement_error=max(path_refinement_error,err_state);
                audit.refinement_samples=audit.refinement_samples+1;
                if err_state>opt.refinement_tol
                    % Windowed-resume evidence: the last VERIFIED coarse time
                    % and its full state. The prefix [0, this time] already
                    % matched within tol on this mesh (real measured
                    % evidence); only the tail needs the finer mesh. Frozen
                    % (non-active) states are exact holds of x0 (the
                    % frozenStateDrift guard), so the full state at the
                    % resume time is x0 with the active rows replaced.
                    a.refinement_resume=struct( ...
                        'elapsed_s',coarse_t(next_coarse-1), ...
                        'x_active',coarse_state(1:numel(active_idx),next_coarse-1), ...
                        'y',coarse_state(numel(active_idx)+1:end,next_coarse-1), ...
                        'prefix_refinement_error',prefix_err, ...
                        'prefix_pass1',pass1_audit, ...
                        'prefix_peak_excursion_deg',pass1_audit.peak_angle_excursion_deg, ...
                        'prefix_energy_error_pu_s',pass1_audit.energy_error_pu_s);
                    a.reason='DT_REFINEMENT_NOT_RESOLVED'; return;
                end
                next_coarse=next_coarse+1;
            end
            residual=dae.dae_g(t+elapsed,X,yy,Y,u,ec);
            if any(~isfinite(residual)) || norm(residual,inf)>opt.kcl_tol
                a.reason='TRIAL_KCL_NOT_RESOLVED'; return;
            end
            e=stability.ne39_transition_snapshot(t+elapsed,X,yy,u,ec,dae,resources,c,bounds);
            if ~observe_snapshot(e)
                a.status=e.status; a.reason=e.reason; a.failed_snapshot=e; return;
            end
            rows=e.records(startsWith({e.records.resource_id},'IBR'));
            nextflow=[rows.source_minus_losses_pu];
            integral=integral+.5*h*(flow+nextflow); flow=nextflow;
            E=[rows.capacitor_energy_pu_s]+[rows.source_inductor_energy_pu_s];
            err=max([0 abs(E-E0-integral)]);
            a.energy_error_pu_s=max(a.energy_error_pu_s,err);
            if err>opt.energy_tol_pu_s
                a.reason='DC_ENERGY_ACCOUNTING_NOT_RESOLVED'; return;
            end
            current_angle=angles(X,yy,t+elapsed);
            delta=current_angle-previous_angle;
            if any(abs(delta)>=pi)
                a.reason='ANGLE_STENCIL_NOT_RESOLVED'; return;
            end
            unwrapped=unwrapped+atan2(sin(delta),cos(delta));
            previous_angle=current_angle;
            for ii=1:numel(former)
                for jj=ii+1:numel(former)
                    if component(ii)~=component(jj), continue; end
                    excursion=abs((unwrapped(ii)-unwrapped(jj))- ...
                        (initial_angle(ii)-initial_angle(jj)))*180/pi;
                    a.peak_angle_excursion_deg=max(a.peak_angle_excursion_deg,excursion);
                end
            end
            if a.peak_angle_excursion_deg>=opt.slip_limit_deg
                a.status='FAIL'; a.reason='LOST_SYNCHRONISM'; return;
            end
        end
        if pass==1
            coarse_t=coarse_t(1:a.steps+1);
            coarse_state=coarse_state(:,1:a.steps+1);
        end
        a.status='PASS'; a.reason='TRIAL_COMPLETE';
        if policy=="observe_voltage", a.status='STUDY_TRIAL_COMPLETE'; end
        progress();

        function allowed=observe_snapshot(ev)
            allowed=stability.ne39_snapshot_policy(ev,policy);
            a.strict_snapshot_pass=a.strict_snapshot_pass && strcmp(ev.status,'PASS');
            if ev.complete
                vr=ev.voltage_reference;
                a.voltage_excursion_samples=a.voltage_excursion_samples+~vr.pass;
                a.voltage_min_pu=min(a.voltage_min_pu,min(vr.magnitude_pu));
                a.voltage_max_pu=max(a.voltage_max_pu,max(vr.magnitude_pu));
            end
        end

        function progress()
            if isinf(progress_interval), return; end
            wall=toc(progress_clock);
            if wall-progress_last<progress_interval, return; end
            progress_last=wall;
            fprintf(['[NE39-private-trial] pass=%d t=%.9g/%.9g steps=%d ' ...
                'attempts=%d rejected=%d next_h=%.3g energy_error=%.3g ' ...
                'refinement_error=%.3g wall=%.1fs\n'], ...
                pass,elapsed,T,a.steps,a.step_attempts,a.rejected_steps, ...
                proposed_h,a.energy_error_pu_s,path_refinement_error,wall);
        end
    end

    function [a,idx,comp]=angles(X,yy,now)
        idx=[]; a=[]; comp=[];
        labels=island_labels;
        for kk=1:numel(dae.devices)
            d=dae.devices(kk);
            xd=X(dae.device_offsets(kk)+(1:d.nx)); ud=u(dae.u_offsets(kk)+(1:d.nu));
            r=d.reconstruct(now,xd,yy,ud,ec);
            if ~r.online, continue; end
            if any(strcmpi(r.mode,{'sg','synchronous'}))
                theta=r.delta;
            elseif strcmpi(r.mode,'gfm')
                theta=r.gfm.delta_VSM;
            else
                continue;
            end
            if ~isnumeric(theta) || ~isscalar(theta) || ~isreal(theta) || ~isfinite(theta)
                error('stability:certify_ne39_transition:angle','ขาด finite SG/GFM angle evidence');
            end
            idx(end+1)=kk; a(end+1)=theta; comp(end+1)=labels(d.bus_position); %#ok<AGROW>
        end
    end
end

function policy=get_policy(opt)
policy="strict";
if isfield(opt,'assessment_policy'), policy=string(opt.assessment_policy); end
if ~isscalar(policy) || ~any(policy==["strict","observe_voltage"])
    error('stability:certify_ne39_transition:policy','assessment_policy ไม่ถูกต้อง');
end
end
