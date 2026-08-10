function run_ieee14_gfm4_fault_probe
%RUN_IEEE14_GFM4_FAULT_PROBE  Diagnostic all-GFM arm through fault clearing.
% This manual tuple is validation-only. It does not define production
% selection policy and cannot be consumed by the automatic launcher.

pf_init_paths();
pfile='output/diagnostics/gfm4_fault_probe_progress.log';
rfile='output/diagnostics/gfm4_fault_probe_result.mat';
if exist(pfile,'file'), delete(pfile); end

s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
ev=struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9, ...
    'Zf',0.01+0.01i,'line_trip',85.90,'line_from_bus',6, ...
    'line_to_bus',13,'restore_time',85.99,'sg_on',85.99, ...
    'coordinated_handback',false,'automatic_gfm_switching',true, ...
    'selected_gfm_indices',[2 3 4 5], ...
    'reference_resource_index',2, ...
    'delays_overrides',struct('timeout_s',5,'dwell_s',0.5));
opt=struct('t_end',86.0,'dt',0.1,'verbose',false, ...
    'ibr_events',ev,'plot_results',false,'max_step_subdivisions',8, ...
    'progress_every',5.0,'progress_file',pfile);
sys0=ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4",sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);
opt.healthy_pf_V=sys0.pf.bus_voltage(:).';
opt.healthy_pf_bus_ids=sys0.pf.external_bus_ids(:).';

r=stability.run_hybrid_case(s,opt);
save(rfile,'r','opt','-v7.3');
fprintf(['GFM4_FAULT_PROBE_DONE converged=%d t_end=%.6f ' ...
    'failure=%s reason=%s\n'],r.converged,last_time(r), ...
    result_field(r,'failure_id'),result_field(r,'failure_reason'));
end

function t=last_time(r)
t=NaN;
if isfield(r,'t') && ~isempty(r.t), t=r.t(end); end
end

function s=result_field(r,name)
s="";
if isfield(r,name), s=string(r.(name)); return; end
if isfield(r,'metadata') && isstruct(r.metadata)
    if strcmp(name,'failure_id') && isfield(r.metadata,'failure')
        s=string(r.metadata.failure);
    elseif strcmp(name,'failure_reason') && isfield(r.metadata,'error')
        s=string(r.metadata.error);
    end
end
end
