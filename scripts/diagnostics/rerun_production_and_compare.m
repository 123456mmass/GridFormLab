function out = rerun_production_and_compare(varargin)
%RERUN_PRODUCTION_AND_COMPARE Authoritative gate for the TS runtime work.
%   Re-runs the switching production request with the SAME options that
%   scripts/reporting/generate_ieee14_switch_report_figures.m issues
%   (production_request, verbatim), writes a NEW cache file, and compares it
%   against the existing production cache with
%   scripts/diagnostics/compare_ts_equivalence.
%
%   The comparison horizon is read from the existing cache itself (r.t(end)),
%   not from the generator's T_end_contract, so a 200-s cache is never
%   compared against a 250-s rerun.
%
%   Nothing overwrites output/diagnostics/engine_release_result.mat.
%
%   Usage:
%     out = rerun_production_and_compare();                  % inspect + run
%     out = rerun_production_and_compare('inspect_only',true);

p = struct('cache',fullfile('output','diagnostics','engine_release_result.mat'), ...
    'new_cache',fullfile('output','diagnostics','engine_release_result_opt.mat'), ...
    'progress_file',fullfile('output','diagnostics','engine_release_opt_progress.log'), ...
    'progress_every',1.0,'inspect_only',false,'tol',0, ...
    't_end_override',NaN);
if mod(numel(varargin),2)~=0
    error('rerun_production_and_compare:badArgs','Expected name/value pairs.');
end
for k = 1:2:numel(varargin)
    p.(char(varargin{k})) = varargin{k+1};
end

pf_init_paths();
if ~exist(p.cache,'file')
    error('rerun_production_and_compare:missingCache', ...
        'Reference cache %s does not exist.',p.cache);
end
ref = load(p.cache,'r');
r_ref = ref.r;
types = string({r_ref.equilibrium.devices(2:5).device_type});
fprintf(['CACHE %s\n  converged=%d  t(end)=%.6f  samples=%d  ' ...
    'ibr_types=%s\n'], p.cache, r_ref.converged, r_ref.t(end), ...
    numel(r_ref.t), strjoin(unique(types),','));
hb = 'ABSENT';
if isfield(r_ref,'handback_status'), hb = char(string(r_ref.handback_status)); end
fprintf('  dt(first)=%.6f  reclose=%s at %.4f  handback=%s\n', ...
    r_ref.t(2)-r_ref.t(1), string(r_ref.reclose_status), ...
    r_ref.actual_reclose_time, hb);
if isfinite(p.t_end_override)
    T_end = p.t_end_override;
else
    T_end = r_ref.t(end);
end
fprintf('  comparison horizon T_end=%.6f s\n',T_end);
if p.inspect_only
    out = struct('reference',p.cache,'t_end',r_ref.t(end), ...
        'converged',r_ref.converged,'inspect_only',true);
    return;
end

sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);
[scenario,opt] = local_production_request(sys,T_end);
opt.progress_every = p.progress_every;
opt.progress_file = p.progress_file;
if exist(p.progress_file,'file'), delete(p.progress_file); end

fprintf('RERUN start T_end=%.4f dt=%.4f max_step_subdivisions=%d\n', ...
    opt.t_end,opt.dt,opt.max_step_subdivisions);
t0 = tic;
r = stability.run_hybrid_case(scenario,opt);
wall = toc(t0);
fprintf('RERUN done wall=%.1f s (%.2f min) converged=%d t(end)=%.6f\n', ...
    wall,wall/60,r.converged,r.t(end));
save(p.new_cache,'r','wall','opt','-v7.3');
fprintf('SAVED %s\n',p.new_cache);

cmp = compare_ts_equivalence(p.cache,p.new_cache, ...
    struct('tol',p.tol,'label','production rerun vs existing cache'));
out = struct('wall_s',wall,'converged',logical(r.converged), ...
    't_end',r.t(end),'new_cache',p.new_cache,'comparison',cmp, ...
    'reference_t_end',r_ref.t(end));
end

% =========================================================================
function [s,opt] = local_production_request(sys,T_end_contract)
%LOCAL_PRODUCTION_REQUEST Copy of production_request in
% scripts/reporting/generate_ieee14_switch_report_figures.m. Every event
% time, gain, delay and solver setting is identical; only t_end is taken
% from the caller so the rerun matches the reference cache's horizon.
s = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
ev = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',145,'sg_on',145,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
opt = struct('t_end',T_end_contract, ...
    'dt',0.10,'verbose',false, ...
    'ibr_events',ev,'plot_results',false, ...
    'max_step_subdivisions',9, ...
    'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
end
