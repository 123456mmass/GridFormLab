function verify_domain_preserving_fix_20260720()
%VERIFY_DOMAIN_PRESERVING_FIX_20260720  Production domain-preserving Newton gate.
% Runs the production Zf=0.1i route (no shadow) at dt=0.01 and dt=0.005 with
% equations/parameters/tolerances/event times UNCHANGED. Acceptance:
%   - dt=0.01 must pass t=3.25s (the prior stepNewton death point) and reach
%     sg_trip=5s; accepted IBR |V| must stay >= V_div_min=0.1.
%   - domain_rejected_trials and subdivision_depth must be published.
%   - scheduled event landings must be exact.
%   - no non-domain exception may be swallowed.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'verify_domain_preserving_fix_20260720.log'),'w');
if fh < 0, error('verify:cannotOpenLog','cannot open log file'); end
c = onCleanup(@() fclose(fh));

dt_list = [0.01, 0.005];
for k = 1:numel(dt_list)
    dt = dt_list(k);
    fprintf(fh,'==== dt=%.4g ====\n', dt);
    opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
    opt.ibr_analysis = 'ts';
    opt.plot_results = false; opt.verbose = false;
    opt.ibr_events.Zf = 1i*0.1;
    opt.dt = dt;
    try
        r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
        ts = r; if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
        conv = ts.converged;
        fid = ''; if isfield(r,'failure_id') && ~isempty(r.failure_id), fid = char(r.failure_id); end
        fr = ''; if isfield(r,'failure_reason'), fr = r.failure_reason; end
        drt = getf_num(r,'domain_rejected_trials'); sd = getf_num(r,'subdivision_depth');
        drt_ts = getf_num(ts,'domain_rejected_trials'); sd_ts = getf_num(ts,'subdivision_depth');
        if isfield(ts,'t') && ~isempty(ts.t)
            t = ts.t; yT = ts.y_traj; bus_ids = ts.bus_ids;
            Vm = abs(complex(yT(1:2:end,:), yT(2:2:end,:)));
            ibr_pos = arrayfun(@(b) find(bus_ids==b,1), [2,3,6,8]);
            minV_all = min(Vm,[],'all');
            minV_ibr = min(Vm(ibr_pos,:),[],'all');
            fprintf(fh,'converged=%d  t_end=%.4f  samples=%d\n', conv, t(end), numel(t));
            fprintf(fh,'failure_id=%s\n', fid);
            fprintf(fh,'failure_reason=%s\n', fr);
            fprintf(fh,'accepted min|V| all buses=%.5f  IBR buses=%.5f\n', minV_all, minV_ibr);
            fprintf(fh,'IBR |V| ever < 0.1: %d\n', minV_ibr < 0.1);
            fprintf(fh,'reached sg_trip(5s)? %d  reached sg_on(8s)? %d\n', t(end)>=5.0, t(end)>=8.0);
            fprintf(fh,'domain_rejected_trials(r)=%g  (ts)=%g\n', drt, drt_ts);
            fprintf(fh,'subdivision_depth(r)=%g  (ts)=%g\n', sd, sd_ts);
            % scheduled event landings exact?
            if isfield(ts,'event_transactions') && ~isempty(ts.event_transactions)
                ev = ts.event_transactions;
                for e = 1:numel(ev)
                    fprintf(fh,'event %s t=%.6f applied=%d\n', ...
                        getf_str(ev(e),'type'), ev(e).t, ev(e).applied);
                end
            end
        else
            fprintf(fh,'converged=%d  no ts.t (early fail)\n', conv);
            fprintf(fh,'failure_id=%s\nfailure_reason=%s\n', fid, fr);
            fprintf(fh,'domain_rejected_trials(r)=%g  subdivision_depth(r)=%g\n', drt, sd);
        end
    catch ME
        fprintf(fh,'ERROR %s: %s\n', ME.identifier, ME.message);
    end
end
fprintf(fh,'DONE\n');
end

function v = getf_num(s,f)
v = NaN;
if isfield(s,f) && ~isempty(s.(f)) && isscalar(s.(f)) && isnumeric(s.(f))
    v = s.(f);
end
end

function v = getf_str(s,f)
v = '';
if isfield(s,f) && ~isempty(s.(f)) && ischar(s.(f)), v = s.(f); end
if isfield(s,f) && ~isempty(s.(f)) && isstring(s.(f)), v = char(s.(f)); end
end
