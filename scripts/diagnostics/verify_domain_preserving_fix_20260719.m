function verify_domain_preserving_fix_20260719()
%VERIFY_DOMAIN_PRESERVING_FIX_20260719  Run the production Zf=0.1i route with a
%SHADOW ts_step_composite that converts RMS10 domain throws (trial-iterate
%lowVoltagePowerInversion) into step rejections so advance_with_subdivision
%bisects instead of propagating stepNewton. Equations/parameters/tolerances/
%event times UNCHANGED. If the run then passes the fault window with accepted
%IBR |V| always >= V_div_min=0.1, the globalization-defect diagnosis is
%confirmed and the production fix (catch domain error in advance_with_subdivision)
%is justified.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'verify_domain_preserving_fix_20260719.log'),'w');
c = onCleanup(@() fclose(fh));

shadow = 'C:\Users\qwert\.claude\jobs\f1e836de\tmp\shadow';
addpath(shadow,'-begin'); rehash;
which stability.ts_step_composite
fprintf(fh,'shadow ts_step_composite: %s\n', which('stability.ts_step_composite'));

global SHADOW_DOMAIN_THROWS SHADOW_STEP_CALLS
SHADOW_DOMAIN_THROWS = 0; SHADOW_STEP_CALLS = 0;

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'full';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);

fprintf(fh,'\n== RESULT ==\n');
fprintf(fh,'converged=%d  failure_id=%s\n', r.converged, char(getf(r,'failure_id')));
fprintf(fh,'failure_reason=%s\n', char(getf(r,'failure_reason')));
fprintf(fh,'ts_step calls=%d  domain throws caught=%d\n', SHADOW_STEP_CALLS, SHADOW_DOMAIN_THROWS);

if isfield(r,'ts') && ~isempty(r.ts)
    ts = r.ts;
    t = ts.t; yT = ts.y_traj; bus_ids = ts.bus_ids;
    Vm = abs(complex(yT(1:2:end,:), yT(2:2:end,:)));
    ibr_pos = arrayfun(@(b) find(bus_ids==b,1), [2,3,6,8]);
    fprintf(fh,'last t=%.4f  accepted samples=%d\n', t(end), numel(t));
    fprintf(fh,'accepted min|V| all buses: %.5f\n', min(Vm,[],'all'));
    fprintf(fh,'accepted min|V| IBR buses: %.5f\n', min(Vm(ibr_pos,:),[],'all'));
    fprintf(fh,'accepted IBR |V| ever < 0.1: %d\n', min(Vm(ibr_pos,:),[],'all') < 0.1);
    % Did it reach sg_trip (5s) and beyond?
    fprintf(fh,'reached sg_trip(5s)? %d   reached sg_on(8s)? %d\n', t(end)>=5.0, t(end)>=8.0);
end
fprintf(fh,'DONE\n');
end

function v = getf(s,f), if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=''; end, end
