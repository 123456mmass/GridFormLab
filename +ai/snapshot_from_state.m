function snap = snapshot_from_state(state, opts)
%SNAPSHOT_FROM_STATE  Normalize one recorded system state into a supervisor snapshot.
%
%   SNAP = ai.snapshot_from_state(STATE, OPTS)
%
%   This is the ONE entry point every caller shares: ai.snapshot_from_cache
%   builds a STATE from a cached run, and a live driver may build the same
%   struct from its own step loop. Because the normalization lives here once,
%   the offline replay and a future live hook cannot drift apart in what the
%   supervisor is shown.
%
%   STATE fields (required unless noted):
%     t                  1-by-n sample times, NON-DECREASING. The adaptive
%                        stepper emits repeated timestamps within one step, so
%                        t is not strictly increasing and any rate computed
%                        here guards against a zero interval.
%     V_bus_pu           nb-by-n bus voltage magnitudes, row = bus POSITION
%     bus_ids            nb-by-1 bus numbers, position k <-> row k
%     device_bus_ids     1-by-nd bus number of each device
%     device_modes       nd-by-n cellstr of device mode labels
%     ibr_device_indices 1-by-m indices of the switchable IBR devices
%     f_coi_Hz           1-by-n centre-of-inertia frequency
%   Optional:
%     rocof_Hz_s         1-by-n; NaN entries are filled by finite difference
%     escr               m-by-n; when absent and Y_log is given, it is rebuilt
%     Y_log              logged topologies (t, topology, Y) for the rebuild
%     srated_pu          1-by-m converter ratings on the system base
%     healthy_V, healthy_bus_ids   pre-disturbance voltage profile
%
%   SNAP adds, on top of the inputs:
%     V_min_pu      minimum bus voltage over ALL buses, per sample
%     V_ibr_pu      m-by-n voltages at the IBR buses only
%     ibr_bus_ids   1-by-m
%     S             1-by-n worst severity over the IBR devices,
%                   S_i = sat(0.5*J_V,i + 0.5*J_f), sat(x) = min(1,max(0,x))
%     J_V, J_f      the two terms S is formed from, kept separate
%     rocof_source  per sample: "analytic" | "finite_difference" | "unavailable"
%     escr_source   "provided" | "rebuilt_from_Y_log" | "unavailable"
%
%   WHY ROCOF NEEDS A FALLBACK. The engine's analytic RoCoF is assembled from
%   device RHS speed rows and requires an online GFM with H > 0
%   (+stability/agsi_reference_terms.m:159-167). In the very scenario this
%   supervisor exists for -- SG tripped, every IBR still GFL -- there is no such
%   device, so the analytic trace is NaN exactly when it is most wanted. The
%   finite difference below is the substitute, and the per-sample
%   rocof_source records which one each value came from, so a report can never
%   present a reconstructed number as a measured one.
%
%   See also ai.snapshot_from_cache, ai.ai_detect_event.

arguments
    state struct
    opts struct = ai.ai_supervisor_defaults()
end

req = {'t','V_bus_pu','bus_ids','device_bus_ids','device_modes', ...
    'ibr_device_indices','f_coi_Hz'};
for k = 1:numel(req)
    if ~isfield(state, req{k})
        error('ai:snapshot_from_state:missingField', ...
            'STATE is missing required field "%s".', req{k});
    end
end

t = state.t(:)';
n = numel(t);
snap = struct();
snap.t = t;
snap.n = n;
snap.V_bus_pu = state.V_bus_pu;
snap.bus_ids = state.bus_ids(:);
snap.f_coi_Hz = state.f_coi_Hz(:)';

if size(state.V_bus_pu, 2) ~= n
    error('ai:snapshot_from_state:sampleCountMismatch', ...
        'V_bus_pu has %d columns but t has %d samples.', ...
        size(state.V_bus_pu,2), n);
end

% --- IBR identity ---------------------------------------------------------
idx = state.ibr_device_indices(:)';
nd = numel(state.device_bus_ids);
if any(idx < 1 | idx > nd)
    error('ai:snapshot_from_state:badIbrIndex', ...
        'ibr_device_indices must lie in 1..%d.', nd);
end
m = numel(idx);
snap.ibr_device_indices = idx;
snap.ibr_bus_ids = state.device_bus_ids(idx);

% --- bus voltages ---------------------------------------------------------
snap.V_min_pu = min(state.V_bus_pu, [], 1);
V_ibr = nan(m, n);
for k = 1:m
    r = find(snap.bus_ids == snap.ibr_bus_ids(k), 1);
    if ~isempty(r)
        V_ibr(k, :) = state.V_bus_pu(r, :);
    end
end
snap.V_ibr_pu = V_ibr;
% The IBR buses as ROW POSITIONS: ai_escr_metrics indexes the admittance and
% the voltage matrix by position, not by bus number.
pos_ibr = arrayfun(@(b) find(snap.bus_ids == b, 1), snap.ibr_bus_ids);
snap.ibr_bus_positions = pos_ibr;

% --- RoCoF: analytic where it exists, finite difference where it does not --
if isfield(state,'rocof_Hz_s') && ~isempty(state.rocof_Hz_s)
    roc = state.rocof_Hz_s(:)';
    if numel(roc) ~= n
        error('ai:snapshot_from_state:rocofLengthMismatch', ...
            'rocof_Hz_s has %d entries but t has %d samples.', numel(roc), n);
    end
else
    roc = nan(1, n);
end
source = repmat("analytic", 1, n);
source(~isfinite(roc)) = "unavailable";
gap = ~isfinite(roc) & isfinite(snap.f_coi_Hz);
if any(gap) && n >= 2
    fd = finite_difference_rate(t, snap.f_coi_Hz);
    fillable = gap & isfinite(fd);
    roc(fillable) = fd(fillable);
    source(fillable) = "finite_difference";
end
snap.rocof_Hz_s = roc;
snap.rocof_source = source;

% --- severity: the production two-term index, kept unaggregated -----------
[snap.J_V, snap.J_f, snap.S] = severity_terms(snap, state, opts);

% --- ESCR -----------------------------------------------------------------
if isfield(state,'escr') && ~isempty(state.escr)
    if ~isequal(size(state.escr), [m n])
        error('ai:snapshot_from_state:escrSizeMismatch', ...
            'escr must be %d-by-%d, got %d-by-%d.', ...
            m, n, size(state.escr,1), size(state.escr,2));
    end
    snap.escr = state.escr;
    snap.escr_source = 'provided';
elseif isfield(state,'Y_log') && ~isempty(state.Y_log) && ...
        isfield(state,'srated_pu') && numel(state.srated_pu) == m
    topo = [];
    if isfield(state,'topology_history') && ~isempty(state.topology_history)
        topo = state.topology_history;
    end
    snap.escr = ai.ai_escr_metrics(state.Y_log, pos_ibr, ...
        state.srated_pu(:)', state.V_bus_pu, t, topo);
    snap.escr_source = 'rebuilt_from_Y_log';
else
    snap.escr = nan(m, n);
    snap.escr_source = 'unavailable';
end

% --- modes at the IBR devices --------------------------------------------
modes = repmat({''}, m, n);
dm = state.device_modes;
if size(dm,1) == nd && size(dm,2) == n
    for k = 1:m
        modes(k, :) = dm(idx(k), :);
    end
end
snap.modes_ibr = modes;

% --- identity and the healthy reference, carried through for the feature ---
if isfield(state,'device_ids')
    snap.device_ids = state.device_ids;
else
    snap.device_ids = {};
end
if isfield(state,'healthy_V') && ~isempty(state.healthy_V) && ...
        isfield(state,'healthy_bus_ids') && ~isempty(state.healthy_bus_ids)
    % abs() is enforced here, not only at the cache reader, because J_V is
    % defined on voltage MAGNITUDES. A caller that hands over a phasor would
    % otherwise get abs(V_i - V_phasor), which is a phasor distance and not a
    % voltage deviation at all, and a complex value would then reach the JSON
    % payload, where jsonencode refuses it outright.
    snap.healthy_V = abs(state.healthy_V(:));
    snap.healthy_bus_ids = state.healthy_bus_ids(:);
else
    snap.healthy_V = [];
    snap.healthy_bus_ids = [];
end

snap.offset_s = t - t(1);
end

% =========================================================================
function [J_V, J_f, S] = severity_terms(snap, state, opts)
%SEVERITY_TERMS  The production pair J_V/J_f and the scalar they saturate into.
%   J_V is per IBR bus because the voltage term is a local one; J_f is a single
%   system trace because f_COI is a single system trace
%   (docs/project/SCENARIOS.md:140). S takes the WORST device, which is the
%   same "any i" reading the engine's augment condition uses.
m = numel(snap.ibr_bus_ids);
n = snap.n;
f0 = opts.severity_f0_Hz;

J_f = abs(snap.f_coi_Hz - f0) / opts.severity_df_base_Hz;

J_V = nan(m, n);
if isfield(state,'healthy_V') && isfield(state,'healthy_bus_ids') && ...
        ~isempty(state.healthy_V)
    for k = 1:m
        r = find(state.healthy_bus_ids(:) == snap.ibr_bus_ids(k), 1);
        if ~isempty(r)
            J_V(k, :) = abs(snap.V_ibr_pu(k,:) - state.healthy_V(r)) / ...
                opts.severity_dV_base_pu;
        end
    end
    % A bus with no healthy reference is left NaN rather than compared against
    % zero, which would manufacture a severity the run never had.
    S = max(sat(0.5*J_V + 0.5*repmat(J_f, m, 1)), [], 1, 'omitnan');
    if all(isnan(S))
        S = nan(1, n);
    end
else
    % No pre-disturbance profile: severity is unavailable, not zero. Reporting
    % S = 0 would read as "nothing is wrong" and silently suppress the trigger.
    S = nan(1, n);
end
end

function y = sat(x)
y = min(1, max(0, x));
end

function rate = finite_difference_rate(t, f)
%FINITE_DIFFERENCE_RATE  df/dt on a non-uniform grid with gaps.
%   Each sample is differenced across the nearest finite samples that bracket
%   it; where only one side has data, the two nearest finite samples on that
%   side are used. Samples with no usable pair stay NaN.
n = numel(t);
rate = nan(1, n);
valid = find(isfinite(f));
if numel(valid) < 2
    return;
end
for i = 1:n
    lo = valid(valid < i);
    hi = valid(valid > i);
    if ~isempty(lo) && ~isempty(hi)
        a = lo(end); b = hi(1);
    elseif numel(lo) >= 2
        a = lo(end-1); b = lo(end);
    elseif numel(hi) >= 2
        a = hi(1); b = hi(2);
    else
        continue;
    end
    dt = t(b) - t(a);
    if dt > 0
        rate(i) = (f(b) - f(a)) / dt;
    end
end
end
