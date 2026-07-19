function trace_stepnewton_origin_20260719()
%TRACE_STEPNEWTON_ORIGIN_20260719  Capture the FULL error stack / cause behind
%the stepNewton failure at Zf=0.1i, dt=0.01, to confirm whether the root throw
%is the RMS10 lowVoltagePowerInversion domain error (trial iterate) masked as
%stepNewton, or a genuine Newton non-convergence. Read-only.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'trace_stepnewton_origin_20260719.log'),'w');
c = onCleanup(@() fclose(fh));

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'ts';
opt.plot_results = false; opt.verbose = true;   % verbose to surface solver trace
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
try
    r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
    fprintf(fh,'returned (no throw). failure_id=%s\n%s\n', ...
        char(getf(r,'failure_id')), char(getf(r,'failure_reason')));
catch ME
    fprintf(fh,'THROWN identifier: %s\n', ME.identifier);
    fprintf(fh,'THROWN message: %s\n', ME.message);
    fprintf(fh,'--- stack (top 12) ---\n');
    for k = 1:min(12,numel(ME.stack))
        fprintf(fh,'  %s (line %d)\n', ME.stack(k).name, ME.stack(k).line);
    end
    for c = 1:numel(ME.cause)
        fprintf(fh,'--- cause %d: %s | %s\n', c, ME.cause{c}.identifier, ME.cause{c}.message);
    end
end
fprintf(fh,'DONE\n');
end
function v = getf(s,f), if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=''; end, end
