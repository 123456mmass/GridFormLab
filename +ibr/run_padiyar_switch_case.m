function result = run_padiyar_switch_case(case_data, opt)
%RUN_PADIYAR_SWITCH_CASE  solve_case runner for the Padiyar 1-SG + 3-GFL AGSI++
%   mode-switch study (schema padiyar_switch/1.0). Builds the system, runs the
%   SG trip + reclose scenario, saves the separate per-quantity figures, and
%   returns a launcher-style result. ASSUMED_DIAGNOSTIC; project code only.

if ~isstruct(case_data) || ~isfield(case_data,'padiyar_switch')
    error('ibr:run_padiyar_switch_case:badCase','case_data must contain padiyar_switch metadata.');
end
if nargin < 2, opt = struct(); end
d = case_data.padiyar_switch;

im = char(ov(opt,'padiyar_index_mode', d.index_mode));
tt = ov(opt,'padiyar_sg_trip_time',    d.sg_trip_time);
tr = ov(opt,'padiyar_sg_reclose_time', d.sg_reclose_time);
T  = ov(opt,'t_end', d.T);
dt = ov(opt,'dt',    d.dt);
plot_results = logical(ov(opt,'plot_results', true));

out = ibr.padiyar_switch_demo(index_mode=string(im), sg_trip_time=tt, ...
    sg_reclose_time=tr, T=T, dt=dt, visible=false, plot=plot_results);

result = struct();
result.converged = out.newton_all_converged;
result.ibr_analysis = lower(char(ov(opt,'ibr_analysis','full')));
result.classification = 'ASSUMED_DIAGNOSTIC_PADIYAR_1SG_3GFL_SWITCH';
result.schema_version = case_data.schema_version;
result.base_values = case_data.base_values;
result.scenario = struct('index_mode',im,'sg_trip_time',tt,'sg_reclose_time',tr,'T',T,'dt',dt);
result.tds = out;
result.switch_events = out.switch_events;
result.dev_modes = out.dev_mode;
result.dev_n_switch = out.dev_n_switch;
result.Vmin_end = out.Vmin(end);
if plot_results, result.figure_files = out.fig_paths; else, result.figure_files = {}; end
result.selector_log = struct('ready',true,'candidate_count',3, ...
    'source','PADIYAR_1SG_3GFL_AGSI_SWITCH');
result.metadata = struct('classification','ASSUMED_DIAGNOSTIC_PADIYAR_SWITCH', ...
    'device_state_count',5+3*6,'device_count',4,'events','SG_TRIP_AND_RECLOSE');
result.execution_summary = struct('pf_invocations',1,'sssa_invocations',0, ...
    'ts_invocations',1,'solver_iterations',0,'linearized_state_count',0, ...
    'eigenvalue_count',0,'ts_step_count',max(0,numel(out.tgrid)-1), ...
    'mode_switch_transactions',size(out.switch_events,1));

fprintf('\n---- PADIYAR 1-SG + 3-GFL AGSI++ SWITCH ----\n');
fprintf('SG @ bus%d (slack); IBRs @ buses %s\n', out.sg_bus, num2str(out.ibr_buses));
fprintf('Event: SG trip @%.2fs, reclose @%.2fs (%s, no dwell)\n', tt, tr, im);
fprintf('Converged=%d ; n_switch=[%d %d %d] ; final modes=[%s %s %s] ; Vend=%.3f\n', ...
    result.converged, out.dev_n_switch, out.dev_mode(1),out.dev_mode(2),out.dev_mode(3), out.Vmin(end));
end

function v = ov(s,name,fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v = s.(name); else, v = fallback; end
end
