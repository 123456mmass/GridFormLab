function ev = schema()
%EVENTS.SCHEMA  Canonical event-config struct, with its derived defaults.
%   EV = events.schema() returns the empty event-configuration record that
%   every file under <root>/events/evt_*.m starts from. The hand-editable
%   convention is:
%
%       ev = events.schema();
%       ev.case_id   = 'ieee14';   % which case this event belongs to
%       ev.fault_bus = 4;          % external bus ID of the faulted bus
%       ev.ds        = 0.10;       % FAULT DURATION, seconds  <- authoritative
%       ev.trip      = [];         % machine trip time, [] = none
%       ev.Zf        = 1i*0.1;     % fault impedance, pu
%
%   THE SINGLE AUTHORITATIVE DURATION IS ev.ds. The fault-clearing instant is
%   NEVER stored: it is always DERIVED as t_fault + ds (see events.resolve).
%   One edit therefore changes the whole disturbance length, and the ordering
%   fault_on < fault_clear <= sg_trip < sg_on is either preserved or it fails
%   closed -- a stored fault_clear could silently disagree with ds.
%
%   Derived defaults (leave the value [] to take the default):
%     t_fault   1.0 s   PROJECT_DERIVED: fault inception one second into the
%                       catalogue's 15 s TS horizon. Recorded here so the
%                       default lives in ONE place, not in every event file
%                       and not inside the resolver.
%     profile   'fault_only'
%   The four values the user is expected to edit (case_id, fault_bus, ds, Zf)
%   have NO default: [] means "not configured" and events.validate fails
%   closed with events:validate:missingField. trip and sg_on use [] to mean
%   "this event is not armed", which is a value, not a missing value.
%
%   profile names a capability row in stability.ibr_event_schedule, which
%   owns the admissible ordering and the list of legal profile names. This
%   file does NOT restate that list (one authority per contract).
%
%   Field list is closed: events.validate rejects any field that is not named
%   here, so a typo (ev.faultbus = 16) fails closed instead of silently
%   leaving fault_bus unset.
%
%   See also: events.LOAD, events.VALIDATE, events.RESOLVE, events.LIST,
%   stability.ibr_event_schedule, stability.ts_simulate.

ev = struct( ...
    'schema_version', 'events_config/1.0', ...
    ...% --- the four (plus case_id) values the user edits -------------------
    'case_id',   '', ...
    'fault_bus', [], ...
    'ds',        [], ...
    'trip',      [], ...
    'Zf',        [], ...
    ...% --- advanced: [] takes the derived default --------------------------
    't_fault',   1.0, ...
    'sg_on',     [], ...
    'profile',   'fault_only', ...
    'notes',     {{}});
end
