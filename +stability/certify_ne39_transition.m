function [ok,audit] = certify_ne39_transition(t,x,y,u,ec,Y,dae,resources,c,bounds,candidate,opt)
%CERTIFY_NE39_TRANSITION private forward trial; ไม่เปลี่ยน live state หรือ timer.
% ตรวจ snapshot ทุก accepted trial sample และรัน dt/2 ยืนยัน energy accounting.
% PASS เป็นหลักฐาน trajectory เท่านั้น; caller ต้อง authenticate context/transfer.
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
ok=false;
audit=struct('status','UNKNOWN','reason','ขาด certified spectrum/trial contract', ...
    'horizon_s',NaN,'passes',{{}},'commit_authorized',false, ...
    'refinement_scope','ALL_COARSE_ACCEPTED_TIMES','refinement_samples',0);
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
audit.horizon_s=T;
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
    if ~strcmp(a.status,'PASS')
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
ok=true; audit.status='PASS'; audit.reason='PRIVATE_TRIAL_AND_REFINEMENT_PASS';

    function [a,X,yy]=trial(dt,pass)
        X=x; yy=y; elapsed=0; next_coarse=2; proposed_h=dt;
        if pass==1
            coarse_t=zeros(1,ceil(T/dt)+1);
            coarse_state=zeros(numel(active)+numel(y),numel(coarse_t));
            coarse_state(:,1)=[X(active);yy];
        end
        a=struct('status','UNKNOWN','reason','','dt',dt,'steps',0, ...
            't_reached',0,'energy_error_pu_s',0,'peak_angle_excursion_deg',0, ...
            'step_attempts',0,'rejected_steps',0,'min_dt',Inf,'max_dt',0, ...
            'peak_local_refinement_error',0);
        e=stability.ne39_transition_snapshot(t,X,yy,u,ec,dae,resources,c,bounds);
        if ~strcmp(e.status,'PASS')
            a.status=e.status; a.reason=e.reason; a.failed_snapshot=e; return;
        end
        residual=dae.dae_g(t,X,yy,Y,u,ec);
        if any(~isfinite(residual)) || norm(residual,inf)>opt.kcl_tol
            a.reason='RIGHT_KCL_NOT_RESOLVED'; return;
        end
        % กำหนดคู่ synchronism เฉพาะ SG/GFM ที่อยู่ energized island เดียวกัน.
        [angle0,former,component]=angles(X,yy,t);
        adjacency=abs(Y)>0; adjacency(1:size(Y,1)+1:end)=false;
        labels=conncomp(graph(adjacency | adjacency.'));
        if isempty(former) || ~all(ismember(unique(labels),component))
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
                    h=min(h,interval/2);
                end
                h=min(h,coarse_t(next_coarse)-elapsed);
            end
            sopt=struct('t_now',t+elapsed,'newton_tol',opt.newton_tol, ...
                'max_iter',opt.max_iter,'fd_eps',opt.fd_eps,'verbose',false, ...
                'full_kcl',true,'domain_preserving_trials',true);
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
                    proposed_h=min(dt,h*factor);
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
                path_refinement_error=max(path_refinement_error,err_state);
                audit.refinement_samples=audit.refinement_samples+1;
                if err_state>opt.refinement_tol
                    a.reason='DT_REFINEMENT_NOT_RESOLVED'; return;
                end
                next_coarse=next_coarse+1;
            end
            residual=dae.dae_g(t+elapsed,X,yy,Y,u,ec);
            if any(~isfinite(residual)) || norm(residual,inf)>opt.kcl_tol
                a.reason='TRIAL_KCL_NOT_RESOLVED'; return;
            end
            e=stability.ne39_transition_snapshot(t+elapsed,X,yy,u,ec,dae,resources,c,bounds);
            if ~strcmp(e.status,'PASS')
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
        progress();

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
        adjacency=abs(Y)>0; adjacency(1:size(Y,1)+1:end)=false;
        labels=conncomp(graph(adjacency | adjacency.'));
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
