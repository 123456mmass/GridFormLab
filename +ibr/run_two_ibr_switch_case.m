function result = run_two_ibr_switch_case(case_data, opt)
%RUN_TWO_IBR_SWITCH_CASE  solve_case runner for the two-IBR AGSI GFL<->GFM
%   mode-switch study (schema two_ibr_switch/1.0).
%
%   RESULT = ibr.run_two_ibr_switch_case(CASE_DATA, OPT) reads the scenario
%   defaults from CASE_DATA.two_ibr_switch, applies any OPT overrides (option
%   names are the scenario fields prefixed by 'two_ibr_', plus t_end -> T and
%   dt), runs the project-owned two-device driver via ibr.two_ibr_switch_demo,
%   and returns a launcher-style result struct.
%
%   This is an ASSUMED_DIAGNOSTIC study runner (not a production TS path); it
%   uses only project code (ibr.SwitchableIbr6 / ibr.two_ibr_infbus_tds /
%   ibr.solve_pcc_infbus_equilibrium) and no external solver.

if ~isstruct(case_data) || ~isfield(case_data,'two_ibr_switch')
    error('ibr:run_two_ibr_switch_case:badCase', ...
        'case_data must contain two_ibr_switch metadata.');
end
if nargin < 2, opt = struct(); end
d = case_data.two_ibr_switch;

% Resolve scenario parameters (opt override 'two_ibr_<field>' -> default).
P_ref        = ov(opt,'two_ibr_P_ref',        d.P_ref);
Q_ref        = ov(opt,'two_ibr_Q_ref',        d.Q_ref);
V_inf        = ov(opt,'two_ibr_V_inf',        d.V_inf);
Z_line       = ov(opt,'two_ibr_Z_line',       d.Z_line);
AGSI_up      = ov(opt,'two_ibr_AGSI_up',      d.AGSI_up);
AGSI_down    = ov(opt,'two_ibr_AGSI_down',    d.AGSI_down);
event_time   = ov(opt,'two_ibr_event_time',   d.event_time);
recover_time = ov(opt,'two_ibr_recover_time', d.recover_time);
Zline_factor = ov(opt,'two_ibr_Zline_factor', d.Zline_factor);
step_dphase  = ov(opt,'two_ibr_step_dphase_deg', d.step_dphase_deg);
step_dV      = ov(opt,'two_ibr_step_dV',      d.step_dV);
step_ramp    = ov(opt,'two_ibr_step_ramp',    d.step_ramp);
T            = ov(opt,'t_end',                d.T);
dt           = ov(opt,'dt',                   d.dt);
plot_results = logical(ov(opt,'plot_results', true));

% Run the project-owned two-device driver (build + integrate + optional plot).
out = ibr.two_ibr_switch_demo( ...
    P_ref=P_ref, Q_ref=Q_ref, V_inf=V_inf, Z_line=Z_line, ...
    AGSI_up=AGSI_up, AGSI_down=AGSI_down, ...
    event_time=event_time, recover_time=recover_time, Zline_factor=Zline_factor, ...
    step_dphase_deg=step_dphase, step_dV=step_dV, step_ramp=step_ramp, ...
    T=T, dt=dt, save_fig=plot_results);

% --- Assemble launcher-style result ----------------------------------------
result = struct();
result.converged = out.newton_all_converged;
result.ibr_analysis = lower(char(ov(opt,'ibr_analysis','full')));
result.classification = 'ASSUMED_DIAGNOSTIC_TWO_IBR_AGSI_SWITCH';
result.schema_version = case_data.schema_version;
result.base_values = case_data.base_values;
result.scenario = struct('P_ref',P_ref,'Q_ref',Q_ref,'V_inf',V_inf,'Z_line',Z_line, ...
    'AGSI_up',AGSI_up,'AGSI_down',AGSI_down,'event_time',event_time, ...
    'recover_time',recover_time,'Zline_factor',Zline_factor, ...
    'step_dphase_deg',step_dphase,'step_dV',step_dV,'step_ramp',step_ramp,'T',T,'dt',dt);
result.tds = out;
result.switch_events = out.switch_events;
result.dev1 = struct('n_switch',out.dev1_n_switch,'final_mode',char(out.dev1_mode));
result.dev2 = struct('n_switch',out.dev2_n_switch,'final_mode',char(out.dev2_mode));
result.peak_agsi = max(out.index1);
if isfield(out,'fig_path') && plot_results
    result.figure_files = {out.fig_path};
else
    result.figure_files = {};
end
result.selector_log = struct('ready',true,'candidate_count',2, ...
    'source','TWO_IBR_COMMON_PCC_AGSI_SWITCH');
result.metadata = struct( ...
    'classification','ASSUMED_DIAGNOSTIC_TWO_IBR_SWITCH', ...
    'device_state_count',12, ...   % two 6-state IBRs (active)
    'device_count',2, 'events','SELF_CONTAINED_WEAK_GRID_SCENARIO');
result.execution_summary = struct( ...
    'pf_invocations',1, 'sssa_invocations',0, 'ts_invocations',1, ...
    'solver_iterations',0, 'linearized_state_count',0, 'eigenvalue_count',0, ...
    'ts_step_count',max(0,numel(out.tgrid)-1), ...
    'mode_switch_transactions',size(out.switch_events,1));

print_summary(result, out);
end

% =========================================================================
function v = ov(s, name, fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    v = s.(name);
else
    v = fallback;
end
end

% =========================================================================
function print_summary(r, out)
sc = r.scenario;
fprintf('\n---------------- TWO-IBR AGSI GFL<->GFM SWITCH ----------------\n');
fprintf('Topology           : IBR1 + IBR2 at a common PCC, one line Z=%.3g%+.3gj to infinite bus\n', ...
    real(sc.Z_line), imag(sc.Z_line));
fprintf('Per-IBR references : P=%.3f pu, Q=%.3f pu ; V_inf=%.3f pu\n', sc.P_ref, sc.Q_ref, sc.V_inf);
fprintf('Switching equation : AGSI vs Gamma_on=%.2f / Gamma_off=%.2f (EECON49-P4 guideline)\n', ...
    sc.AGSI_up, sc.AGSI_down);
fprintf('Weak-grid event    : t=%.2f-%.2f s, Z_line x%.1f, dphase=%g deg, dV=%g\n', ...
    sc.event_time, sc.recover_time, sc.Zline_factor, sc.step_dphase_deg, sc.step_dV);
fprintf('Horizon / step     : T=%.3g s, dt=%.4g s\n', sc.T, sc.dt);
fprintf('IBR1               : n_switch=%d, final mode=%s\n', r.dev1.n_switch, r.dev1.final_mode);
fprintf('IBR2               : n_switch=%d, final mode=%s\n', r.dev2.n_switch, r.dev2.final_mode);
if ~isempty(out.switch_events)
    fprintf('Switch events [t, dev, AGSI, ->GFM?]:\n');
    ev = out.switch_events;
    for k = 1:size(ev,1)
        if size(ev,2) >= 4 && ev(k,4) == 1, tgt = 'GFM'; else, tgt = 'gfl'; end
        fprintf('   t=%.3f s  IBR%d  AGSI=%.3f  -> %s\n', ev(k,1), ev(k,2), ev(k,3), tgt);
    end
end
fprintf('Newton converged   : %d (all steps)\n', r.converged);
if ~isempty(r.figure_files)
    fprintf('Figure             : %s\n', r.figure_files{1});
end
end
