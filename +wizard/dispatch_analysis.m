function result = dispatch_analysis(req)
%DISPATCH_ANALYSIS  Single shared dispatcher: validated request -> launcher.
%   result = wizard.dispatch_analysis(req) runs the production launcher for
%   the analysis specified in the validated request req. This is the ONE
%   dispatcher used by BOTH the wizard UI and the programmatic path (G4,
%   correction: "Wizard must call the same pure dispatcher as programmatic
%   path"). No duplicate dispatch exists anywhere.
%
%   dispatch_analysis calls the EXISTING production launchers verbatim:
%     pf   -> pfsolver.pf_resolve_method + pfsolver.pf_method_strategy(...).solve
%     sssa -> stability.multicase_sssa
%     ts   -> stability.ts_simulate
%     ibr  -> cases.scenario_ieee14_1sg_4ibr -> stability.ibr_configure_scenario
%             -> stability.run_hybrid_case
%
%   It does NOT introduce new solvers, new equations, or new event semantics.
%   events_policy='event_free' reaches the production runtime as an ACTUALLY
%   empty schedule (correction #6): for IBR, ibr_events.enabled=false is passed
%   through so run_hybrid_case produces the slim empty-schedule result; for TS,
%   the events struct is left empty so ts_simulate runs event-free.
%
%   The result schema, launcher sub-struct, execution_summary, and failure
%   IDs are produced by the production launchers and are NOT mutated here.
%   An additive launcher annotation (analysis/case_id/case_label/log_file)
%   is attached to mirror solve_case.m's existing result.launcher contract.
%
%   See also: wizard.BUILD_REQUEST, wizard.VALIDATE_REQUEST, wizard.ADAPT_RESULT.

req = wizard.validate_request(req);
analysis = req.analysis;
case_id = req.case_id;
opt = req.options;

% Locate the case entry (lazy; no solved-state load).
entries = wizard.discover_cases(analysis);
idx = find(strcmp(case_id, {entries.id}), 1);
if isempty(idx)
    error('wizard:dispatch_analysis:unknownCase', ...
        'Case %s not supported for %s.', case_id, analysis);
end
entry = entries(idx);
case_data = entry.loader();

% Attach the event spec to options for the TS/IBR launchers that consume it.
opt = attach_events(opt, req, analysis);
if strcmp(analysis,'ibr') && isfield(case_data,'smib_verification')
    opt = sanitize_smib_options(opt);
end

root = pf_init_paths();
logdir = fullfile(root, 'output', 'logs');
if ~exist(logdir, 'dir'), mkdir(logdir); end
stamp = datestr(now, 'yyyymmdd_HHMMSS');
logfile = fullfile(logdir, sprintf('%s_%s_%s.log', stamp, analysis, case_id));
diary(logfile);
diary_cleanup = onCleanup(@() diary('off')); %#ok<NASGU>

print_launcher_header(analysis, entry.label, logfile, case_data);
print_run_options(opt);

switch analysis
    case 'pf'
        [pf_method_name, pf_selection_source] = pfsolver.pf_resolve_method(opt);
        pf_strat = pfsolver.pf_method_strategy(pf_method_name);
        result = pf_strat.solve(case_data, opt);
        result = enrich_pf_metadata(result, pf_method_name, ...
            pf_selection_source, pf_strat);
        print_pf_checks(result, opt);
        print_resource_injections(case_data, result, opt, false);
    case 'sssa'
        result = stability.multicase_sssa(case_data, opt);
        result = annotate_sssa_result(result, opt);
        print_sssa_checks(result);
    case 'ts'
        result = stability.ts_simulate(case_data, opt);
        if ~isfield(opt, 'plot_results') || opt.plot_results
            [fig, png] = plot_ts_result(result, entry.label, root, case_id);
            result.figure = fig; result.figure_file = png;
        end
        print_ts_checks(result);
    case 'ibr'
        if isfield(case_data,'smib_verification')
            result = ibr.run_smib_verification_case(case_data,opt);
        else
            result = run_ibr_analysis(case_data, opt, entry.label, root, case_id);
        end
    otherwise
        error('wizard:dispatch_analysis:unknownAnalysis', ...
            'Unknown analysis ID %s.', analysis);
end

result = annotate_launcher_execution(analysis, result);
if ~strcmp(analysis, 'ibr')
    print_launcher_execution(result.execution_summary);
end
result.launcher = struct('analysis', analysis, 'case_id', case_id, ...
    'case_label', entry.label, 'log_file', logfile);

run_ok = ~isfield(result, 'converged') || logical(result.converged);
if run_ok
    fprintf('\nSTATUS: COMPLETE\n');
else
    fprintf('\nSTATUS: FAILED CLOSED\n');
end
fprintf('Saved log: %s\n', logfile);
diary('off');

% UI explanation path is handled by the wizard controller; do not block here.
% (solve_case.m opens a modal msgbox only in interactive mode; the wizard
%  shows results in-page instead.)
end

function opt = sanitize_smib_options(opt)
% Remove IEEE14 multi-device controls from the one-converter SMIB contract.
irrelevant={'ibr_profile','pf_verbose','initial_gfm_count','initial_gfl_count', ...
    'initial_gfm_indices','initial_reference_resource_index', ...
    'automatic_gfm_switching'};
for k=1:numel(irrelevant)
    if isfield(opt,irrelevant{k}), opt=rmfield(opt,irrelevant{k}); end
end
end

% =========================================================================
function opt = attach_events(opt, req, analysis)
% Pass the event spec through to the launcher's option ABI. For PF/SSSA,
% events are NOT_APPLICABLE and nothing is attached. For TS, the events
% struct flows into the ts_simulate option contract. For IBR, the nested
% ibr_events struct flows into run_hybrid_case.
registry = wizard.analysis_registry();
aidx = find(strcmp(analysis, {registry.id}), 1);
if ~registry(aidx).events_applicable, return; end
ev = req.events;
switch analysis
    case 'ts'
        if ~isempty(ev) && isfield(ev, 'enabled') && logical(ev.enabled)
            % Map the wizard event struct onto the TS option fields consumed
            % by ts_simulate (fault_bus, t_fault, t_clear, Zf). The wizard
            % event struct uses ibr-style names; the TS launcher uses
            % t_fault/t_clear. This mapping is a pure option translation,
            % not a new event semantic.
            opt.fault_bus = ev.fault_bus;
            opt.t_fault = ev.fault_on;
            opt.t_clear = ev.fault_clear;
            opt.Zf = ev.Zf;
            opt.fault_enabled = true;
        else
            % Canonical SG time-domain simulator exposes an explicit switch;
            % defaults contain fault times, so merely omitting fields would
            % still create a hidden fault.
            opt.fault_enabled = false;
        end
    case 'ibr'
        if ~isempty(ev)
            opt.ibr_events = ev;
        else
            % event_free for IBR: an explicit disabled struct reaches the
            % runtime as an empty schedule (correction #6).
            opt.ibr_events = struct('enabled', false);
        end
end
end

function result = enrich_pf_metadata(result, pf_method_name, pf_selection_source, pf_strat)
if ~isfield(result, 'metadata'), result.metadata = struct(); end
if ~isfield(result.metadata, 'method_executed')
    result.metadata.method_requested = pf_method_name;
    result.metadata.method_executed = pf_method_name;
    result.metadata.dispatch_requested = pf_method_name;
    result.metadata.method_source = pf_strat.method_source;
    result.metadata.selection_source = pf_selection_source;
    result.metadata.capability = pf_strat.capability;
    result.metadata.fallback_used = false;
    if isfield(result, 'max_mismatch')
        result.metadata.full_ac_mismatch = result.max_mismatch;
    end
else
    if ~isfield(result.metadata, 'dispatch_requested')
        result.metadata.dispatch_requested = pf_method_name;
    end
    if ~isfield(result.metadata, 'selection_source')
        result.metadata.selection_source = pf_selection_source;
    end
end
end

function result = run_ibr_analysis(case_data, opt, label, root, case_id)
ibr_analysis = lower(char(option_value(opt, 'ibr_analysis', 'ts')));
if strcmp(ibr_analysis,'full') && isfield(opt,'ibr_method_modes') && ...
        isstruct(opt.ibr_method_modes) && isfield(opt.ibr_method_modes,'linked') && ...
        ~logical(opt.ibr_method_modes.linked)
    result=run_ibr_full_separate(case_data,opt,label,root,case_id);
    return;
end
scenario_opt = struct();
if isfield(opt, 'ibr_profile') && ~isempty(opt.ibr_profile)
    scenario_opt.ibr_profile = opt.ibr_profile;
end

if isfield(opt, 'ibr_dispatch') && ~isempty(opt.ibr_dispatch)
    scenario_opt.dispatch = opt.ibr_dispatch;
end
base = cases.scenario_ieee14_1sg_4ibr(scenario_opt);
[scenario, selection] = stability.ibr_configure_scenario(base, opt);
if ~selection.ready
    result = struct('converged', false, 'metadata', struct( ...
        'failure', 'solve_case:ibr:initialSelection', ...
        'error', selection.failure_reason), 'selector_log', selection, ...
        'execution_summary', selection_failure_summary(selection));
    fprintf('\nIBR initial configuration rejected (no fallback).\n');
    stability.print_ibr_run_log(result);
    return;
end

switch ibr_analysis
    case 'pf'
        result = run_ibr_pf(case_data, selection, opt);
        print_pf_checks(result.pf, struct('tolerance', 1e-10));
        print_resource_injections(case_data, result.pf, opt, true, selection);
        print_ibr_product_summary(result);
    case 'pf_compare'
        result = wizard.ibr_sg_cycle_comparison(case_data, scenario, ...
            selection, opt, false, root, case_id);
    case 'sssa_compare'
        result = wizard.ibr_sg_cycle_comparison(case_data, scenario, ...
            selection, opt, true, root, case_id);
    case 'sssa'
        result = run_ibr_sssa(case_data, scenario, selection, opt);
        print_ibr_product_summary(result);
    case {'ts','full'}
        if ~isfield(opt, 'ibr_events') || ~isstruct(opt.ibr_events)
            opt.ibr_events = event_struct_from_flat(opt);
        end
        ts_result = stability.run_hybrid_case(scenario, opt);
        ts_result.selector_log = selection;
        if isfield(ts_result, 'execution_summary')
            ts_result.execution_summary.selector_candidate_evaluations = selection.candidate_count;
            ts_result.execution_summary.sssa_invocations = selection.sssa_evaluations;
        end
        if strcmp(ibr_analysis, 'ts')
            result = ts_result;
            result.ibr_analysis = 'ts';
            fprintf('\nRequested product : TIME-DOMAIN SIMULATION (TS)\n');
            stability.print_ibr_run_log(result);
        else
            result = assemble_ibr_full(case_data, scenario, selection, opt, ts_result);
            print_resource_injections(case_data, result.pf, opt, true, selection);
            print_ibr_product_summary(result);
        end
    otherwise
        error('wizard:dispatch_analysis:badIbrAnalysis', ...
            'Unknown IBR analysis %s.', ibr_analysis);
end

plot_requested = ~isfield(opt, 'plot_results') || opt.plot_results;
plot_result = result;
if strcmp(ibr_analysis, 'full') && ~isempty(result.ts), plot_result = result.ts; end
if plot_requested && isfield(plot_result,'t') && ~isempty(plot_result.t) && ...
        isfield(plot_result,'equilibrium') && plot_result.equilibrium.converged
    plot_result = enrich_ibr_plot_payload(plot_result, case_data, opt);
    p = stability.plot_ibr_ts_results(plot_result, struct( ...
        'output_dir', fullfile(root, 'output', 'plots'), ...
        'visible', logical(option_value(opt, 'plot_visible', false)), ...
        'prefix', case_id));
    files = {p.angle_plot, p.freq_plot, p.power_plot, p.voltage_plot};
    if isfield(p,'group_plots')
        files = [files, struct2cell(p.group_plots.sg).', ...
            struct2cell(p.group_plots.ibr).'];
    end
    if strcmp(ibr_analysis, 'full')
        result.ts = plot_result;
    else
        result = plot_result;
    end
    result.figure_files = files;
    if plot_result.converged
        plot_status = 'complete';
    else
        plot_status = 'PARTIAL / FAILED CLOSED';
    end
    fprintf('IBR TS plots (%s; %s):\n', label, plot_status);
    fprintf('  angle  : %s\n', p.angle_plot);
    fprintf('  omega  : %s\n', p.freq_plot);
    fprintf('  power  : %s\n', p.power_plot);
    fprintf('  voltage: %s\n', p.voltage_plot);
end
end

function result=run_ibr_full_separate(case_data,opt,label,root,case_id)
% Execute PF, SSSA and TS with independently selected IBR device-mode maps.
% Each product is an honest independent operating point; no cross-method
% equilibrium identity is claimed when the maps differ.
required={'pf','sssa','ts'};
for k=1:numel(required)
    if ~isfield(opt.ibr_method_modes,required{k})
        error('wizard:dispatch_analysis:missingMethodModeConfig', ...
            'Full Analysis separate mode requires ibr_method_modes.%s.',required{k});
    end
end

stage=struct();
for k=1:numel(required)
    name=required{k};
    stage_opt=apply_method_mode_config(opt,opt.ibr_method_modes.(name));
    stage_opt=rmfield(stage_opt,'ibr_method_modes');
    stage_opt.ibr_analysis=name;
    if ~strcmp(name,'ts')
        stage_opt.plot_results=false;
        stage_opt.ibr_events=struct('enabled',false);
    end
    stage.(name)=run_ibr_analysis(case_data,stage_opt,label,root,case_id);
end

result=struct();
result.ibr_analysis='full';
result.converged=logical(stage.pf.converged) && ...
    logical(stage.sssa.converged) && logical(stage.ts.converged);
result.failure_id=''; result.failure_reason='';
if ~result.converged
    result.failure_id='wizard:dispatch_analysis:fullStageFailed';
    result.failure_reason='At least one independently configured Full Analysis stage failed.';
end
result.pf=stage.pf.pf;
result.equilibrium=stage.sssa.equilibrium;
result.sssa=stage.sssa.sssa;
result.ts=stage.ts;
result.separate_stage_results=stage;
result.ibr_method_modes=opt.ibr_method_modes;
result.cross_analysis_identity='INDEPENDENT_MODE_CONFIGURATIONS';
if isequal(opt.ibr_method_modes.pf,opt.ibr_method_modes.sssa) && ...
        isequal(opt.ibr_method_modes.pf,opt.ibr_method_modes.ts)
    result.cross_analysis_identity='SAME_MODE_MAP_INDEPENDENT_EXECUTIONS';
end
if isfield(stage.ts,'figure_files'), result.figure_files=stage.ts.figure_files; end
result.execution_summary=sum_stage_summaries(stage);
fprintf('\nFULL ANALYSIS MODE CONFIGURATION: %s\n',result.cross_analysis_identity);
fprintf('  PF   GFM indices: %s\n',mat2str(opt.ibr_method_modes.pf.initial_gfm_indices));
fprintf('  SSSA GFM indices: %s\n',mat2str(opt.ibr_method_modes.sssa.initial_gfm_indices));
fprintf('  TS   GFM indices: %s\n',mat2str(opt.ibr_method_modes.ts.initial_gfm_indices));
end

function opt=apply_method_mode_config(opt,cfg)
names={'initial_gfm_count','initial_gfl_count','initial_gfm_indices', ...
    'initial_reference_resource_index'};
for k=1:numel(names)
    if ~isfield(cfg,names{k})
        error('wizard:dispatch_analysis:badMethodModeConfig', ...
            'Method mode configuration lacks %s.',names{k});
    end
    opt.(names{k})=cfg.(names{k});
end
opt=wizard.normalize_ibr_mode_selection(opt);
end

function summary=sum_stage_summaries(stage)
summary=struct('pf_invocations',0,'equilibrium_invocations',0, ...
    'sssa_invocations',0,'ts_invocations',0,'ts_steps_attempted',0, ...
    'ts_steps_accepted',0,'ts_newton_iterations',0, ...
    'event_transactions',0,'selector_candidate_evaluations',0);
names=fieldnames(stage);
for j=1:numel(names)
    r=stage.(names{j});
    if ~isfield(r,'execution_summary'), continue; end
    s=r.execution_summary;
    fields=fieldnames(summary);
    for k=1:numel(fields)
        f=fields{k};
        if isfield(s,f) && isnumeric(s.(f)) && isscalar(s.(f)) && isfinite(s.(f))
            summary.(f)=summary.(f)+s.(f);
        end
    end
end
end

function r = enrich_ibr_plot_payload(r, case_data, opt)
eq = r.equilibrium;
devices = eq.devices;
nd = numel(devices); nt = numel(r.t); nb = size(r.y_traj,1)/2;
offsets = zeros(1,nd); u_offsets = zeros(1,nd);
cx = 0; cu = 0;
for k=1:nd, offsets(k)=cx; u_offsets(k)=cu; cx=cx+devices(k).nx; cu=cu+devices(k).nu; end
if ~isfield(r,'u_history') || isempty(r.u_history)
    r.u_history = repmat(eq.u_eq(:),1,nt);
end
if ~isfield(r,'event_context_history') || numel(r.event_context_history) ~= nt
    r.event_context_history = repmat({eq.equilibrium_context},1,nt);
end
P=zeros(nd,nt); Q=zeros(nd,nt); Imag=zeros(nd,nt); lim=nan(nd,nt);
freq=nan(nd,nt); angle_deg=nan(nd,nt); online=false(nd,nt);
for j=1:nt
    x=r.x_traj(:,j); y=r.y_traj(:,j); u=r.u_history(:,j);
    ec=r.event_context_history{j};
    for k=1:nd
        dev=devices(k); xi=offsets(k)+(1:dev.nx); ui=u_offsets(k)+(1:dev.nu);
        I=dev.current_injection(r.t(j),x(xi),y,u(ui),ec);
        V=complex(y(2*dev.bus_position-1),y(2*dev.bus_position));
        S=V*conj(I); P(k,j)=real(S); Q(k,j)=imag(S); Imag(k,j)=abs(I);
        rec=dev.reconstruct(r.t(j),x(xi),y,u(ui),ec);
        online(k,j)=logical(rec.online);
        if isfield(rec,'delta')
            angle_deg(k,j)=rad2deg(rec.delta);
            freq(k,j)=case_data.base_values.frequency_Hz*(1+rec.omega);
        elseif isfield(rec,'gfm')
            angle_deg(k,j)=rad2deg(rec.gfm.delta_VSM);
            freq(k,j)=case_data.base_values.frequency_Hz*(1+rec.gfm.omega_m);
            if isfield(rec.gfm,'ImaxF_sys'), lim(k,j)=rec.gfm.ImaxF_sys; end
        elseif isfield(rec,'gfl')
            angle_deg(k,j)=rad2deg(rec.gfl.delta_PLL);
            if isfield(rec.gfl,'omega_PLL'), freq(k,j)=rec.gfl.omega_PLL/(2*pi); end
            if isfield(rec.gfl,'Imax') && isfield(rec.gfl,'kappa')
                lim(k,j)=rec.gfl.Imax/rec.gfl.kappa;
            end
        end
        if ~online(k,j), freq(k,j)=NaN; end
    end
end
Vmat=complex(r.y_traj(1:2:end,:),r.y_traj(2:2:end,:));
r.bus_ids=case_data.bus_data(:,1).';
r.device_ids={devices.device_id}; r.device_bus_ids=[devices.bus_id];
r.bus_voltage_magnitude=abs(Vmat(1:nb,:));
r.device_P_pu=P; r.device_Q_pu=Q;
r.device_P_MW=P*case_data.mpc.baseMVA; r.device_Q_MVAr=Q*case_data.mpc.baseMVA;
r.device_current_magnitude=Imag; r.device_current_limit_sys=lim;
r.device_frequency_Hz=freq; r.device_angle_deg=angle_deg;
r.base_frequency_Hz=case_data.base_values.frequency_Hz;
r.device_online_history=online;
types=cell(1,nd);
for k=1:nd
    types{k}='ibr';
    if isfield(devices(k),'capabilities') && ...
            isfield(devices(k).capabilities,'resource_type')
        types{k}=lower(char(devices(k).capabilities.resource_type));
    elseif startsWith(upper(char(devices(k).device_id)),'SG')
        types{k}='sg';
    end
end
r.device_resource_types=types;
r.plot_voltage_bus_id=option_value(opt,'fault_bus',4);
if ~isfield(r,'sched') || ~isstruct(r.sched)
    r.sched=struct('fault_bus',option_value(opt,'fault_bus',4));
end
end

function result = run_ibr_pf(case_data, selection, opt)
pf_opt = struct('verbose', logical(option_value(opt, 'pf_verbose', true)), ...
    'plot_results', logical(option_value(opt, 'plot_results', false)), 'max_iter', 50, ...
    'tolerance', 1e-10, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opt);
pf = enrich_pf_metadata(pf, 'newton_raphson', 'IBR_SUBANALYSIS_DEFAULT', ...
    pfsolver.pf_method_strategy('newton_raphson'));
result = struct('converged', logical(pf.converged), ...
    'ibr_analysis', 'pf', 'pf', pf, 'equilibrium', [], 'sssa', [], 'ts', [], ...
    'selector_log', selection, 'execution_summary', struct( ...
        'pf_stage_invocations', 1, 'pf_stage_names', {{'published_network_pf'}}, ...
        'equilibrium_invocations', 0, 'equilibrium_newton_iterations', 0, ...
        'sssa_invocations', 0, 'selector_candidate_evaluations', selection.candidate_count, ...
        'ts_invocations', 0, 'ts_step_attempts', 0, 'ts_accepted_steps', 0, ...
        'ts_newton_iterations', 0, 'event_transactions', 0));
if ~pf.converged
    result.failure_id = 'wizard:dispatch_analysis:ibrPf';
    result.failure_reason = 'The published IBR network power flow did not converge.';
end
end

function result = run_ibr_sssa(case_data, scenario, selection, opt)
[eq, dev_meta] = solve_ibr_operating_point(case_data, scenario, opt);
result = empty_ibr_product('sssa', selection);
result.equilibrium = eq;
result.metadata = struct('device_build', dev_meta);
if ~eq.converged
    result.failure_id = 'wizard:dispatch_analysis:ibrEquilibrium';
    result.failure_reason = eq.failure_reason;
    return;
end
sssa = linearize_ibr_equilibrium(case_data, eq, opt);
result.sssa = classify_ibr_sssa(sssa, opt);
result.converged = true;
result.execution_summary = ibr_stage_counts(3, 1, eq.iterations, 1, 0, selection);
end

function result = assemble_ibr_full(case_data, scenario, selection, opt, ts_result)
result = empty_ibr_product('full', selection);
result.failure_id = '';
result.failure_reason = '';
result.pf = run_ibr_pf(case_data, selection, opt).pf;
result.ts = ts_result;
if isfield(ts_result, 'equilibrium'), result.equilibrium = ts_result.equilibrium; end
if ~ts_result.converged || isempty(result.equilibrium) || ...
        ~isfield(result.equilibrium, 'converged') || ~result.equilibrium.converged
    result.converged = false;
    result.failure_id = option_value(ts_result, 'failure_id', ...
        'wizard:dispatch_analysis:ibrFullTs');
    result.failure_reason = option_value(ts_result, 'failure_reason', ...
        'Full Analysis stopped because the equilibrium/TS stage failed closed.');
else
    sssa = linearize_ibr_equilibrium(case_data, result.equilibrium, opt);
    result.sssa = classify_ibr_sssa(sssa, opt);
    result.converged = logical(result.pf.converged) && logical(ts_result.converged);
end
result.execution_summary = ts_result.execution_summary;
result.execution_summary.pf_stage_invocations = ...
    result.execution_summary.pf_stage_invocations + 2;
result.execution_summary.pf_stage_names{end+1} = 'published_network_pf';
result.execution_summary.pf_stage_names{end+1} = 'sssa_dae_warm_start';
if ~isempty(result.sssa)
    result.execution_summary.sssa_invocations = ...
        result.execution_summary.sssa_invocations + 1;
end
end

function [eq, dev_meta] = solve_ibr_operating_point(case_data, scenario, opt)
build_opt = struct();
if isfield(scenario, 'scenario_opt') && isstruct(scenario.scenario_opt)
    build_opt = scenario.scenario_opt;
end
[devices, dev_meta] = stability.build_mixed_resource_devices( ...
    case_data, scenario.resources, build_opt);
config = struct('devices', devices);
if isfield(scenario, 'config') && isstruct(scenario.config)
    fields = {'resource_ids','selected_gfm_indices','n_gfm_required', ...
        'reference_resource_index'};
    for k = 1:numel(fields)
        if isfield(scenario.config, fields{k}) && ~isempty(scenario.config.(fields{k}))
            config.(fields{k}) = scenario.config.(fields{k});
        end
    end
end
eq_opt = struct('verbose', logical(option_value(opt, 'verbose', false)), ...
    'tolerance', 1e-8, 'max_iter', 300, ...
    'load_model', option_value(opt, 'load_model', 'cz_p_cz_q'));
eq = stability.mixed_equilibrium_solve(case_data, config, eq_opt);
end

function sssa = linearize_ibr_equilibrium(case_data, eq, opt)
sssa_opt = struct('full_kcl', true, 'u_eq', eq.u_eq, ...
    'event_context', eq.equilibrium_context, ...
    'active_state_indices', eq.active_state_indices, ...
    'fd_eps', option_value(opt, 'fd_eps', 3e-6));
sssa = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, ...
    case_data, sssa_opt);
end

function sssa = classify_ibr_sssa(sssa, opt)
tol = option_value(opt, 'stability_tolerance', 1e-7);
lam = sssa.eigenvalues(:);
nu = sum(real(lam) > tol);
ns = sum(real(lam) < -tol);
nm = numel(lam) - nu - ns;
if nu > 0, status = 'UNSTABLE';
elseif nm > 0, status = 'MARGINAL';
else, status = 'ASYMPTOTICALLY STABLE'; end
sssa.execution_converged = true;
sssa.stability_status = status;
sssa.stability_tolerance = tol;
sssa.root_counts = struct('stable', ns, 'marginal', nm, 'unstable', nu);
end

function result = empty_ibr_product(kind, selection)
result = struct('converged', false, 'ibr_analysis', kind, 'pf', [], ...
    'equilibrium', [], 'sssa', [], 'ts', [], 'selector_log', selection, ...
    'metadata', struct(), 'execution_summary', ...
    ibr_stage_counts(0, 0, 0, 0, 0, selection));
end

function q = ibr_stage_counts(npf, neq, neq_iter, nsssa, nts, selection)
q = struct('pf_stage_invocations', npf, ...
    'pf_stage_names', {{'device_factory_warm_start','equilibrium_dae_warm_start'}}, ...
    'equilibrium_invocations', neq, 'equilibrium_newton_iterations', neq_iter, ...
    'sssa_invocations', nsssa, 'selector_candidate_evaluations', selection.candidate_count, ...
    'ts_invocations', nts, 'ts_step_attempts', 0, 'ts_accepted_steps', 0, ...
    'ts_newton_iterations', 0, 'event_transactions', 0);
end

function print_ibr_product_summary(result)
fprintf('\n---------------- IBR ANALYSIS PRODUCTS ----------------\n');
if strcmp(result.ibr_analysis, 'ts')
    requested = 'TIME-DOMAIN SIMULATION (TS)';
elseif strcmp(result.ibr_analysis, 'full')
    requested = 'FULL ANALYSIS (PF + EQUILIBRIUM + SSSA + TS)';
else
    requested = upper(result.ibr_analysis);
end
fprintf('Requested product : %s\n', requested);
fprintf('PF published      : %d\n', ~isempty(result.pf));
fprintf('Equilibrium       : %d\n', ~isempty(result.equilibrium));
fprintf('SSSA published    : %d\n', ~isempty(result.sssa));
fprintf('TS published      : %d\n', ~isempty(result.ts));
if ~isempty(result.sssa)
    fprintf('SSSA states       : %d\n', size(result.sssa.A,1));
    fprintf('Physical result   : %s\n', result.sssa.stability_status);
    print_ibr_sssa_details(result.sssa, result.equilibrium);
end
fprintf('Execution status  : %d\n', result.converged);
end

function print_ibr_sssa_details(sssa, eq)
active = sssa.active_state_indices(:);
labels = cell(numel(active),1);
device_ids = cell(numel(active),1);
local_indices = zeros(numel(active),1);
offsets = zeros(1,numel(eq.devices));
cursor = 0;
for k = 1:numel(eq.devices), offsets(k)=cursor; cursor=cursor+eq.devices(k).nx; end
fprintf('\nIBR/SG ACTIVE STATE INVENTORY\n');
for p = 1:numel(active)
    gi = active(p);
    dk = find(gi > offsets & gi <= offsets + [eq.devices.nx], 1);
    li = gi - offsets(dk);
    device_ids{p} = char(eq.devices(dk).device_id);
    local_indices(p) = li;
    name = char(eq.devices(dk).state_names{li});
    labels{p} = sprintf('%s:x_dev(%d) %s', device_ids{p}, li, name);
    fprintf('  A(%-3d) x(%-3d) device=%-5s local=%-2d state=%-18s : %s\n', ...
        p, gi, device_ids{p}, li, name, state_description(name));
end

modal = stability.modal_analysis(sssa);
fprintf('\nFULL STATE EIGENVALUES (MIXED SG/GFM/GFL)\n');
fprintf('Eigenvalue set  : %d roots from sssa.A (%d-by-%d)\n', ...
    numel(modal.eigenvalues), size(sssa.A,1), size(sssa.A,2));
fprintf('  No Pair  Real (1/s)   Imag (1/s)       f(Hz)       zeta  Dominant device/state                Part.\n');
for i = 1:numel(modal.eigenvalues)
    lam = modal.eigenvalues(i);
    ranking = modal.display_ranking(:,i);
    [rho,bi] = max(ranking);
    if isempty(bi) || ~isfinite(rho)
        bi = 1; rho = NaN;
    end
    fprintf('  %02d %4d %+11.2e %+11.2e %11.2e %10.2e  %-36s %6.2f%%\n', ...
        modal.display_mode_number(i), modal.conjugate_pair_id(i), ...
        real(lam), imag(lam), abs(imag(lam))/(2*pi), ...
        -real(lam)/(abs(lam)+eps), labels{bi}, 100*rho);
end
fprintf(['Participation domain: original active coordinates of sssa.A; ', ...
    'unavailable/ill-conditioned modes retain their eigenvalues.\n']);
if isfield(sssa, 'physical_A') && ~isempty(sssa.physical_A)
    physical = stability.modal_analysis(sssa, struct('domain','physical_A'));
    fprintf('\nPHYSICAL DECISION EIGENVALUES\n');
    fprintf('Matrix dimension : %d (published alongside, never replaces full state)\n', ...
        physical.matrix_dimension);
    fprintf('  No Pair  Real (1/s)   Imag (1/s)       f(Hz)       zeta\n');
    for i = 1:numel(physical.eigenvalues)
        lam = physical.eigenvalues(i);
        fprintf('  %02d %4d %+11.2e %+11.2e %11.2e %10.2e\n', ...
            physical.display_mode_number(i), physical.conjugate_pair_id(i), ...
            real(lam), imag(lam), abs(imag(lam))/(2*pi), ...
            -real(lam)/(abs(lam)+eps));
    end
end
end

function summary = selection_failure_summary(selection)
summary = struct( ...
    'pf_stage_invocations', 3*selection.equilibrium_evaluations, ...
    'pf_stage_names', {{'selector_candidate_device/equilibrium/sssa_warm_starts'}}, ...
    'equilibrium_invocations', selection.equilibrium_evaluations, ...
    'equilibrium_newton_iterations', 0, ...
    'sssa_invocations', selection.sssa_evaluations, ...
    'selector_candidate_evaluations', selection.candidate_count, ...
    'ts_invocations', 0, 'ts_step_attempts', 0, 'ts_accepted_steps', 0, ...
    'ts_newton_iterations', 0, 'event_transactions', 0);
end

function ev = event_struct_from_flat(opt)
required = {'events_enabled','fault_bus','Zf','fault_on','fault_clear', ...
    'sg_trip','sg_on','post_trip_gfm_indices','post_trip_reference_resource_index'};
for k = 1:numel(required)
    if ~isfield(opt, required{k})
        error('wizard:dispatch_analysis:ibr:eventOptions', ...
            'Missing options.%s.', required{k});
    end
end
ev = struct('enabled', logical(opt.events_enabled), 'fault_bus', opt.fault_bus, ...
    'Zf', opt.Zf, 'fault_on', opt.fault_on, 'fault_clear', opt.fault_clear, ...
    'sg_trip', opt.sg_trip, 'sg_on', opt.sg_on, ...
    'selected_gfm_indices', opt.post_trip_gfm_indices, ...
    'reference_resource_index', opt.post_trip_reference_resource_index);
end

function result = annotate_launcher_execution(analysis, result)
if isfield(result, 'execution_summary'), return; end
summary = struct('pf_invocations', 0, 'sssa_invocations', 0, 'ts_invocations', 0, ...
    'solver_iterations', 0, 'linearized_state_count', 0, 'eigenvalue_count', 0, ...
    'ts_step_count', 0);
switch analysis
    case 'pf'
        summary.pf_invocations = 1;
        if isfield(result, 'iterations'), summary.solver_iterations = result.iterations; end
    case 'sssa'
        summary.sssa_invocations = 1;
        if isfield(result, 'newton_iterations'), summary.solver_iterations = result.newton_iterations; end
        if isfield(result, 'Afull'), summary.linearized_state_count = size(result.Afull, 1); end
        if isfield(result, 'eigenvalues'), summary.eigenvalue_count = numel(result.eigenvalues); end
    case 'ts'
        summary.ts_invocations = 1;
        if isfield(result, 'accepted_steps'), summary.ts_step_count = result.accepted_steps;
        elseif isfield(result, 't'), summary.ts_step_count = max(0, numel(result.t)-1); end
end
result.execution_summary = summary;
end

function result = annotate_sssa_result(result, opt)
if ~isfield(result, 'state_names') || isempty(result.state_names)
    result.state_names = arrayfun(@(k) sprintf('x%d', k), 1:size(result.Afull,1), ...
        'UniformOutput', false).';
else
    result.state_names = result.state_names(:);
end
if isfield(result, 'reduced_eigenvalues'), lam = result.reduced_eigenvalues(:);
else, lam = result.eigenvalues(:); end
tol = 1e-7;
if isfield(opt, 'stability_tolerance'), tol = opt.stability_tolerance; end
nu = sum(real(lam) > tol); ns = sum(real(lam) < -tol); nm = numel(lam) - nu - ns;
if isempty(lam), status = 'NOT APPLICABLE - NO RELATIVE MODES';
elseif nu > 0, status = 'UNSTABLE';
elseif nm > 0, status = 'MARGINAL';
else, status = 'ASYMPTOTICALLY STABLE'; end
result.stability_status = status;
result.stability_tolerance = tol;
result.root_counts = struct('stable', ns, 'marginal', nm, 'unstable', nu);
end

function print_launcher_header(analysis, case_label, logfile, case_data)
fprintf('\n============================================================\n');
fprintf('IN-HOUSE ANALYSIS LAUNCHER\n');
if strcmp(analysis, 'ts')
    analysis_label = 'TIME-DOMAIN SIMULATION (TS)';
else
    analysis_label = upper(analysis);
end
fprintf('Analysis : %s\n', analysis_label);
fprintf('Case     : %s\n', case_label);
fprintf('Time     : %s\n', datestr(now, 31));
fprintf('Log      : %s\n', logfile);
fprintf('Engine   : project MATLAB code only (no external solver)\n');
fprintf('============================================================\n');
if isfield(case_data, 'schema_version')
    fprintf('Schema   : %s\n', case_data.schema_version);
end
if isfield(case_data, 'base_values')
    fprintf('Base     : %.6g MVA, %.6g Hz\n', ...
        case_data.base_values.S_base_MVA, case_data.base_values.frequency_Hz);
end
if isfield(case_data, 'bus_data')
    fprintf('Network  : %d buses, %d branches\n', ...
        size(case_data.bus_data, 1), size(case_data.line_data, 1));
end
end

function print_resource_injections(case_data, pf, opt, is_ibr, selection)
% Reporting-only ownership map. P/Q are solved PF injections and never feed
% back into the numerical solution.
if nargin < 5, selection = struct(); end
bus_ids = pf.external_bus_ids(:);
gen_pos = find(pf.bus_type(:) <= 2);
Sbase = pf.base_values.S_base_MVA;
fprintf('\n---------------- RESOURCE INJECTION BREAKDOWN ----------------\n');
fprintf('  %-7s %-6s %-12s %10s %10s %11s %11s\n', ...
    'Device','Bus','Mode','P (pu)','Q (pu)','P (MW)','Q (MVAr)');
if is_ibr
    profile = lower(char(option_value(opt, 'ibr_profile', 'rms10_profile_b')));
    if strcmp(profile, 'rms10_profile_b')
        ids = {'SG1','IBR2','IBR3','IBR6','IBR8'};
        rb = [1 2 3 6 8];
        if isfield(selection,'selected_gfm_indices')
            gfm_idx = selection.selected_gfm_indices;
        elseif isfield(opt,'initial_gfm_indices')
            % Empty is an authoritative all-GFL request, not a missing value.
            gfm_idx = opt.initial_gfm_indices;
        else
            gfm_idx = 2;
        end
        modes = {'SG-EMF6','GFL-RMS10','GFL-RMS10','GFL-RMS10','GFL-RMS10'};
        for j = 1:4
            if ismember(j+1, gfm_idx), modes{j+1} = 'GFM-13'; end
        end
        ngfm = numel(gfm_idx); ngfl = 4-ngfm;
        active_order = 5 + 13*ngfm + 10*ngfl;
        if isequal(gfm_idx(:).', 2)
            profile_name = 'RMS10 Profile B';
        else
            profile_name = 'RMS10 configurable mix';
        end
        if ngfm == 0
            fprintf('Profile : %s | SG=1, GFL-RMS10=%d\n',profile_name,ngfl);
            fprintf('Order   : active=%d (SG 5 + %dxGFL 10), inventory=98\n', ...
                active_order,ngfl);
        else
            fprintf('Profile : %s | SG=1, GFM=%d, GFL-RMS10=%d\n', ...
                profile_name, ngfm, ngfl);
            fprintf('Order   : active=%d (SG 5 + %dxGFM 13 + %dxGFL 10), inventory=98\n', ...
                active_order, ngfm, ngfl);
        end
    else
        ids = arrayfun(@(k) sprintf('GEN%d',k), 1:numel(gen_pos), 'UniformOutput', false);
        rb = bus_ids(gen_pos).';
        modes = repmat({'LEGACY/CONFIGURED'}, 1, numel(rb));
        fprintf('Profile : legacy/configured; runtime mode map governs state ownership\n');
    end
else
    ids = arrayfun(@(k) sprintf('G%d',k), 1:numel(gen_pos), 'UniformOutput', false);
    rb = bus_ids(gen_pos).';
    modes = repmat({'SG'}, 1, numel(rb));
    fprintf('Resources: SG=%d, GFM=0, GFL=0 (REF/PV generator-bus mapping)\n', numel(rb));
end
psum = 0; qsum = 0;
for k = 1:numel(rb)
    pos = find(bus_ids == rb(k), 1);
    if isempty(pos), continue; end
    p = pf.P_generation(pos); q = pf.Q_generation(pos);
    psum = psum + p; qsum = qsum + q;
    fprintf('  %-7s %-6g %-12s %10.4f %10.4f %11.2f %11.2f\n', ...
        ids{k}, rb(k), modes{k}, p, q, p*Sbase, q*Sbase);
end
fprintf('  %-7s %-6s %-12s %10.4f %10.4f %11.2f %11.2f\n', ...
    'TOTAL','-','-',psum,qsum,psum*Sbase,qsum*Sbase);
fprintf('Reconcile: resource totals equal PF total generation: dP=%+.3e pu, dQ=%+.3e pu\n', ...
    psum-pf.P_total_gen, qsum-pf.Q_total_gen);
if isfield(case_data,'source'), fprintf('Mapping source: %s\n', char(case_data.source)); end
end

function print_run_options(opt)
fprintf('\n---------------- RUN SETTINGS -------------------\n');
names = fieldnames(opt);
for k = 1:numel(names)
    name = names{k}; value = opt.(name);
    if islogical(value) && isscalar(value), text = mat2str(value);
    elseif isnumeric(value) && isscalar(value)
        if isreal(value), text = sprintf('%.12g', value);
        else, text = sprintf('%.12g %+.12gj', real(value), imag(value)); end
    elseif ischar(value) || (isstring(value) && isscalar(value)), text = char(value);
    elseif isempty(value), text = '[]';
    else, text = sprintf('<%s %s>', class(value), mat2str(size(value))); end
    fprintf('%-20s: %s\n', name, text);
end
end

function value = option_value(s, name, default)
value = default;
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); end
end

function print_pf_checks(r, opt)
fprintf('\n---------------- PF VERIFICATION ----------------\n');
fprintf('Converged       : %d\n', r.converged);
if isfield(r, 'iterations'), fprintf('Iterations      : %d\n', r.iterations); end
if isfield(r, 'max_mismatch'), fprintf('Max mismatch    : %.3e pu\n', r.max_mismatch); end
if isfield(r, 'metadata')
    if isfield(r.metadata, 'method_executed')
        fprintf('Method executed : %s\n', r.metadata.method_executed);
    end
    if isfield(r.metadata, 'dispatch_requested')
        fprintf('Dispatch req    : %s\n', r.metadata.dispatch_requested);
    end
end
fprintf('Voltage range   : %.6f .. %.6f pu\n', min(r.bus_voltage), max(r.bus_voltage));
fprintf('Angle range     : %.6f .. %.6f deg\n', min(r.bus_angle_deg), max(r.bus_angle_deg));
fprintf('Tolerance       : %.3e\n', opt.tolerance);
if ~r.converged
    msg = 'Power flow did not converge.';
    if isfield(r, 'reason'), msg = sprintf('%s\n  reason: %s', msg, r.reason); end
    error('solve_case:pf', msg);
end
end

function print_sssa_checks(r)
fprintf('\n---------------- SSSA VERIFICATION --------------\n');
fprintf('Dynamic states  : %d\n', numel(r.state_names));
fprintf('Stability status: %s\n', r.stability_status);
fprintf('Decision tol.   : %.3e 1/s\n', r.stability_tolerance);
if isfield(r, 'reduced_eigenvalues') && ...
        numel(r.reduced_eigenvalues) < numel(r.eigenvalues)
    fprintf('Decision basis  : COI-relative set (%d roots)\n', ...
        numel(r.reduced_eigenvalues));
else
    fprintf('Decision basis  : full state eigenvalue set (%d roots)\n', ...
        numel(r.eigenvalues));
end
fprintf('Root counts     : stable=%d, marginal=%d, unstable=%d\n', ...
    r.root_counts.stable, r.root_counts.marginal, r.root_counts.unstable);
if isfield(r, 'newton_residual'), fprintf('DAE residual    : %.3e\n', r.newton_residual); end
fprintf('\nSTATE INVENTORY\n');
for k = 1:numel(r.state_names)
    fprintf('  x(%-3d) %-28s : %s\n', k, r.state_names{k}, ...
        state_description(r.state_names{k}));
end
lam = r.eigenvalues(:);
fprintf('\nFULL STATE EIGENVALUES\n');
fprintf('Eigenvalue set  : %d roots\n', numel(lam));
fprintf('Max real(lambda): %+.6e 1/s\n', max(real(lam)));
[lam_table, mode_labels, display_order] = sssa_table_display_order(r, lam);
fprintf('Display order   : %s\n', display_order);
print_eigenvalue_table(r.Afull, r.state_names, lam_table, mode_labels);
end

function [lam_table, mode_labels, description] = sssa_table_display_order(r, lam)
lam = lam(:); n = numel(lam);
lam_table = lam; mode_labels = cell(n,1);
description = 'computed eigensolver order';
if ~isfield(r,'launcher_eigenvalue_display') || ...
        ~isstruct(r.launcher_eigenvalue_display), return; end
md = r.launcher_eigenvalue_display;
required = {'order','mode_labels','description','diagnostic_only'};
if ~all(isfield(md,required)) || ~isequal(md.diagnostic_only,true), return; end
order = md.order(:); labels = md.mode_labels(:);
if numel(order) ~= n || numel(labels) ~= n || any(~isfinite(order)) || ...
        any(order ~= fix(order)) || ~isequal(sort(order),(1:n).'), return; end
lam_table = lam(order); mode_labels = labels;
description = char(md.description);
end

function print_eigenvalue_table(A, state_names, lam, mode_labels)
% Left/right eigensolves are paired directly; no inv/pinv is used.
if isempty(A) || isempty(lam), return; end
lam = lam(:); state_names = state_names(:); mode_labels = mode_labels(:);
if size(A,1) ~= numel(lam) || numel(state_names) ~= numel(lam), return; end
[V,d] = eig(A,'vector');
[U,dl] = eig(A','vector');
used_r = false(numel(d),1); used_l = false(numel(dl),1);
fprintf('\n  No  Dominant state              Real (1/s)   Imag (1/s)       f(Hz)       zeta  Mode\n');
for i = 1:numel(lam)
    candidates = find(~used_r);
    [~,jr] = min(abs(d(candidates)-lam(i))); ir = candidates(jr); used_r(ir)=true;
    candidates = find(~used_l);
    [~,jl] = min(abs(dl(candidates)-conj(lam(i)))); il = candidates(jl); used_l(il)=true;
    alpha = U(:,il)'*V(:,ir);
    if isfinite(alpha) && abs(alpha) > 100*eps
        ui = U(:,il)/conj(alpha);
        score = abs(conj(ui).*V(:,ir));
    else
        score = abs(V(:,ir));
    end
    [~,bi] = max(score);
    re_i = real(lam(i)); im_i = imag(lam(i));
    fhz = abs(im_i)/(2*pi); zet = -re_i/(abs(lam(i))+eps);
    cm = mode_labels{i};
    if isempty(cm), cm = state_description(state_names{bi}); end
    fprintf('  %02d  %-24s %+11.2e %+11.2e %11.2e %10.2e  %s\n', ...
        i, char(state_names{bi}), re_i, im_i, fhz, zet, char(cm));
end
end

function text = state_description(raw)
s = lower(char(raw));
if contains(s,'delta_pll')
    text='PLL electrical angle / grid-synchronization state';
elseif contains(s,'xi_pll') || contains(s,'pll_int')
    text='PLL PI integrator state';
elseif contains(s,'delta_itmax') || contains(s,'delta_itmin')
    text='dynamic GFM current-angle bound';
elseif contains(s,'delta_it')
    text='VSG internal angle relative to PLL frame';
elseif contains(s,'delta')
    text='synchronous-machine rotor electrical angle';
elseif contains(s,'omega_m')
    text='VSG virtual rotor speed deviation';
elseif contains(s,'omega')
    text='synchronous-machine rotor speed deviation';
elseif contains(s,'x_washout')
    text='VSG damping washout state';
elseif contains(s,'x_eint')
    text='GFM voltage-controller integrator';
elseif contains(s,'p_f') || contains(s,'pinv_f')
    text='filtered active-power measurement';
elseif contains(s,'q_f') || contains(s,'qinv_f')
    text='filtered reactive-power measurement';
elseif contains(s,'xi_p')
    text='active-power outer-loop integrator';
elseif contains(s,'xi_q')
    text='reactive-power outer-loop integrator';
elseif contains(s,'xi_id')
    text='d-axis current-controller integrator';
elseif contains(s,'xi_iq')
    text='q-axis current-controller integrator';
elseif contains(s,'i_d') || contains(s,'idinv')
    text='d-axis converter current/filter state';
elseif contains(s,'i_q') || contains(s,'iqinv')
    text='q-axis converter current/filter state';
elseif contains(s,'v_f') || contains(s,'vinv_f') || contains(s,'vt_f')
    text='filtered terminal-voltage magnitude';
elseif contains(s,'eqpp')
    text='q-axis subtransient internal EMF';
elseif contains(s,'edpp')
    text='d-axis subtransient internal EMF';
elseif contains(s,'eqp')
    text='q-axis transient internal EMF';
elseif contains(s,'edp')
    text='d-axis transient internal EMF';
elseif contains(s,'efd')
    text='field-voltage / exciter state';
elseif contains(s,'vr') || contains(s,'v_r')
    text='AVR regulator state';
elseif contains(s,'rf') || contains(s,'r_f')
    text='exciter stabilizing-feedback state';
else
    text='model state; see device equation/state-order contract';
end
end

function print_ts_checks(r)
fprintf('\n---------------- TS VERIFICATION ----------------\n');
fprintf('Samples         : %d\n', numel(r.t));
fprintf('Time range      : %.4f .. %.4f s\n', r.t(1), r.t(end));
fprintf('Minimum voltage : %.6f pu\n', min(r.Vbus, [], 'all'));
if isfield(r, 'omega_is_deviation') && r.omega_is_deviation
    wd = r.omega;
else
    wd = r.omega - 1;
end
fprintf('Max |Delta w|   : %.6e pu\n', max(abs(wd), [], 'all'));
if isfield(r, 'integrator'), fprintf('Integrator      : %s\n', r.integrator); end
end

function print_launcher_execution(q)
fprintf('\n---------------- LAUNCHER WORK COUNTS --------------------\n');
fprintf('PF / SSSA / TS invocations : %d / %d / %d\n', ...
    q.pf_invocations, q.sssa_invocations, q.ts_invocations);
if isfield(q, 'solver_iterations')
    fprintf('Solver iterations          : %d\n', q.solver_iterations);
end
if isfield(q, 'linearized_state_count')
    fprintf('Linearized states / roots  : %d / %d\n', ...
        q.linearized_state_count, q.eigenvalue_count);
end
if isfield(q, 'ts_step_count')
    fprintf('TS accepted steps          : %d\n', q.ts_step_count);
end
end
