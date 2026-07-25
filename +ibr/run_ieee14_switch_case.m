function result = run_ieee14_switch_case(case_data, opt)
%RUN_IEEE14_SWITCH_CASE  solve_case runner for the IEEE 14-bus 1-SG + 4-IBR
%   AGSI++ mode-switch study (schema ieee14_switch/1.0). Builds the system, runs
%   the SG trip + reclose scenario, saves the separate per-quantity figures, and
%   returns a launcher-style result. ASSUMED_DIAGNOSTIC; project code only.

if ~isstruct(case_data) || ~isfield(case_data,'ieee14_switch')
    error('ibr:run_ieee14_switch_case:badCase','case_data must contain ieee14_switch metadata.');
end
if nargin < 2, opt = struct(); end
d = case_data.ieee14_switch;

im = char(ov(opt,'ieee14_index_mode', d.index_mode));
tt = ov(opt,'ieee14_sg_trip_time',    d.sg_trip_time);
tr = ov(opt,'ieee14_sg_reclose_time', d.sg_reclose_time);
T  = ov(opt,'t_end', d.T);
dt = ov(opt,'dt',    d.dt);
plot_results = logical(ov(opt,'plot_results', true));

out = ibr.padiyar_switch_demo(system="ieee14", index_mode=string(im), ...
    sg_trip_time=tt, sg_reclose_time=tr, T=T, dt=dt, visible=false, plot=plot_results);

nib = numel(out.ibr_buses);
result = struct();
result.converged = out.newton_all_converged;
result.ibr_analysis = lower(char(ov(opt,'ibr_analysis','full')));
result.classification = 'ASSUMED_DIAGNOSTIC_IEEE14_1SG_4IBR_SWITCH';
result.schema_version = case_data.schema_version;
result.base_values = case_data.base_values;
result.scenario = struct('index_mode',im,'sg_trip_time',tt,'sg_reclose_time',tr,'T',T,'dt',dt);
result.tds = out;
result.switch_events = out.switch_events;
result.dev_modes = out.dev_mode;
result.dev_n_switch = out.dev_n_switch;
result.Vmin_end = out.Vmin(end);
result.sssa = out.sssa;
if plot_results, result.figure_files = out.fig_paths; else, result.figure_files = {}; end
result.selector_log = struct('ready',true,'candidate_count',nib, ...
    'source','IEEE14_1SG_4IBR_AGSI_SWITCH');
result.metadata = struct('classification','ASSUMED_DIAGNOSTIC_IEEE14_SWITCH', ...
    'device_state_count',size(out.sssa.A,1),'device_count',nib+1, ...
    'events','SG_TRIP_AND_RECLOSE');
result.execution_summary = struct('pf_invocations',1,'sssa_invocations',1, ...
    'ts_invocations',1,'solver_iterations',0,'linearized_state_count',size(out.sssa.A,1), ...
    'eigenvalue_count',numel(out.sssa.eig),'ts_step_count',max(0,numel(out.tgrid)-1), ...
    'mode_switch_transactions',size(out.switch_events,1));

fprintf('\n---- IEEE 14-bus 1-SG + 4-IBR AGSI++ SWITCH ----\n');
fprintf('SG @ bus%d (slack, manual/no-AVR); IBRs @ buses %s\n', out.sg_bus, num2str(out.ibr_buses));
fprintf('Event: SG trip @%.2fs, reclose @%.2fs (%s)\n', tt, tr, im);
fprintf('SSSA: maxRe=%+.4f, n_unstable=%d (%s)\n', max(real(out.sssa.eig)), out.sssa.n_unstable, ...
    ternary(out.sssa.n_unstable==0,'small-signal stable','UNSTABLE'));
fprintf('Converged=%d ; n_switch=[%s] ; final modes=[%s] ; Vend=%.3f\n', ...
    result.converged, strjoin(string(out.dev_n_switch(:).'),' '), ...
    strjoin(string(out.dev_mode(:).'),' '), out.Vmin(end));
end

function v = ov(s,name,fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v = s.(name); else, v = fallback; end
end

function r = ternary(c,a,b)
if c, r = a; else, r = b; end
end
