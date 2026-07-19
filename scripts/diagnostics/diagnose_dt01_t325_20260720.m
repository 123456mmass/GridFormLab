function diagnose_dt01_t325_20260720()
%DIAGNOSE_DT01_T325_20260720  Why does dt=0.01 still die at t=3.25s after the
%domain-preserving fix? Capture domain_rejected_trials, subdivision_depth,
%the failure_id/reason, and the residual trajectory around t=3.25s.
%Equations/parameters/tolerances/event times UNCHANGED.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'diagnose_dt01_t325_20260720.log'),'w');
if fh < 0, error('diag:cannotOpenLog','cannot open log file'); end
c = onCleanup(@() fclose(fh));

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'ts';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);

ts = r; if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
fprintf(fh,'converged=%d\n', ts.converged);
fprintf(fh,'failure_id=%s\n', getf_str(r,'failure_id'));
fprintf(fh,'failure_reason=%s\n', getf_str(r,'failure_reason'));
fprintf(fh,'domain_rejected_trials(r)=%g  (ts)=%g\n', ...
    getf_num(r,'domain_rejected_trials'), getf_num(ts,'domain_rejected_trials'));
fprintf(fh,'subdivision_depth(r)=%g  (ts)=%g\n', ...
    getf_num(r,'subdivision_depth'), getf_num(ts,'subdivision_depth'));

if isfield(ts,'t') && ~isempty(ts.t)
    t = ts.t;
    fprintf(fh,'t_end=%.6f  samples=%d\n', t(end), numel(t));
    % residual per step around t=3.25
    if isfield(ts,'residual_per_step') && ~isempty(ts.residual_per_step)
        res = ts.residual_per_step;
        fprintf(fh,'max residual all=%.6e\n', max(abs(res)));
        % last 10 samples
        n = min(10, numel(t));
        fprintf(fh,'last %d samples:\n', n);
        for j = numel(t)-n+1:numel(t)
            fprintf(fh,'  t=%.6f  resid=%.6e\n', t(j), res(j));
        end
    end
    % voltage trajectory around fault
    if isfield(ts,'y_traj') && isfield(ts,'bus_ids')
        yT = ts.y_traj; bus_ids = ts.bus_ids;
        Vm = abs(complex(yT(1:2:end,:), yT(2:2:end,:)));
        ibr_pos = arrayfun(@(b) find(bus_ids==b,1), [2,3,6,8]);
        fprintf(fh,'min|V| all buses=%.5f  IBR buses=%.5f\n', ...
            min(Vm,[],'all'), min(Vm(ibr_pos,:),[],'all'));
        % voltage at last few samples
        n = min(10, numel(t));
        fprintf(fh,'last %d sample voltages (IBR buses 2,3,6,8):\n', n);
        for j = numel(t)-n+1:numel(t)
            fprintf(fh,'  t=%.6f  V=[%.4f %.4f %.4f %.4f]\n', ...
                t(j), Vm(ibr_pos(1),j), Vm(ibr_pos(2),j), ...
                Vm(ibr_pos(3),j), Vm(ibr_pos(4),j));
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

function v = getf_str(s,f)
v = '';
if isfield(s,f) && ~isempty(s.(f)) && ischar(s.(f)), v = s.(f); end
if isfield(s,f) && ~isempty(s.(f)) && isstring(s.(f)), v = char(s.(f)); end
end
