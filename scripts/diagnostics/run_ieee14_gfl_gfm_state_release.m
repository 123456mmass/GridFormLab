function run_ieee14_gfl_gfm_state_release
%RUN_IEEE14_GFL_GFM_STATE_RELEASE  Audited 250-s mixed-resource chronology.
% The post-reclose return is owned by each IBR severity/dwell state machine;
% coordinated handback is deliberately disabled.

pf_init_paths();
pfile='output/diagnostics/engine_release_progress.log';
rfile='output/diagnostics/engine_release_result.log';
mfile='output/diagnostics/engine_release_result.mat';
archive_rfile='output/diagnostics/engine_release_250s_improved_result.log';
archive_mfile='output/diagnostics/engine_release_250s_improved_result.mat';
if exist(pfile,'file'), delete(pfile); end
if exist(rfile,'file'), delete(rfile); end

s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
ev=struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9, ...
    'Zf',0.01+0.01i,'line_trip',110,'line_from_bus',6, ...
    'line_to_bus',13,'restore_time',145,'sg_on',145, ...
    'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
opt=struct('t_end',250.0,'dt',0.1,'verbose',false, ...
    'ibr_events',ev,'plot_results',false,'max_step_subdivisions',9, ...
    'progress_every',0.1,'progress_file',pfile, ...
    'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00);

% CASE_DEFINED healthy voltage reference from the same SG-online case/PF.
sys0=ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4",sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);
opt.healthy_pf_V=sys0.pf.bus_voltage(:).';
opt.healthy_pf_bus_ids=sys0.pf.external_bus_ids(:).';

r=stability.run_hybrid_case(s,opt);
save(mfile,'r','opt','-v7.3');
write_result_log(r,rfile,sys0);
save(archive_mfile,'r','opt','-v7.3');
write_result_log(r,archive_rfile,sys0);
fprintf('ENGINE_RELEASE_DONE converged=%d t_end=%.6f\n', ...
    r.converged,last_time(r));
end

function write_result_log(r,rfile,sys0)
fid=fopen(rfile,'w');
if fid<0, error('run_ieee14_gfl_gfm_state_release:logOpen', ...
        'Could not open %s.',rfile); end
c=onCleanup(@() fclose(fid));
fprintf(fid,'converged=%d n_t=%d t_end=%.6f\n', ...
    r.converged,numel(r.t),last_time(r));
if ~r.converged
    if isfield(r,'metadata')
        fprintf(fid,'failure=%s\n',string_field(r.metadata,'failure'));
        fprintf(fid,'reason=%s\n',string_field(r.metadata,'error'));
    end
    return;
end

V=complex(r.y_traj(1:2:end,:),r.y_traj(2:2:end,:));
fprintf(fid,'frequency_min_Hz=%.12g frequency_max_Hz=%.12g\n', ...
    min(r.coi_frequency_Hz),max(r.coi_frequency_Hz));
fprintf(fid,'voltage_min_pu=%.12g voltage_max_pu=%.12g\n', ...
    min(abs(V),[],'all'),max(abs(V),[],'all'));
fprintf(fid,'subdivision_depth=%d domain_rejected_trials=%d\n', ...
    r.subdivision_depth,r.domain_rejected_trials);

fprintf(fid,'\nevents:\n');
for k=1:numel(r.event_log)
    e=r.event_log(k);
    fprintf(fid,'  t=%.6f type=%s applied=%d details=%s\n', ...
        e.t,string(e.type),e.applied,string(e.details));
end

t=r.t(:); didx=2:5; modes=string(r.device_modes_history(didx,:)).';
sgon=logical(r.device_online_history(1,:)).';
bp=zeros(1,4);
for j=1:4
    bp(j)=find(r.bus_ids==r.device_bus_ids(didx(j)),1);
end
ibrV=abs(V(bp,:)).';
hV=sys0.pf.bus_voltage(:).'; hB=sys0.pf.external_bus_ids(:).';
sev=zeros(numel(t),4);
for j=1:4
    bp0=find(hB==r.device_bus_ids(didx(j)),1);
    vref=hV(bp0);
    sev(:,j)=min(1,max(0,0.5*abs(ibrV(:,j)-vref)/0.10 + ...
        0.5*abs(r.coi_frequency_Hz(:)-60)/0.50));
end

fprintf(fid,'\nselected timeline:\n');
for tt=[0 20 50 85 85.15 110 145 146 150 160 170 180 190 200 225 250]
    k=find(t>=tt-1e-9,1); if isempty(k), k=numel(t); end
    fprintf(fid,['  t=%.3f sg=%d mode=[%s %s %s %s] ' ...
        'V=[%.6f %.6f %.6f %.6f] S=[%.6f %.6f %.6f %.6f]\n'], ...
        t(k),sgon(k),modes(k,1),modes(k,2),modes(k,3),modes(k,4), ...
        ibrV(k,1),ibrV(k,2),ibrV(k,3),ibrV(k,4), ...
        sev(k,1),sev(k,2),sev(k,3),sev(k,4));
end

fprintf(fid,'\nindex-driven handback:\n');
for j=1:4
    post_trip=find(t>=20 & t<145 & strcmpi(modes(:,j),'GFM'),1,'last');
    eligible=NaN; actual=NaN;
    if ~isempty(post_trip)
        candidates=find(t>=145 & sev(:,j)<0.35 & isfinite(sev(:,j)));
        for q=1:numel(candidates)
            k=candidates(q); kend=find(t>=t(k)+1.0-1e-9,1);
            if ~isempty(kend) && all(sev(k:kend,j)<0.35)
                eligible=t(kend); break;
            end
        end
        gfl=find(t>=145 & strcmpi(modes(:,j),'gfl'),1);
        if ~isempty(gfl), actual=t(gfl); end
    end
    fprintf(fid,['  IBR%d bus=%g was_GFM=%d severity_eligible_s=%.6f ' ...
        'actual_GFL_release_s=%.6f\n'],j,r.device_bus_ids(didx(j)), ...
        ~isempty(post_trip),eligible,actual);
end
fprintf(fid,'reselection_status=%s actual_mode_reselection_time=%.6f\n', ...
    string(r.reselection_status),r.actual_mode_reselection_time);
if isfield(r,'handback_status')
    fprintf(fid,['handback_status=%s handback_start_s=%.6f ' ...
        'handback_duration_s=%.6f handback_complete_s=%.6f\n'], ...
        string(r.handback_status),r.handback_start_time, ...
        r.handback_duration_s,r.handback_complete_time);
end
end

function t=last_time(r)
t=NaN; if isfield(r,'t') && ~isempty(r.t), t=r.t(end); end
end

function s=string_field(x,n)
s=""; if isfield(x,n), s=string(x.(n)); end
end
