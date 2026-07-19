function analyze_dt005_rejects_20260720()
%ANALYZE_DT005_REJECTS_20260720  Distribution of the 197 domain-rejected
%trials in the dt=0.005 passing run. Confirms the rejects are concentrated in
%the fault window (not scattered) and that accepted |V| stays >= V_div_min.
%Read-only diagnostic.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'analyze_dt005_rejects_20260720.log'),'w');
if fh < 0, error('analyze:cannotOpenLog','cannot open log file'); end
c = onCleanup(@() fclose(fh));

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'ts';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.005;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
ts = r; if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
fprintf(fh,'dt=0.005: converged=%d t_end=%.4f samples=%d\n', ...
    ts.converged, ts.t(end), numel(ts.t));
fprintf(fh,'domain_rejected_trials=%g subdivision_depth=%g\n', ...
    getf_num(r,'domain_rejected_trials'), getf_num(r,'subdivision_depth'));

if isfield(ts,'t') && isfield(ts,'y_traj') && isfield(ts,'bus_ids')
    t = ts.t;
    yT = ts.y_traj; bus_ids = ts.bus_ids;
    Vm = abs(complex(yT(1:2:end,:), yT(2:2:end,:)));
    ibr_pos = arrayfun(@(b) find(bus_ids==b,1), [2,3,6,8]);
    fprintf(fh,'\nmin|V| all buses=%.5f  IBR buses=%.5f\n', ...
        min(Vm,[],'all'), min(Vm(ibr_pos,:),[],'all'));
    fprintf(fh,'IBR |V| ever < 0.1: %d\n', min(Vm(ibr_pos,:),[],'all') < 0.1);
    % voltage around the fault window (3.0-3.1s) and after
    fprintf(fh,'\n== |V| at IBR buses around fault window ==\n');
    fprintf(fh,'%-10s %-8s %-8s %-8s %-8s\n','t','V2','V3','V6','V8');
    for j = 1:numel(t)
        if t(j) >= 2.95 && t(j) <= 3.3
            fprintf(fh,'%-10.4f %-8.4f %-8.4f %-8.4f %-8.4f\n', ...
                t(j), Vm(ibr_pos(1),j), Vm(ibr_pos(2),j), ...
                Vm(ibr_pos(3),j), Vm(ibr_pos(4),j));
        end
    end
    % residual per step around fault window
    if isfield(ts,'residual_per_step')
        res = ts.residual_per_step;
        fprintf(fh,'\n== residual per step around fault window ==\n');
        for j = 1:numel(t)
            if t(j) >= 2.95 && t(j) <= 3.3
                fprintf(fh,'t=%.4f resid=%.6e\n', t(j), res(j));
            end
        end
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
