function escr = ai_escr_metrics(Ylog, bus_positions, srated_pu, V_bus_pu, t, topology)
%AI_ESCR_METRICS  Local effective short-circuit ratio per IBR bus, per sample.
%
%   ESCR = ai.ai_escr_metrics(YLOG, BUS_POSITIONS, SRATED_PU, V_BUS_PU, T)
%   ESCR = ai.ai_escr_metrics(..., TOPOLOGY)
%
%   ESCR_i(t) = |V_i(t)|^2 / ( |Z_th,ii(t)| * S_rated,i )
%   Z_th,ii   = [Y(t)\e_i]_i , with Y taken from the topology in force at t.
%
%   YLOG  - struct array with fields t, topology, Y. This is the LIVE admittance
%           log built inside +stability/ts_simulate_ibr_hybrid.m:100-103 and
%           consumed in-process at :1481 by agsi_reference_terms. It is NOT a
%           cache's result.Y_log: that field is assigned samples.topology at
%           :1381 and therefore holds topology LABEL STRINGS, one per sample,
%           with no matrix to index. Passing a cache's result.Y_log here is an
%           error, not a rebuild. A caller holding only a cache must use
%           result.agsi_reference.scr, which the run that owned the live Y
%           already published, or rebuild Y from the case.
%   T     - 1-by-n sample times.
%   V_BUS_PU - nb-by-n bus voltage magnitudes, a cache's
%           result.bus_voltage_magnitude.
%   SRATED_PU - 1-by-m converter ratings ON THE SYSTEM BASE.
%   TOPOLOGY - optional 1-by-n cellstr/string of topology labels. When given,
%           a sample is matched to the logged Y carrying the SAME label, which
%           keeps a left/right sample pair on the correct side of an atomic
%           topology transaction. When omitted, only the time rule is used.
%
%   Returns an m-by-n matrix. A bus whose solve fails, or whose rating is not
%   finite and positive, returns NaN for that sample -- never 0, which would
%   read as "infinitely strong grid" and invert the selection rule.
%
%   RELATION TO +stability/agsi_reference_terms.m
%   That function publishes exactly this quantity as out.scr (:209-216). It is
%   not callable from a cache, because it needs the live dae and settings
%   structs. This is the rebuild path, used only when a cache predates
%   result.agsi_reference; ai.snapshot_from_cache prefers the stored values.
%
%   STATUS. The production SCR GATE classifies the full-state IBR families
%   'not_applicable_full_state_source_model' and admits them WITHOUT consulting
%   SCR (+stability/ibr_scr_metrics.m:266-292). Nothing here changes that. The
%   number returned is a grid-strength diagnostic, not gate evidence, and must
%   not be cited as gate evidence.

arguments
    Ylog struct
    bus_positions (1,:) double {mustBePositive, mustBeInteger}
    srated_pu (1,:) double {mustBePositive}
    V_bus_pu (:,:) double {mustBeReal}
    t (1,:) double {mustBeReal}
    topology = []
end

m = numel(bus_positions);
if numel(srated_pu) ~= m
    error('ai:ai_escr_metrics:ratingCountMismatch', ...
        'Got %d bus positions but %d ratings; they must correspond one to one.', ...
        m, numel(srated_pu));
end
n = numel(t);
if size(V_bus_pu, 2) ~= n
    error('ai:ai_escr_metrics:sampleCountMismatch', ...
        ['V_BUS_PU has %d columns but T has %d samples. The bus-voltage ' ...
         'matrix must be nb-by-numel(T).'], size(V_bus_pu, 2), n);
end

escr = nan(m, n);
if isempty(Ylog) || n == 0
    return;
end

% Topology labels, when supplied, are matched exactly.
have_labels = ~isempty(topology) && numel(topology) == n;
if have_labels
    top_str = string(topology);
    top_str = top_str(:)';
else
    top_str = strings(1, n);
end
ylog_top = string({Ylog.topology});
yt = [Ylog.t];

% One Thevenin diagonal solve per DISTINCT logged topology, not per sample: the
% same Y repeats for every sample inside a topology span.
zth = nan(m, numel(Ylog));
solved = false(1, numel(Ylog));

for i = 1:n
    q = applicable_entry(yt, ylog_top, top_str(i), t(i), have_labels);
    if q == 0
        continue;
    end
    if ~solved(q)
        zth(:, q) = thevenin_diagonal(Ylog(q).Y, bus_positions);
        solved(q) = true;
    end
    for k = 1:m
        bp = bus_positions(k);
        zk = zth(k, q);
        if ~isfinite(zk) || zk <= 0
            continue;
        end
        Vm = V_bus_pu(bp, i);
        if ~isfinite(Vm)
            continue;
        end
        escr(k, i) = (Vm^2) / (zk * srated_pu(k));
    end
end
end

% =========================================================================
% RELATION TO ai.miescr_metrics
% =========================================================================
% This function is the SINGLE-INFEED ratio S_sc/S_rated. ai.miescr_metrics
% called with no sources stamped returns the same quantity, and
% tests/test_ai_supervisor_contract.m pins the two against each other on a
% shared closed form rather than asserting they agree. The multi-infeed ratio
% -- where each converter's own voltage support lowers its Thevenin and the
% other converters load it -- is ai.miescr_metrics, which this function does
% not compute. Neither number is gate evidence.

% =========================================================================
function q = applicable_entry(yt, ylog_top, top_label, tsample, have_labels)
%APPLICABLE_ENTRY  Index of the logged admittance in force at TSAMPLE.
%   With labels, the latest entry carrying the same label at or before the
%   sample. Without, the latest entry at or before the sample; if the sample
%   precedes every entry, the first entry is used so an early sample is still
%   described by a real topology rather than silently dropped.
q = 0;
best = -inf;
for k = 1:numel(yt)
    if have_labels && ylog_top(k) ~= top_label
        continue;
    end
    if yt(k) <= tsample + 1e-12 && yt(k) > best
        best = yt(k);
        q = k;
    end
end
if q == 0
    for k = 1:numel(yt)
        if have_labels && ylog_top(k) ~= top_label
            continue;
        end
        q = k;
        return;
    end
end
end

function z = thevenin_diagonal(Y, bus_positions)
%THEVENIN_DIAGONAL  |Z_th,ii| at the requested buses, one linear solve each.
%   A singular or badly scaled Y leaves that entry NaN; the caller turns NaN
%   into NaN output rather than a substituted value.
n = size(Y, 1);
z = nan(1, numel(bus_positions));
if n == 0
    return;
end
for k = 1:numel(bus_positions)
    bp = bus_positions(k);
    if ~isscalar(bp) || bp < 1 || bp > n
        continue;
    end
    e = zeros(n, 1);
    e(bp) = 1;
    try
        zc = Y \ e;
    catch
        continue;
    end
    if all(isfinite(zc))
        z(k) = abs(zc(bp));
    end
end
end
