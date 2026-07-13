function events_new = ts_transitions_from_legacy(events_old, t_span)
%TS_TRANSITIONS_FROM_LEGACY  Adapt legacy fault events to the generic transitions list (Phase 2).
%   events_new = ts_transitions_from_legacy(events_old, t_span) converts the
%   Track A B3 legacy events struct (fault_enabled, t_fault, t_clear, Ypre,
%   Yfault, Ypost) into the generic events.transitions list + events.topologies
%   map. The conversion is BIT-IDENTICAL: the topology_id strings map directly
%   to the SAME Y matrices, and the transition times are the SAME t_fault/
%   t_clear. No algebraic solve logic changes.
%
%   Legacy mapping (frozen, B3-compatible):
%     fault_on  -> time=t_fault, order=1, topology_id='fault'
%     fault_off -> time=t_clear, order=1, topology_id='post'
%     events.topologies = struct('pre',Ypre,'fault',Yfault,'post',Ypost)
%
%   If fault_enabled is false or t_fault/t_clear are outside t_span, the
%   transitions list is empty (no events). The legacy fields (fault_enabled,
%   t_fault, t_clear, Ypre, Yfault, Ypost) are PRESERVED for backward-compat
%   with any caller that still reads them.
%
%   Source: project Phase 2 design. PROJECT_DERIVED adapter; the underlying
%   fault-on/off convention is Sauer-Pai §6.7 (slack V specified, KCL replaced)
%   via Track A B3. No new numerical behavior — purely a schema wrapping.

arguments
    events_old struct
    t_span (1,2) double
end

t0 = t_span(1); t_end = t_span(2);

% Preserve legacy fields (backward-compat: callers may still read them).
events_new = events_old;
events_new.guards = [];
events_new.transitions = struct([]);
events_new.topologies = struct();

% Populate topologies from legacy Y fields (if present).
if isfield(events_old, 'Ypre') && ~isempty(events_old.Ypre)
    events_new.topologies.pre = events_old.Ypre;
end
if isfield(events_old, 'Yfault') && ~isempty(events_old.Yfault)
    events_new.topologies.fault = events_old.Yfault;
end
if isfield(events_old, 'Ypost') && ~isempty(events_old.Ypost)
    events_new.topologies.post = events_old.Ypost;
end

fault_enabled = isfield(events_old, 'fault_enabled') && events_old.fault_enabled;
if ~fault_enabled
    return;
end

transitions = repmat(struct('event_id', "", 'time', NaN, 'order', 0, ...
    'topology_id', "", 'atomic_updates', struct(), 'hybrid_commit', ...
    struct(), 'source', 'legacy_adapter'), 0, 1);

if isfield(events_old, 't_fault') && isfinite(events_old.t_fault) && ...
   events_old.t_fault > t0 && events_old.t_fault < t_end
    tr = struct('event_id', "fault_on", 'time', events_old.t_fault, ...
        'order', 1, 'topology_id', "fault", ...
        'atomic_updates', struct('Y_update', events_old.Yfault), ...
        'hybrid_commit', struct(), 'source', 'legacy_adapter');
    transitions = [transitions; tr]; %#ok<AGROW>
end

if isfield(events_old, 't_clear') && isfinite(events_old.t_clear) && ...
   events_old.t_clear > t0 && events_old.t_clear < t_end
    tr = struct('event_id', "fault_off", 'time', events_old.t_clear, ...
        'order', 1, 'topology_id', "post", ...
        'atomic_updates', struct('Y_update', events_old.Ypost), ...
        'hybrid_commit', struct(), 'source', 'legacy_adapter');
    transitions = [transitions; tr]; %#ok<AGROW>
end

events_new.transitions = transitions;
end
