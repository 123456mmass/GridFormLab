function folder=probe_ne39_short_physical_events(design_request,assessment_policy)
%PROBE_NE39_SHORT_PHYSICAL_EVENTS ตรวจ short TS ด้วย canonical coupled kernel.
% เริ่ม SG_OFF equilibrium; ย่อระยะรอ ไม่ใช่ chronology160s/selector/reclose.
% ไม่มี global path refinement จึงไม่เป็น production/private certificate.
arguments
    design_request (1,1) string
    assessment_policy (1,1) string {mustBeMember(assessment_policy,["strict","observe_voltage"])} = "strict"
end
root=pf_init_paths(); loaded=load(design_request,'request'); s=loaded.request.scenario;
c=s.case_data; off=s.resources; ii=find(strcmp({off.resource_type},'ibr'));
sg=find(strcmp({off.resource_type},'sg'));
if numel(sg)~=1 || numel(ii)~=9
    error('probe_ne39_short_physical_events:resources','ต้องเป็น 1SG+9IBR');
end
off(sg).initial_online=false; off(sg).initial_mode='breaker_open';
for k=ii, off(k).initial_mode='gfm'; end
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_short_physical_events_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
% ให้ load response settle ก่อน fault; 5s > 95% decay time ของ SG_OFF ชุดล่าสุด.
% เป็น diagnostic timing ไม่แทน chronology ที่รอ35sจริงก่อน fault.
times=[0 .4 5.4 5.55 6.4 7.4 8.4];
names={'initial','load_on','fault_on','fault_clear','line_trip','restore'};
op=struct('newton_tol',1e-9,'max_iter',50,'fd_eps',3e-6,'full_kcl',true, ...
    'domain_preserving_trials',true,'integration_method','trapezoidal', ...
    'atol_x',2e-8,'rtol_x',1e-7,'atol_y',2e-8,'rtol_y',1e-7);
bounds=struct('v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5);
request=struct('source_request',design_request,'case_data',c,'resources',off, ...
    'times',times,'event_names',{names},'options',op,'bounds',bounds, ...
    'energy_tol_pu_s',1e-6,'kcl_tol',1e-6,'production_certified',false, ...
    'global_refinement_performed',false,'assessment_policy',char(assessment_policy));
save(fullfile(folder,'request.mat'),'request','-v7.3');
result=struct('status','NOT_FINISHED','reason','','production_certified',false, ...
    'global_refinement_performed',false,'floor_accepted_steps',0, ...
    'energy_error_pu_s',0,'step_attempts',0,'rejected_steps',0, ...
    'assessment_policy',char(assessment_policy));
T=0; h=.0025; floor_h=.0025/4096; samples=struct([]); events=struct([]);
x=[]; y=[]; u=[]; ec=struct(); X=[]; V=[]; rejections=struct([]);
clock=tic; last_progress=-Inf;
try
    [dev,~]=stability.build_mixed_resource_devices(c,off, ...
        struct('dispatch',c.dispatch_contract.post_trip.post_trip_Pg_MW));
    dae=stability.composite_dae(c,dev,struct());
    ec=struct('hybrid_state',stability.ts_hybrid_state_init(dev));
    z=stability.mixed_ibr_reduced_initialize(dae,ec,ii(1), ...
        struct('tolerance',1e-10,'max_iter',300));
    if ~z.converged
        error('probe_ne39_short_physical_events:steady','%s',z.failure_reason);
    end
    x=z.x0; y=z.y0; u=z.u_eq; Y0=dae.Ynet; Y=Y0;
    dY=.2*diag(conj(complex(c.mpc.bus(:,3),c.mpc.bus(:,4))/c.mpc.baseMVA) ...
        ./(dae.pf.bus_voltage.^2+eps));
    stamp=line_stamp(c.mpc,16,17);
    fault_bus=find(c.mpc.bus(:,1)==16);
    if numel(fault_bus)~=1
        error('probe_ne39_short_physical_events:bus','fault bus ไม่ unique');
    end
    active=stability.ts_dynamic_state_indices(dae,ec);
    [row,flow,E0]=snapshot(T,x,y,Y,NaN,'initial',u,ec,dae,off,c,bounds);
    samples=row; X=x; V=y; integral=zeros(size(flow));
    require_snapshot(row);
    for phase=1:numel(times)-1
        if phase>1
            left_x=x; left_y=y; left_u=u; left_ec=ec; left_Y=Y;
            switch names{phase}
                case 'load_on', Y=Y0+dY;
                case 'fault_on', Y(fault_bus,fault_bus)=Y(fault_bus,fault_bus)+1/(1i*.1);
                case 'fault_clear', Y(fault_bus,fault_bus)=Y(fault_bus,fault_bus)-1/(1i*.1);
                case 'line_trip', Y=Y-stamp;
                case 'restore', Y=Y0;
            end
            g=@(xx,yy,YY)dae.dae_g(T,xx,yy,YY,u,ec);
            [y,ainfo]=stability.ts_algebraic_solve(x,y,Y,g,@stability.ts_jac_y_fd,op.newton_tol);
            if ~ainfo.converged
                error('probe_ne39_short_physical_events:kcl','event KCL ไม่ converged');
            end
            [row,nextflow,E]=snapshot(T,x,y,Y,NaN,'right',u,ec,dae,off,c,bounds);
            events=[events,struct('name',names{phase},'t',T,'x_left',left_x, ...
                'y_left',left_y,'u_left',left_u,'context_left',left_ec, ...
                'Y_left',left_Y,'Y_right',Y,'solver',ainfo, ...
                'state_continuity_exact',isequal(x,left_x), ...
                'input_continuity_exact',isequal(u,left_u), ...
                'context_continuity_exact',isequal(ec,left_ec),'right_snapshot',row)]; %#ok<AGROW>
            samples=[samples,row]; X(:,end+1)=x; V(:,end+1)=y; %#ok<AGROW>
            require_snapshot(row);
            check_energy(E); flow=nextflow; % right-limit flow, ไม่มี impulse/reset ของ DC.
            h=min(h,.0025);
        end
        while T<times(phase+1)-1e-12
            h=min(h,times(phase+1)-T);
            [half,fine,err,kcl]=full_and_fine(x,y,T,h,dae,Y,u,ec,active,op);
            result.step_attempts=result.step_attempts+1;
            if ~isfinite(err) || err>1 || ~isfinite(kcl) || kcl>op.newton_tol
                result.rejected_steps=result.rejected_steps+1;
                rejections=[rejections,struct('t',T,'h',h,'LTE',err,'kcl',kcl)]; %#ok<AGROW>
                factor=.5;
                if isfinite(err) && err>1, factor=max(.2,min(.5,.9*err^(-1/3))); end
                if h*factor<floor_h
                    error('probe_ne39_short_physical_events:floor', ...
                        'strict LTE/Newton ถึง floor ที่ t=%g err=%g kcl=%g',T,err,kcl);
                end
                h=h*factor; continue; % committed x/y/u/ec ยังไม่เปลี่ยน.
            end
            % accepted path คือสอง half steps; ตรวจ midpoint จริงด้วย.
            [mid,midflow,midE]=snapshot(T+h/2,half.x_full,half.y_full,Y,err,'continuous',u,ec,dae,off,c,bounds);
            [last,lastflow,lastE]=snapshot(T+h,fine.x_full,fine.y_full,Y,err,'continuous',u,ec,dae,off,c,bounds);
            x=fine.x_full; y=fine.y_full; T=T+h;
            samples=[samples,mid,last]; %#ok<AGROW>
            X=[X,half.x_full,x]; V=[V,half.y_full,y]; %#ok<AGROW>
            require_snapshot(mid); require_snapshot(last);
            integral=integral+.25*h*(flow+midflow); check_energy(midE);
            integral=integral+.25*h*(midflow+lastflow); check_energy(lastE); flow=lastflow;
            if toc(clock)-last_progress>=30
                fprintf('[NE39-short-events] phase=%s t=%g LTE=%g energy=%g\n', ...
                    names{phase},T,err,result.energy_error_pu_s);
                last_progress=toc(clock);
            end
            h=min(.025,h*min(2,max(.2,.9*max(err,1e-12)^(-1/3))));
        end
    end
    result.status='SHORT_SCREEN_PASS';
    if assessment_policy=="observe_voltage", result.status='SHORT_STUDY_COMPLETED'; end
catch me
    result.status='SHORT_SCREEN_FAIL';
    if assessment_policy=="observe_voltage", result.status='SHORT_STUDY_FAILED'; end
    result.reason=me.message;
    result.failure_id=me.identifier; result.failure_stack=me.stack;
end
result.t_reached=T; result.samples=samples; result.events=events;
result.x_traj=X; result.y_traj=V; result.x_last=x; result.y_last=y;
result.u=u; result.event_context=ec; result.rejections=rejections; result.elapsed_s=toc(clock);
result.assessment_policy=char(assessment_policy);
result.strict_snapshot_pass=~isempty(samples) && all(arrayfun(@(q)strcmp(q.evidence.status,'PASS'),samples));
if ~isempty(samples)
    result.voltage_observation=stability.ne39_voltage_observation( ...
        [samples.t],abs(complex(V(1:2:end,:),V(2:2:end,:))),c.mpc.bus(:,1),bounds);
end
save(fullfile(folder,'screen.mat'),'request','result','-v7.3');
fprintf('%s reached=%g reason=%s artifact=%s\n',result.status,T,result.reason,folder);
if isfield(result,'voltage_observation')
    a=result.voltage_observation;
    fprintf('V_STUDY V=[%.9g %.9g] excursion=%d final_in_band=%d since=%g span=%g energy=%g\n', ...
        a.voltage_min_pu,a.voltage_max_pu,a.any_excursion,a.final_all_in_band, ...
        a.final_in_band_since_sample_s,a.final_in_band_sampled_span_s,result.energy_error_pu_s);
end

    function require_snapshot(row)
        allowed=stability.ne39_snapshot_policy(row.evidence,assessment_policy);
        if ~isfinite(row.kcl) || row.kcl>request.kcl_tol || ~allowed
            failed=row.evidence.records(~[row.evidence.records.pass]);
            details=strjoin(arrayfun(@(r)[r.resource_id ':' r.failure],failed,'UniformOutput',false),';');
            error('probe_ne39_short_physical_events:physical', ...
                'physical FAIL t=%g side=%s V=[%g %g] KCL=%g %s', ...
                row.t,row.side,row.Vmin,row.Vmax,row.kcl,details);
        end
    end

    function check_energy(E)
        energy_residual=max(abs(E-E0-integral));
        result.energy_error_pu_s=max(result.energy_error_pu_s,energy_residual);
        if ~isfinite(energy_residual) || energy_residual>request.energy_tol_pu_s
            error('probe_ne39_short_physical_events:energy','DC energy ledger FAIL err=%g',energy_residual);
        end
    end
end

function [row,flow,E]=snapshot(t,xx,yy,YY,lte,side,u,ec,dae,off,c,bounds)
% local function แยก workspace: ไม่ให้ flow/err ทับ adaptive/energy controller.
e=stability.ne39_transition_snapshot(t,xx,yy,u,ec,dae,off,c,bounds);
voltage=complex(yy(1:2:end),yy(2:2:end));
row=struct('t',t,'side',side,'Vmin',min(abs(voltage)),'Vmax',max(abs(voltage)), ...
    'kcl',norm(YY*voltage-dae.current_injection(t,xx,yy,u,ec),inf),'LTE',lte,'evidence',e);
rows=e.records(startsWith({e.records.resource_id},'IBR'));
if numel(rows)~=nnz(strcmp({off.resource_type},'ibr'))
    error('probe_ne39_short_physical_events:evidence','IBR/DC evidence ไม่ครบ');
end
flow=[rows.source_minus_losses_pu];
E=[rows.capacitor_energy_pu_s]+[rows.source_inductor_energy_pu_s];
end

function [half,fine,err,kcl]=full_and_fine(x,y,t,h,dae,Y,u,ec,active,op)
% ใช้สูตร production hybrid เดิม: x Richardson/3, y difference ไม่หาร3.
op.t_now=t; full=stability.ts_step_composite(x,y,h,dae,Y,u,ec,active,op);
half=full; fine=full; err=Inf; kcl=Inf;
if ~full.converged || ~full.finite, return; end
half=stability.ts_step_composite(x,y,h/2,dae,Y,u,ec,active,op);
if ~half.converged || ~half.finite, return; end
op.t_now=t+h/2;
fine=stability.ts_step_composite(half.x_full,half.y_full,h/2,dae,Y,u,ec,active,op);
if ~fine.converged || ~fine.finite, return; end
scx=op.atol_x+op.rtol_x*max(abs(x(active)),abs(fine.x_full(active)));
scy=op.atol_y+op.rtol_y*max(abs(y),abs(fine.y_full));
ex=(fine.x_full(active)-full.x_full(active))/3;
ey=fine.y_full-full.y_full;
err=max(sqrt(mean((ex./scx).^2)),sqrt(mean((ey./scy).^2)));
ny=numel(y); kcl=norm(fine.terminal_residual_vector(end-ny+1:end),inf);
end

function Y=line_stamp(mpc,from,to)
% MATPOWER transformer/tap/charging stamp; trip เฉพาะ source circuit นี้.
hit=(mpc.branch(:,1)==from & mpc.branch(:,2)==to) | ...
    (mpc.branch(:,1)==to & mpc.branch(:,2)==from);
if nnz(hit)~=1, error('probe_ne39_short_physical_events:line','line ไม่ unique'); end
b=mpc.branch(hit,:); i=find(mpc.bus(:,1)==b(1)); j=find(mpc.bus(:,1)==b(2));
a=b(9); if a==0, a=1; end
a=a*exp(1i*deg2rad(b(10))); ys=1/complex(b(3),b(4));
Y=complex(zeros(size(mpc.bus,1)));
Y(i,i)=(ys+1i*b(5)/2)/abs(a)^2; Y(j,j)=ys+1i*b(5)/2;
Y(i,j)=-ys/conj(a); Y(j,i)=-ys/a;
end
