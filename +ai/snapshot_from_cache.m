function [snap, r, meta] = snapshot_from_cache(scenario_id, opts, cache_dir)
%SNAPSHOT_FROM_CACHE  Build a supervisor snapshot from one cached scenario run.
%
%   [SNAP, R, META] = ai.snapshot_from_cache(SCENARIO_ID, OPTS, CACHE_DIR)
%
%   Reads output/diagnostics/ieee14_scenario_suite/<SCENARIO_ID>.mat -- written
%   by scripts/reporting/run_ieee14_scenario_suite.m -- and normalizes it through
%   ai.snapshot_from_state. Nothing is simulated here; this reader never
%   re-runs the engine, so a supervisor verdict is reproducible from the cache
%   alone.
%
%   R is the raw result struct, returned so a caller can cross-check a
%   reconstructed feature against the stored one. META carries the cache path
%   and the stored option signature.
%
%   ESCR is taken from result.agsi_reference.scr when the cache has it -- those
%   values were computed by the run that produced the trajectory, on the live
%   dae, and are preferred to any reconstruction. A cache that predates that
%   field falls back to ai.ai_escr_metrics over result.Y_log.
%
%   See also ai.snapshot_from_state, ai.ai_escr_metrics.

arguments
    scenario_id (1,1) string
    opts struct = ai.ai_supervisor_defaults()
    cache_dir (1,1) string = fullfile('output','diagnostics','ieee14_scenario_suite')
end

f = fullfile(cache_dir, scenario_id + ".mat");
if ~isfile(f)
    error('ai:snapshot_from_cache:cacheMissing', ...
        ['No cache at %s. Run ' ...
         'run_ieee14_scenario_suite(scenarios="%s") first; this reader ' ...
         'never simulates.'], f, scenario_id);
end

S = load(f);
for fld = {'result'}
    if ~isfield(S, fld{1})
        error('ai:snapshot_from_cache:cacheIncomplete', ...
            'Cache %s lacks the "%s" variable.', f, fld{1});
    end
end
r = S.result;

req = {'t','bus_voltage_magnitude','bus_ids','device_bus_ids', ...
    'device_modes_history','coi_frequency_Hz','device_ids'};
for k = 1:numel(req)
    if ~isfield(r, req{k}) || isempty(r.(req{k}))
        error('ai:snapshot_from_cache:resultIncomplete', ...
            'Cache %s: result lacks a usable "%s" field.', f, req{k});
    end
end

% --- IBR device indices ---------------------------------------------------
% agsi_reference.device_indices is authoritative when present: its order is the
% column order of agsi_reference.scr, so taking the ESCR from it cannot
% mis-associate a converter with another converter's impedance.
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference) && ...
        isfield(r.agsi_reference,'device_indices') && ...
        ~isempty(r.agsi_reference.device_indices)
    ibr_idx = r.agsi_reference.device_indices(:)';
else
    ibr_idx = find(startsWith(string(r.device_ids), "IBR"));
    if isempty(ibr_idx)
        error('ai:snapshot_from_cache:noIbrDevices', ...
            ['Cache %s: no device id begins with "IBR" and result has no ' ...
             'agsi_reference.device_indices. Cannot identify the switchable ' ...
             'converters.'], f);
    end
end

% --- state struct ---------------------------------------------------------
state = struct();
state.t = r.t(:)';
state.V_bus_pu = r.bus_voltage_magnitude;
state.bus_ids = r.bus_ids(:);
state.device_bus_ids = r.device_bus_ids(:)';
state.device_modes = r.device_modes_history;
state.ibr_device_indices = ibr_idx;
state.f_coi_Hz = r.coi_frequency_Hz(:)';
state.device_ids = r.device_ids;

n = numel(state.t);
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference) && ...
        isfield(r.agsi_reference,'rocof_Hz_s') && ...
        numel(r.agsi_reference.rocof_Hz_s) == n
    state.rocof_Hz_s = r.agsi_reference.rocof_Hz_s(:)';
end

% ESCR straight from the stored diagnostic when its shape agrees with this
% snapshot; otherwise leave it off so snapshot_from_state rebuilds it.
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference) && ...
        isfield(r.agsi_reference,'scr') && ...
        isequal(size(r.agsi_reference.scr), [n, numel(ibr_idx)])
    state.escr = r.agsi_reference.scr';
end

% The pre-disturbance voltage profile the case itself defines, used as the
% "healthy" reference of J_V. Device-bus resolution is exactly what J_V needs,
% since J_V is only ever formed at a converter bus.
%
% V0_per_bus is a complex PHASOR (build_mixed_resource_devices.m:264 stores
% V0_complex). J_V is defined on magnitudes -- the engine feeds it
% sys.pf.bus_voltage, which is a magnitude, and compares it to |V| directly
% (+stability/agsi_reference_terms.m:186). Taking abs() here is what makes the
% two agree, and it is also what keeps a complex value from reaching the JSON
% payload.
if isfield(r,'metadata') && isfield(r.metadata,'device_build') && ...
        isfield(r.metadata.device_build,'bus_ids') && ...
        isfield(r.metadata.device_build,'V0_per_bus')
    state.healthy_bus_ids = r.metadata.device_build.bus_ids(:);
    state.healthy_V = abs(r.metadata.device_build.V0_per_bus(:));
end

state.Y_log = [];
if isfield(r,'Y_log'), state.Y_log = r.Y_log; end
if isfield(r,'topology_history'), state.topology_history = r.topology_history; end
state.srated_pu = opts.ibr_srated_pu;

snap = ai.snapshot_from_state(state, opts);

meta = struct();
meta.cache_file = f;
meta.scenario_id = scenario_id;
if isfield(S,'opt_signature'), meta.opt_signature = S.opt_signature; end
if isfield(S,'arm'), meta.arm = S.arm; end
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference)
    meta.rocof_method = string(r.agsi_reference.rocof_method);
    meta.agsi_base_classification = string(r.agsi_reference.base_classification);
else
    meta.rocof_method = "unknown";
    meta.agsi_base_classification = "unknown";
end
end
