function report=ne39_restoration_preflight()
%NE39_RESTORATION_PREFLIGHT Build real destination evidence before chronology.
% No long chronology or acceptance relaxation. Missing coverage remains a hold.
[design,analysis]=ne39_endpoint_design_options();
c=cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(),design);
s=cases.scenario_ne39_tamu_mixed(c,struct('sg_reclose_plant',true, ...
    'initial_modes',analysis.initial_modes));
ibr=find(strcmpi({s.resources.resource_type},'ibr'));
sets=cell(1,numel(ibr));
for k=1:numel(ibr), sets{k}=setdiff(ibr,ibr(k),'stable'); end
for k=numel(ibr)-2:-1:0, sets{end+1}=ibr(1:k); end
sf=struct('enabled',true,'event_profile','fault_only', ...
    'automatic_gfm_switching',true, ...
    'fault_bus',16,'Zf',1i*1e6,'fault_on',.0002,'fault_clear',.0004, ...
    'gfm_selection_mode','manual_override','selected_gfm_indices',ibr, ...
    'n_gfm_required',numel(ibr),'reference_resource_index',ibr(1));
op=struct('t_end',.001,'dt',.001,'verbose',false,'ibr_events',sf, ...
    'lazy_gfm_search',true,'sg_on_candidate_sets',{sets}, ...
    'budget',struct('max_full_evaluations',20,'stop_on_first_certified',false), ...
    'healthy_pf_V',c.bus_data(:,3).','healthy_pf_bus_ids',c.bus_data(:,1).', ...
    'ne39_rate_policy',true,'ne39_weighted_severity',true);
r=stability.run_hybrid_case(s,op);
report=struct('status','PREFLIGHT_INCOMPLETE','failure_id','', ...
    'failure_reason','','production_certified',false);
if isfield(r,'failure_id'), report.failure_id=r.failure_id; end
if isfield(r,'failure_reason'), report.failure_reason=r.failure_reason; end
if isfield(r,'selector_table'), report.selector_table=r.selector_table; end
if ~isfield(report,'selector_table')
    if isfield(r,'metadata'), report.metadata=r.metadata; end
    disp(report); return;
end
cfg=report.selector_table.sg_on.configurations;
counts=zeros(1,numel(cfg)); ready=false(size(counts));
for k=1:numel(cfg)
    counts(k)=numel(cfg(k).selected_gfm_indices);
    ready(k)=isequal(cfg(k).ready_to_commit,true);
    fprintf('SG_ON set=%s ready=%d omega=%g reason=%s\n', ...
        mat2str(cfg(k).selected_gfm_indices),ready(k),cfg(k).omega,char(string(cfg(k).reason)));
end
report.evaluated_counts=counts;
report.certified_counts=counts(ready);
report.has_certified_one_step=any(ready & counts==numel(ibr)-1);
report.has_lower_count_endpoint=any(ready & counts<numel(ibr));
if report.has_certified_one_step
    report.status='NODE_COVERAGE_AVAILABLE_TRANSITION_TRIAL_PENDING';
end
folder=fullfile(pf_init_paths(),'output','diagnostics', ...
    ['ne39_restoration_preflight_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder); save(fullfile(folder,'preflight.mat'),'report','op','-v7.3');
fprintf('PREFLIGHT status=%s certified_counts=%s artifact=%s\n', ...
    report.status,mat2str(report.certified_counts),folder);
end
