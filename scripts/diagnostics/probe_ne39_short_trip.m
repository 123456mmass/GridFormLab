function folder = probe_ne39_short_trip(composition,initial_gfm_ids)
%PROBE_NE39_SHORT_TRIP ทดสอบ production trip จริงก่อนขยาย horizon.
arguments
    composition (1,1) string = "1sg_9ibr"
    initial_gfm_ids (1,:) string = "IBR32"
end
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_trip_' char(composition) '_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
im=struct('device_id',{},'mode',{});
for id=initial_gfm_ids
    im(end+1)=struct('device_id',char(id),'mode','gfm'); %#ok<AGROW>
end
so=struct('study_capability',true,'initial_modes',im);
if composition=="5sg_5ibr", s=cases.scenario_ne39_5sg_5ibr(so);
else, s=cases.scenario_ne39_1sg_9ibr(so); end
e=struct('enabled',true,'event_profile','sg_cycle','sg_trip',.02, ...
    'sg_on',.1,'automatic_gfm_switching',true);
op=struct('t_end',.12,'dt',.005,'verbose',false,'ibr_events',e, ...
    'lazy_gfm_search',true,'budget',struct('max_full_evaluations',40, ...
    'stop_on_first_certified',true),'progress_every',.01, ...
    'progress_file',fullfile(folder,'progress.log'));
request=struct('scenario',s,'options',op); timer=tic;
result=stability.run_hybrid_case(s,op); elapsed=toc(timer);
save(fullfile(folder,'raw.mat'),'request','result','elapsed','-v7.3');
fid=fopen(fullfile(folder,'result.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
if isempty(result.t), reached=0; else, reached=result.t(end); end
id=''; why='';
if isfield(result,'failure_id'), id=result.failure_id; end
if isfield(result,'failure_reason'), why=result.failure_reason; end
text=sprintf('reached=%g/0.12 converged=%d failure=%s reason=%s elapsed=%.2fs\n', ...
    reached,result.converged,id,why,elapsed);
fprintf(fid,'%s',text); fprintf('%s',text);
if isfield(result,'selector_table')
    for name={'sg_on','sg_off'}
        ctx=result.selector_table.(name{1});
        for k=1:numel(ctx.configurations)
            c=ctx.configurations(k);
            fprintf('%s GFM=%s feasible=%d zeta=%g id=%s reason=%s\n', ...
                name{1},mat2str(c.selected_gfm_indices),c.feasible, ...
                value(c,'zeta_worst'),c.failure_id,c.reason);
        end
    end
end
if isfield(result,'event_log')
    for k=1:numel(result.event_log)
        q=result.event_log(k);
        fprintf('event=%s t=%g applied=%d id=%s detail=%s\n', ...
            q.type,q.t,q.applied,q.failure_id,q.details);
    end
end
if isfield(result,'controller_audit') && isfield(result.controller_audit,'ne39_transition')
    a=result.controller_audit.ne39_transition;
    for k=1:numel(a.passes)
        p=a.passes{k};
        fprintf('trial pass=%d t=%g reason=%s\n',k,p.t_reached,p.reason);
        if isfield(p,'failed_snapshot')
            fprintf('network voltage snapshot=%s\n',p.failed_snapshot.reason);
            for q=p.failed_snapshot.records
                if ~q.pass
                    fprintf('FAIL %s %s P=%g Q=%g V=%g f=%g I=%g Vdc=%g Idc=%g\n', ...
                        q.resource_id,q.failure,q.P_MW,q.Q_MVAr,q.V_pu,q.f_Hz, ...
                        q.I_converter_pu,q.Vdc_pu,q.Idc_pu);
                end
            end
        end
    end
end
fprintf('artifact=%s\n',folder);
end

function v=value(s,name)
v=NaN;
if isfield(s,name) && ~isempty(s.(name)), v=s.(name); end
end
