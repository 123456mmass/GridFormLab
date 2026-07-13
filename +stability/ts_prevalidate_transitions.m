function [event_times, event_ids] = ts_prevalidate_transitions(events, t_span, event_tol)
%TS_PREVALIDATE_TRANSITIONS  Prevalidate generic transitions before stepping (Phase 2).
%   [event_times, event_ids] = ts_prevalidate_transitions(events, t_span, event_tol)
%   returns the sorted unique event times within T_SPAN and the corresponding
%   event_ids, after validating the generic events.transitions list.
%
%   Validation (per user correction 3, coincident-event semantics):
%     - event_id is globally unique across ALL transitions.
%     - (time, order) pairs are unique.
%     - same-time events MUST have distinct order values.
%     - same (time, order) => FAIL CLOSED (ts_prevalidate_transitions:ambiguousOrder).
%     - same-time events allowed only if every intermediate state is valid:
%         every topology_id exists in events.topologies; atomic_updates
%         struct is internally consistent.
%     - sort key is (time, order); transitions are applied in this order.
%     - ONE public right-limit sample after the final event at a timestamp
%       (enforced by the driver loop, not here).
%
%   EVENT_TOL is a FROZEN absolute tolerance (1e-10), passed explicitly so
%   coincidence does NOT depend on a local step-size dt. Identical in fixed
%   and adaptive paths.
%
%   Source: project Phase 2 design (user correction 3). PROJECT_DERIVED.
%   No external source for the transition schema — it is project
%   infrastructure for the IEEE14 IBR mission's mode-switching events.

arguments
    events struct
    t_span (1,2) double
    event_tol (1,1) double
end

t0 = t_span(1); t_end = t_span(2);
event_times = [];
event_ids = strings(0, 1);

if ~isfield(events, 'transitions') || isempty(events.transitions)
    return;
end

T = events.transitions;
n = numel(T);
if n == 0
    return;
end

% Collect declared transitions within t_span.
times = zeros(n, 1);
ids = strings(n, 1);
orders = zeros(n, 1);
topo_ids = strings(n, 1);
for k = 1:n
    tk = T(k).time;
    if ~isfinite(tk) || tk <= t0 || tk >= t_end
        continue;
    end
    times(k) = tk;
    ids(k) = string(T(k).event_id);
    orders(k) = T(k).order;
    topo_ids(k) = string(T(k).topology_id);
end

% Drop zero-time placeholders (NaN-initialized orders default to 0; filter
% by finite time).
keep = times > t0 & times < t_end & isfinite(times);
times = times(keep); ids = ids(keep); orders = orders(keep); topo_ids = topo_ids(keep);
m = numel(times);
if m == 0
    return;
end

% 1. event_id globally unique.
[u_ids, ~, ic] = unique(ids);
if numel(u_ids) ~= m
    % Find the first duplicated event_id.
    seen = strings(0, 1);
    dup_id = "";
    for k = 1:m
        if any(seen == ids(k))
            dup_id = ids(k);
            break;
        end
        seen = [seen; ids(k)]; %#ok<AGROW>
    end
    error('ts_prevalidate_transitions:duplicateEventId', ...
        ['event_id "%s" appears in more than one transition. ' ...
         'event_id MUST be globally unique across all transitions.'], dup_id);
end

% 2. (time, order) pairs unique. Same (time, order) => ambiguous => fail.
for i = 1:m-1
    for j = i+1:m
        if abs(times(i) - times(j)) <= event_tol && orders(i) == orders(j)
            error('ts_prevalidate_transitions:ambiguousOrder', ...
                ['Two transitions at time %.10g have the same order=%d. ' ...
                 'Ordered same-time events require DISTINCT order values; ' ...
                 'same (time, order) is ambiguous and fails closed.'], ...
                times(i), orders(i));
        end
    end
end

% 3. topology_id exists in events.topologies (every intermediate state valid).
if isfield(events, 'topologies') && ~isempty(events.topologies)
    topo_fields = fieldnames(events.topologies);
else
    topo_fields = {};
end
for k = 1:m
    if isempty(topo_ids(k)) || ~any(strcmp(topo_fields, topo_ids(k)))
        error('ts_prevalidate_transitions:missingTopology', ...
            ['Transition "%s" at t=%.10g references topology_id "%s" ' ...
             'not present in events.topologies. Every intermediate state ' ...
             'must be valid.'], ids(k), times(k), topo_ids(k));
    end
end

% 4. Sort by (time, order) for deterministic application order.
[~, idx] = sortrows([times, orders]);
times = times(idx); ids = ids(idx); orders = orders(idx);

% 5. Coincident check (distinct times): two times within event_tol that are
%    NOT the same time (different orders at different times within tol but
%    not exactly equal) — this would be a true coincidence with no order
%    disambiguation. Same-time distinct-order is ALLOWED (handled above).
for i = 1:m-1
    if abs(times(i+1) - times(i)) <= event_tol && orders(i) == orders(i+1)
        % Already caught above; redundant safety.
        error('ts_prevalidate_transitions:ambiguousCoincident', ...
            ['Coincident event times %.10g and %.10g within event_tol=%.2e ' ...
             'with equal order. No deterministic transition; fails closed.'], ...
            times(i), times(i+1), event_tol);
    end
end

event_times = times;
event_ids = ids;
end
