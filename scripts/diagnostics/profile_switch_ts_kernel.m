function out = profile_switch_ts_kernel(opts)
%PROFILE_SWITCH_TS_KERNEL  Measure where the switched-TS run spends wall clock.
%   OUT = profile_switch_ts_kernel() runs two short arms through the SAME
%   production route as the report evidence (stability.run_hybrid_case with the
%   IEEE14 1SG+4IBR chronology contract), records wall clock without the
%   profiler, then records a profiler attribution pass, and stores a baseline
%   result for scripts/diagnostics/compare_ts_equivalence.m.
%
%   WHY TWO ARMS: the production request cannot simply be truncated in time.
%   stability.ibr_event_schedule requires fault_clear <= t_end and
%   sg_trip < sg_on <= t_end, and stability.run_hybrid_case passes ONE t_end to
%   both the schedule and the kernel, so a short prefix of the 200/250-s
%   chronology is not constructible. The two arms therefore are:
%
%     composite   ibr_events disabled, t_end = 2.0 s. run_hybrid_case routes
%                 this to stability.ts_simulate_composite (run_hybrid_case.m:199),
%                 NOT to the event supervisor. It still exercises the shared
%                 cost centres — ts_step_composite, composite_newton,
%                 forward_fd, composite_dae and every device closure — so it is
%                 the fast bit-identical sentinel for that work. It does NOT
%                 cover the supervisor loop or the work-hint logic.
%     compressed  every event TYPE of the production chronology, with the
%                 times compressed into 8 s, so stability.ts_simulate_ibr_hybrid
%                 and its transactions/work hint are exercised. Controller
%                 constants (gamma_on/gamma_off/T_d_on/T_d_off) are NOT scaled,
%                 so the late release branches may not fire; those are covered
%                 by the full-horizon rerun, not here.
%     compressed_fast  the same chronology inside 3.5 s, for the develop/verify
%                 loop. Use `compressed` for the per-stage confirmation.
%
%   Measured baseline (tag s0a, before any optimisation):
%     composite   3.12 s wall, 21 samples, subdivision depth 0
%     compressed  827.43 s wall, 88 samples, 5,692 Newton iterations,
%                 subdivision depth 4  (~65 iterations per logical step, i.e.
%                 the same expensive regime the 200-s production log shows)
%
%   The compressed arm is NOT the production trajectory. It is a before/after
%   instrument evaluated on identical inputs, which is what equivalence work
%   needs. The authoritative check remains a full-horizon rerun compared with
%   the stored production cache.
%
%   Source of the request fields: scripts/reporting/
%   generate_ieee14_switch_report_figures.m production_request (lines 118-139).
%   Reproduce: pf_init_paths; profile_switch_ts_kernel();

arguments
    opts.arms (1,:) string = ["composite","compressed"]
    opts.run_profiler (1,1) logical = true
    opts.tag (1,1) string = ""
    opts.outdir (1,1) string = fullfile('output','diagnostics')
    % Extra request fields merged into the arm's option struct after
    % local_request builds it. Used to measure one NUMERICAL_METHOD knob at a
    % time (e.g. fd_grouping, fd_structure_check) on the
    % SAME arm, so a before/after comparison keeps every other input fixed.
    opts.extra_opt (1,1) struct = struct()
end

pf_init_paths();
if ~exist(opts.outdir,'dir'), mkdir(opts.outdir); end
tag = char(opts.tag);
if isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end %#ok<TNOW1,DATST>

fprintf('TS_PROFILE_START tag=%s arms=%s\n',tag,strjoin(cellstr(opts.arms),','));
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);

out = struct('tag',tag,'arms',local_empty_arm());
for k = 1:numel(opts.arms)
    arm = char(opts.arms(k));
    out.arms(end+1) = local_run_arm(arm,sys,tag,char(opts.outdir), ...
        opts.run_profiler,opts.extra_opt);
end
local_print_summary(out);
end

% =========================================================================
function a = local_empty_arm()
a = repmat(struct('arm','','wall_s',NaN,'wall_profiled_s',NaN, ...
    'converged',false,'t_end_reached',NaN,'n_samples',0, ...
    'total_iterations',NaN,'max_attempts',NaN,'max_depth',NaN, ...
    'baseline_file','','profile_file','','top',{{}}),0,1);
end

% =========================================================================
function [scenario,opt] = local_request(arm,sys)
%LOCAL_REQUEST  Build one arm's scenario/opt pair.
scenario = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));
opt = struct('dt',0.10,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9, ...
    'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
switch arm
case 'composite'
    opt.t_end = 2.0;
    opt.ibr_events = struct('enabled',false);
case 'compressed'
    % Same event TYPES and the same ordering constraints as the production
    % chronology (sg_trip < ... < fault_on < fault_clear < line_trip <
    % restore_time = sg_on <= t_end), compressed in time only.
    opt.t_end = 8.0;
    opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
        'sg_trip',2,'load_step',3,'load_step_factor',0.20, ...
        'fault_on',4,'fault_clear',4.15,'fault_bus',9,'Zf',0.01+0.01i, ...
        'line_trip',5,'line_from_bus',6,'line_to_bus',13, ...
        'restore_time',6,'sg_on',6,'coordinated_handback',false, ...
        'automatic_gfm_switching',true, ...
        'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
case 'compressed_fast'
    % Same event types and ordering as `compressed`, compressed harder so a
    % develop/verify cycle costs minutes instead of a quarter hour. Measured
    % cost of `compressed` at tag s0a was 827 s for 8 s of simulated time
    % (5,692 Newton iterations over 88 logical steps, max subdivision depth
    % 4), which is too slow to iterate against.
    opt.t_end = 3.5;
    opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
        'sg_trip',1,'load_step',1.5,'load_step_factor',0.20, ...
        'fault_on',2,'fault_clear',2.15,'fault_bus',9,'Zf',0.01+0.01i, ...
        'line_trip',2.5,'line_from_bus',6,'line_to_bus',13, ...
        'restore_time',3,'sg_on',3,'coordinated_handback',false, ...
        'automatic_gfm_switching',true, ...
        'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
otherwise
    error('profile_switch_ts_kernel:badArm','Unknown arm "%s".',arm);
end
end

% =========================================================================
function info = local_run_arm(arm,sys,tag,outdir,run_profiler,extra_opt)
[scenario,opt] = local_request(arm,sys);
extra_names = fieldnames(extra_opt);
for e = 1:numel(extra_names)
    opt.(extra_names{e}) = extra_opt.(extra_names{e});
end

% --- pass 1: honest wall clock, no profiler instrumentation ---------------
fprintf('TS_PROFILE_ARM %s: timing pass (t_end=%g, dt=%g)\n', ...
    arm,opt.t_end,opt.dt);
t0 = tic;
r = stability.run_hybrid_case(scenario,opt);
wall = toc(t0);

baseline_file = fullfile(outdir,sprintf('ts_equiv_baseline_%s_%s.mat',arm,tag));
% wall is stored with the result so a lost console log does not lose the
% before/after timing evidence.
save(baseline_file,'r','scenario','opt','wall','-v7.3');

info = struct('arm',arm,'wall_s',wall,'wall_profiled_s',NaN, ...
    'converged',logical(r.converged), ...
    't_end_reached',r.t(end),'n_samples',numel(r.t), ...
    'total_iterations',local_field_sum(r,'iter_per_step'), ...
    'max_attempts',local_field_max(r,'step_attempts'), ...
    'max_depth',local_field_max(r,'subdivision_depth'), ...
    'baseline_file',baseline_file,'profile_file','','top',{{}});

% --- pass 2: profiler attribution ----------------------------------------
if run_profiler
    fprintf('TS_PROFILE_ARM %s: profiler pass\n',arm);
    profile('off'); profile('clear');
    % No '-history': this run makes millions of function calls and the call
    % history would exhaust memory. FunctionTable totals are what we need.
    profile('on');
    t1 = tic;
    stability.run_hybrid_case(scenario,opt);
    info.wall_profiled_s = toc(t1);
    profile('off');
    p = profile('info');
    info.top = local_top_functions(p,20);
    info.profile_file = fullfile(outdir, ...
        sprintf('ts_profile_%s_%s.mat',arm,tag));
    save(info.profile_file,'p','-v7.3');
    profile('clear');
end
end

% =========================================================================
function v = local_field_sum(r,name)
%LOCAL_FIELD_SUM  Sum a published counter, tolerating absent fields.
%   The legacy no-event route (run_hybrid_case.m:199) publishes fewer fields
%   than the event supervisor, so every metric read here must be optional.
v = NaN;
if isfield(r,name) && isnumeric(r.(name)) && ~isempty(r.(name))
    x = r.(name);
    v = sum(x(isfinite(x)));
end
end

function v = local_field_max(r,name)
v = NaN;
if isfield(r,name) && isnumeric(r.(name)) && ~isempty(r.(name))
    x = r.(name);
    x = x(isfinite(x));
    if ~isempty(x), v = max(x); end
end
end

% =========================================================================
function rows = local_top_functions(p,n)
%LOCAL_TOP_FUNCTIONS  Rank profiler entries by total time.
ft = p.FunctionTable;
if isempty(ft), rows = {}; return; end
[~,idx] = sort([ft.TotalTime],'descend');
n = min(n,numel(idx));
rows = cell(n,4);
for k = 1:n
    e = ft(idx(k));
    rows{k,1} = e.FunctionName;
    rows{k,2} = e.TotalTime;
    rows{k,3} = e.NumCalls;
    rows{k,4} = e.TotalTime/max(1,e.NumCalls);
end
end

% =========================================================================
function local_print_summary(out)
fprintf('\nTS_PROFILE_SUMMARY tag=%s\n',out.tag);
fprintf('%-12s %10s %10s %6s %9s %8s %10s %9s %6s\n','arm','wall_s', ...
    'prof_s','conv','t_end','samples','iters','attempts','depth');
for k = 1:numel(out.arms)
    a = out.arms(k);
    fprintf('%-12s %10.2f %10.2f %6d %9.3f %8d %10.0f %9.0f %6.0f\n', ...
        a.arm,a.wall_s,a.wall_profiled_s,a.converged,a.t_end_reached, ...
        a.n_samples,a.total_iterations,a.max_attempts,a.max_depth);
end
for k = 1:numel(out.arms)
    a = out.arms(k);
    if isempty(a.top), continue; end
    fprintf('\n-- %s: top functions by total time --\n',a.arm);
    fprintf('%-52s %10s %12s %12s\n','function','total_s','calls','s_per_call');
    for j = 1:size(a.top,1)
        fprintf('%-52s %10.3f %12d %12.3g\n',a.top{j,1},a.top{j,2}, ...
            a.top{j,3},a.top{j,4});
    end
end
fprintf('\nTS_PROFILE_DONE\n');
end
