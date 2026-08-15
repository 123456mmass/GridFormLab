function r = run_ieee14_eecon49_chronology(varargin)
%RUN_IEEE14_EECON49_CHRONOLOGY  Flagship IEEE 14-bus mixed SG/IBR study.
%
%   r = run_ieee14_eecon49_chronology()
%   r = run_ieee14_eecon49_chronology('t_end',250,'save',true)
%
% Runs the 250 s IEEE 14-bus chronology on the EECON49 case profile: one
% synchronous machine at bus 1 and four dual-mode converters at buses 2, 3, 6
% and 8, through
%
%     t =  20 s   SG trips, the network islands on converters alone
%     t =  50 s   all constant-impedance loads step up 20 %
%     t =  85 s   three-phase fault at bus 9, cleared after 150 ms
%     t = 110 s   line 6-13 trips
%     t = 145 s   topology restored and the SG reclose request is raised
%     t = 250 s   horizon
%
% Grid-forming/grid-following mode changes are decided at run time by the
% severity supervisor, authenticated against the precomputed small-signal
% selector table, and committed as atomic transactions. Every option below is an
% explicit argument to stability.run_hybrid_case, so the run is reproducible.
%
% Two opt-in behaviours are enabled here; both default to OFF elsewhere and both
% leave an omitted run byte-identical:
%
%   support_transition_certificate  forward-simulates the would-be-committed
%                                   state with the production kernel and refuses
%                                   fail-closed if the island would lose
%                                   synchronism (defect AGSI-2026-08-14-02)
%   handback_efd_timescale          walks the post-reclose field-voltage command
%                                   over the declared actuator response time
%                                   instead of the destination mode's decay time
%                                   (defect RECLOSE-2026-08-15-01)
%
% Expected outcome on this profile: reclose_status = 'SUCCESS' at t = 159.3436 s,
% the run reaching t = 250 s with f_COI = 60.000000 Hz, and the terminal
% dispatch reproducing the published EECON49 operating point.

p = inputParser;
p.addParameter('t_end',250);
p.addParameter('dt',0.05);
p.addParameter('save',false);
p.addParameter('output',fullfile('output','diagnostics','ieee14_eecon49_chronology.mat'));
p.parse(varargin{:});
a = p.Results;

pf_init_paths();

% Healthy pre-event power flow supplies the severity supervisor's voltage
% reference profile. The supervisor consumes J_V and J_f only.
sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);

scenario = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));

% Precompute and authenticate the configuration table once, before the run.
% Pass the FULL scenario struct: the selector resolves its dispatch from
% scenario.config.dispatch or scenario.scenario_opt.dispatch, so handing it
% scenario.scenario_opt directly would silently certify every SG-online row at
% zero IBR active power.
selector_table = stability.ibr_selector_table(scenario.case_data, ...
    scenario.resources,scenario,struct());

events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',145,'sg_on',145,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));

opt = struct( ...
    't_end',a.t_end,'dt',a.dt,'verbose',false,'plot_results',false, ...
    'ibr_events',events, ...
    'max_step_subdivisions',12,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).', ...
    'stepper','adaptive','reject_limit',20, ...
    'support_transition_certificate',true, ...
    'handback_efd_timescale','control', ...
    'selector_table',selector_table);

fprintf('running the %g s IEEE 14-bus EECON49 chronology ...\n',a.t_end);
tic; r = stability.run_hybrid_case(scenario,opt); wall = toc;

fprintf('\nconverged      %d\n',r.converged);
fprintf('horizon        %.6f s   (wall %.1f s)\n',r.t(end),wall);
if isfield(r,'failure_id') && ~isempty(r.failure_id)
    fprintf('failure_id     %s\n',char(string(r.failure_id)));
    fprintf('failure_reason %s\n',char(string(r.failure_reason)));
end
fprintf('reclose        %s at %s s\n',char(string(r.reclose_status)), ...
    num2str(r.actual_reclose_time));
fprintf('terminal f_COI %.6f Hz\n',r.coi_frequency_Hz(end));
fprintf('terminal |V|   %.4f .. %.4f pu\n', ...
    min(r.bus_voltage_magnitude(:,end)),max(r.bus_voltage_magnitude(:,end)));
fprintf('\n%-6s %-8s %-10s %-10s %-10s\n','dev','mode','|I| pu','P pu','Q pu');
for k = 1:numel(r.device_ids)
    fprintf('%-6s %-8s %-10.5f %-10.5f %-10.5f\n', ...
        char(string(r.device_ids{k})), ...
        char(string(r.device_modes_history{k,end})), ...
        r.device_current_magnitude(k,end), ...
        r.device_P_pu(k,end),r.device_Q_pu(k,end));
end

if a.save
    outdir = fileparts(a.output);
    if ~isempty(outdir) && ~isfolder(outdir), mkdir(outdir); end
    save(a.output,'r','wall','-v7.3');
    fprintf('\nsaved %s\n',a.output);
    fprintf('render the chronology figure with:\n');
    fprintf('  generate_readme_chronology_figure(''result'',''%s'')\n',a.output);
end
end
