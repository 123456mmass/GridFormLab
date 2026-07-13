function event_times = ts_prevalidate_events(events, t_span, event_tol)
%TS_PREVALIDATE_EVENTS  Prevalidate event times before stepping (B3).
%   Returns the sorted unique event times within T_SPAN, after checking
%   that no two declared event times are coincident within EVENT_TOL.
%   Coincident events (e.g. t_fault == t_clear) fail closed with
%   ts_event_transition:ambiguousCoincident — there is no deterministic
%   single transition to apply. Ordered multi-event semantics are deferred
%   to separately approved case-schema work; this correction assumes at
%   most ONE transition per event time.
%
%   EVENT_TOL is a FROZEN absolute tolerance (1e-10), independent of any
%   local step-size dt. It is used identically by fixed and adaptive
%   paths (passed explicitly to ts_event_transition).
%
%   Source: project B3 design (docs/project/plans/ibr_interface_foundation.md).

arguments
    events struct
    t_span (1,2) double
    event_tol (1,1) double
end

t0 = t_span(1); t_end = t_span(2);
event_times = [];
if isfield(events,'fault_enabled') && events.fault_enabled
    if isfield(events,'t_fault') && isfinite(events.t_fault) && ...
       events.t_fault > t0 && events.t_fault < t_end
        event_times = [event_times; events.t_fault];
    end
    if isfield(events,'t_clear') && isfinite(events.t_clear) && ...
       events.t_clear > t0 && events.t_clear < t_end
        event_times = [event_times; events.t_clear];
    end
end

% Coincident-event prevalidation: any pair within event_tol => fail closed.
% Check BEFORE unique() (unique would merge t_fault==t_clear into one,
% hiding the coincidence). Ordered multi-event semantics are deferred.
ne = numel(event_times);
for i = 1:ne-1
    for j = i+1:ne
        if abs(event_times(j) - event_times(i)) <= event_tol
            error('ts_event_transition:ambiguousCoincident', ...
                ['Coincident event times %.10g and %.10g within event_tol=%.2e. ' ...
                 'No deterministic single transition; ordered multi-event semantics ' ...
                 'are deferred to separately approved case-schema work.'], ...
                event_times(i), event_times(j), event_tol);
        end
    end
end
event_times = sort(unique(event_times));
end
