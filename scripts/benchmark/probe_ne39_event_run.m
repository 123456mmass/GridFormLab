function probe_ne39_event_run()
%PROBE_NE39_EVENT_RUN  Minimal NE39 fault/clear event run (fail-closed probe).
%   Drives stability.run_hybrid_case on the NE39 mixed case through the
%   ibr_events route with a bus fault that is cleared, to see whether the
%   generic event driver + automatic GFM switching operate on this case.
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
sc = stability.build_hybrid_scenario(s.case_data, s.resources, s.scenario_opt);

opt = struct();
opt.t_end = 0.5;
opt.verbose = false;
opt.stepper = 'adaptive';
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
opt.dt_max = 0.5; opt.dt_max_armed = 0.05; opt.reject_limit = 12;
opt.ibr_events = struct('enabled',true,'event_profile','fault_only', ...
    'fault_bus',16,'Zf',1i*0.1,'fault_on',0.10,'fault_clear',0.20, ...
    'automatic_gfm_switching',false, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
try
    r = stability.run_hybrid_case(sc, opt);
    fn = fieldnames(r);
    fprintf('RUN fields=%s\n', strjoin(fn', ','));
    for i = 1:numel(fn)
        v = r.(fn{i});
        if isnumeric(v) || islogical(v)
            fprintf('  %s: %s %s\n', fn{i}, class(v), mat2str(size(v)));
        elseif isstruct(v)
            fprintf('  %s: struct n=%d\n', fn{i}, numel(v));
        elseif iscell(v)
            fprintf('  %s: cell n=%d\n', fn{i}, numel(v));
        end
    end
    if isfield(r,'converged'), fprintf('CONVERGED=%d\n', r.converged); end
    if isfield(r,'failure_id'), fprintf('FAILURE_ID=%s\n', string(r.failure_id)); end
    if isfield(r,'failure_reason'), fprintf('FAILURE_REASON=%s\n', string(r.failure_reason)); end
    if isfield(r,'status_log') && isstruct(r.status_log) && ~isempty(r.status_log)
        sl = r.status_log; f = fieldnames(sl);
        fprintf('STATUS_LOG fields=%s n=%d\n', strjoin(f',','), numel(sl));
    end
    if isfield(r,'t') && ~isempty(r.t), fprintf('T end=%.4f n=%d\n', r.t(end), numel(r.t)); end
catch e
    fprintf('EVENT_RUN_ERROR %s :: %s\n', e.identifier, e.message);
    for s = 1:min(12, numel(e.stack))
        fprintf('  at %s line %d\n', e.stack(s).name, e.stack(s).line);
    end
    try, fprintf('EXTENDED:\n%s\n', getReport(e,'extended','hyperlinks','off')); catch, end
end
end
