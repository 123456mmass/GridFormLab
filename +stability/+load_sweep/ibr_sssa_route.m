function point = ibr_sssa_route(case_data, scenario, opt)
%IBR_SSSA_ROUTE  Shared pure IBR SSSA route for single-point and load-sweep.
%   POINT = stability.load_sweep.ibr_sssa_route(CASE_DATA, SCENARIO, OPT)
%   runs the mixed-resource composite equilibrium + full-KCL SSSA for ONE
%   operating point. This is a pure route helper extracted from the existing
%   run_ibr_sssa call graph so both single-point IBR SSSA and load-sweep
%   IBR SSSA call ONE implementation. It does NOT duplicate equations,
%   equilibrium construction, active-state selection, or full-KCL SSSA logic.
%
%   Stages (each fail-closed with a typed failure_stage + failure_id):
%     DEVICE_BUILD  -> stability.build_mixed_resource_devices
%     EQUILIBRIUM   -> stability.mixed_equilibrium_solve
%     SSSA_LINEARIZATION -> stability.composite_sssa_model (full_kcl=true)
%     MODAL_REPORTING   -> stability.modal_analysis
%
%   The REF bus injection balances PF mismatch (PF contract). Tm/Efd are
%   equilibrium initialization inputs, NOT a PF redispatch policy.

point = struct();
point.failure_stage = '';
point.failure_id = '';
point.failure_reason = '';

% --- DEVICE_BUILD ---------------------------------------------------------
build_opt = struct();
if isfield(scenario,'scenario_opt') && isstruct(scenario.scenario_opt)
    build_opt = scenario.scenario_opt;
end
config = struct();
if isfield(scenario,'config') && isstruct(scenario.config)
    fields = {'resource_ids','selected_gfm_indices','n_gfm_required', ...
        'reference_resource_index'};
    for k = 1:numel(fields)
        if isfield(scenario.config, fields{k}) && ~isempty(scenario.config.(fields{k}))
            config.(fields{k}) = scenario.config.(fields{k});
        end
    end
end
try
    [devices, dev_meta] = stability.build_mixed_resource_devices( ...
        case_data, scenario.resources, build_opt);
catch err
    point.failure_stage = 'DEVICE_BUILD';
    point.failure_id = 'sssa_load_sweep:deviceBuild';
    point.failure_reason = err.message;
    point.devices = [];
    point.dev_meta = [];
    return;
end
config.devices = devices;
point.devices = devices;
point.dev_meta = dev_meta;

% --- EQUILIBRIUM ----------------------------------------------------------
eq_opt = struct('verbose', logical(option_value(opt,'verbose',false)), ...
    'tolerance', 1e-8, 'max_iter', 300, ...
    'load_model', option_value(opt,'load_model','cz_p_cz_q'));
try
    eq = stability.mixed_equilibrium_solve(case_data, config, eq_opt);
catch err
    point.failure_stage = 'EQUILIBRIUM';
    point.failure_id = 'sssa_load_sweep:equilibrium';
    point.failure_reason = err.message;
    point.equilibrium = struct('converged',false,'failure_reason',err.message);
    return;
end
point.equilibrium = eq;
if ~eq.converged
    point.failure_stage = 'EQUILIBRIUM';
    point.failure_id = 'sssa_load_sweep:equilibriumNoConverge';
    point.failure_reason = option_value(eq,'failure_reason', ...
        'mixed_equilibrium_solve did not converge');
    return;
end

% --- SSSA_LINEARIZATION ---------------------------------------------------
try
    sssa_opt = struct('full_kcl', true, 'u_eq', eq.u_eq, ...
        'event_context', eq.equilibrium_context, ...
        'active_state_indices', eq.active_state_indices, ...
        'fd_eps', option_value(opt,'fd_eps',3e-6));
    sssa = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, ...
        case_data, sssa_opt);
catch err
    point.failure_stage = 'SSSA_LINEARIZATION';
    point.failure_id = 'sssa_load_sweep:sssa';
    point.failure_reason = err.message;
    point.sssa = [];
    return;
end
% Forward active_bound_regimes if the accepted equilibrium exposes them so
% physical_A is produced by the existing attach_physical_decision_spectrum.
if isfield(eq,'active_bound_regimes') && ~isempty(eq.active_bound_regimes)
    try
        sssa_opt_phys = sssa_opt;
        sssa_opt_phys.active_bound_regimes = eq.active_bound_regimes;
        sssa = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, ...
            case_data, sssa_opt_phys);
    catch
        % physical_A is optional; retain the raw-A SSSA result.
    end
end
point.sssa = sssa;

% --- MODAL_REPORTING ------------------------------------------------------
try
    modal = stability.modal_analysis(sssa);
    point.modal = modal;
catch err
    point.failure_stage = 'MODAL_REPORTING';
    point.failure_id = 'sssa_load_sweep:modal';
    point.failure_reason = err.message;
    point.modal = [];
end
end

function value = option_value(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end
