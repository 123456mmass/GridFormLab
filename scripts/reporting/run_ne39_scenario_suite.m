function out = run_ne39_scenario_suite(opts)
%RUN_NE39_SCENARIO_SUITE raw production results แยก composition/policy/suite.
% ไม่ยกเลิก gate เพื่อให้ scenario ผ่าน; blocked run เก็บเป็นผลจริงแยกต่างหาก.
arguments
    opts.compositions (1,:) string = ["5sg_5ibr","1sg_9ibr"]
    opts.scenarios (1,:) string = ["no_event","fault_bus16", ...
        "load_step20","line_outage_restore","sg_cycle", ...
        "sg_load_step20","sg_fault_bus16","line_fault_16_17","former_outage"]
    opts.policies (1,:) string = ["si","enhanced"]
    opts.dt (1,1) double {mustBePositive} = .01
    opts.t_end (1,1) double = NaN
    opts.outdir (1,1) string = ""
    opts.reuse_completed (1,1) logical = true
    opts.initial_gfm_ids (1,:) string = strings(1,0)
    opts.max_full_evaluations (1,1) double {mustBeInteger,mustBePositive} = 6
    opts.policy_options (1,1) struct = struct()
end
root=pf_init_paths();
if strlength(opts.outdir)==0
    opts.outdir=string(fullfile(root,'output','diagnostics','ne39_scenario_suite'));
end
if ~isfinite(opts.dt) || (~isnan(opts.t_end) && ...
        (~isfinite(opts.t_end) || opts.t_end<=0))
    error('run_ne39_scenario_suite:time','dt/horizon ต้อง finite และเป็นบวก');
end
if ~all(ismember(opts.compositions,["5sg_5ibr","1sg_9ibr"])) || ...
        ~all(ismember(opts.policies,["si","enhanced"]))
    error('run_ne39_scenario_suite:request','composition/policy ไม่ถูกต้อง');
end
rows=stability.ne39_scenario_catalog();
if ~all(ismember(opts.scenarios,string({rows.id})))
    error('run_ne39_scenario_suite:scenario','ไม่รู้จัก scenario');
end
rows=rows(ismember(string({rows.id}),opts.scenarios));
source_hash=model_hash(root);
out=struct('schema','ne39_scenario_suite/1','classification', ...
    'REPORTING_OVER_PRODUCTION_NOT_SWITCHING_CERTIFICATE', ...
    'model_sha256',source_hash,'results',struct([]));
for composition=opts.compositions
    initial_modes=struct('device_id',{},'mode',{});
    for id=opts.initial_gfm_ids
        initial_modes(end+1)=struct('device_id',char(id),'mode','gfm'); %#ok<AGROW>
    end
    scenario_opt=struct('study_capability',true,'initial_modes',initial_modes);
    if composition=="5sg_5ibr"
        s=cases.scenario_ne39_5sg_5ibr(scenario_opt);
    else
        s=cases.scenario_ne39_1sg_9ibr(scenario_opt);
    end
    for row=rows
        T=row.horizon_s;
        if isfinite(opts.t_end), T=opts.t_end; end
        for policy=opts.policies
            op=struct('t_end',T,'dt',opts.dt,'verbose',false, ...
                'automatic_gfm_switching',row.events.automatic_gfm_switching);
            if row.events.enabled
                op.ibr_events=row.events;
                op.healthy_pf_V=s.case_data.bus_data(:,3);
                op.healthy_pf_bus_ids=s.case_data.bus_data(:,1);
                op.online_rate_measurement=true;
                op.automatic_support_supervision=row.events.automatic_gfm_switching;
                op.ne39_rate_policy=policy=="enhanced";
                if policy=="enhanced", op.ne39_policy=opts.policy_options; end
                if row.events.automatic_gfm_switching
                    op.lazy_gfm_search=true;
                    op.budget=struct('max_full_evaluations',opts.max_full_evaluations, ...
                        'stop_on_first_certified',true);
                end
            end
            % fault-only/network-only arms ไม่มี switching authority โดยเจตนา.
            % ระบุใน request เพื่อไม่ปนกับ certified operating-configuration comparison.
            request=struct('composition',composition,'policy',policy, ...
                'scenario',row,'options',op,'initial_gfm_ids',opts.initial_gfm_ids, ...
                'initial_modes',{string({s.resources.initial_mode})}, ...
                'model_sha256',source_hash,'case_data',s.case_data,'resources',s.resources);
            category='suite';
            if strcmp(row.id,'chronology'), category='chronology'; end
            folder=fullfile(opts.outdir,composition,policy,category);
            if ~isfolder(folder), mkdir(folder); end
            artifact=fullfile(folder,[row.id '.mat']); reused=false;
            cache_rejection='';
            if isfile(artifact)
                stored=load(artifact,'request','result','elapsed');
                if opts.reuse_completed && all(isfield(stored,{'request','result','elapsed'})) && ...
                        isequaln(stored.request,request)
                    r=stored.result; elapsed=stored.elapsed; reused=true;
                else
                    cache_rejection='REQUEST_OR_MODEL_CHANGED_OR_REUSE_DISABLED';
                end
            end
            if ~reused
                timer=tic;
                try
                    r=stability.run_hybrid_case(s,op);
                catch me
                    r=struct('converged',false,'t',[],'x_traj',[],'y_traj',[], ...
                        'failure_id',me.identifier,'failure_reason',me.message);
                end
                elapsed=toc(timer);
                result=r; %#ok<NASGU>
                save(artifact,'request','result','elapsed','-v7.3');
            end
            m=stability.ne39_event_metrics(r,row,T);
            m.composition=char(composition); m.policy=char(policy);
            m.scope=row.scope; m.initial_gfm_ids=cellstr(opts.initial_gfm_ids);
            m.elapsed_s=elapsed; m.cache_reused=reused; m.artifact=char(artifact);
            m.cache_rejection=cache_rejection;
            m.raw_sha256=file_hash(artifact);
            if ~row.events.enabled
                m.policy_execution='NO_EVENT_LEGACY_PATH_NO_ONLINE_POLICY';
            elseif isfield(r,'ne39_decision_log')
                m.policy_execution='ACCEPTED_SAMPLE_ENHANCED_POLICY';
            else
                m.policy_execution='SI_PATH_OR_PRE_TS_GATE_REFUSAL';
            end
            if isempty(out.results), out.results=m; else, out.results(end+1)=m; end %#ok<AGROW>
            fid=fopen(fullfile(folder,[row.id '.json']),'w');
            if fid<0, error('run_ne39_scenario_suite:output','เปิด summary ไม่ได้'); end
            cleanup=onCleanup(@()fclose(fid));
            fprintf(fid,'%s',jsonencode(m,PrettyPrint=true)); clear cleanup;
            fprintf('%s/%s/%s reached=%.4g/%g defining=%d converged=%d failure=%s\n', ...
                composition,policy,row.id,m.reached_horizon_s,T, ...
                m.defining_event_executed,m.numerically_converged,m.failure_id);
        end
    end
end
out.manifest_scope='THIS_REQUEST_ONLY_RAW_ARMS_REMAIN_IN_SEPARATE_DIRECTORIES';
end

function hash=model_hash(root)
% รวม model/case/solver/helper จริงทุกไฟล์; ไม่ reuse cache หลังเปลี่ยน equation/policy.
files=[];
for package={'+cases','+ibr','+stability','+pfsolver','internal'}
    files=[files;dir(fullfile(root,package{1},'**','*.m'))]; %#ok<AGROW>
end
files=[files;dir(fullfile(root,'scripts','reporting','run_ne39*.m'))];
paths=arrayfun(@(f)fullfile(f.folder,f.name),files,'UniformOutput',false);
paths=sort(paths); text='';
for k=1:numel(paths)
    text=[text,strrep(paths{k},root,''),'|',file_hash(paths{k}),newline]; %#ok<AGROW>
end
h=java.security.MessageDigest.getInstance('SHA-256');
h.update(unicode2native(text,'UTF-8'));
hash=sprintf('%02x',typecast(h.digest(),'uint8'));
end

function hash=file_hash(file)
fid=fopen(file,'rb');
if fid<0, error('run_ne39_scenario_suite:hash','อ่านไฟล์สำหรับ hash ไม่ได้'); end
cleanup=onCleanup(@()fclose(fid));
h=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    bytes=fread(fid,65536,'*uint8'); h.update(bytes);
end
hash=sprintf('%02x',typecast(h.digest(),'uint8'));
end
