function ev = validate(ev, case_data, analysis)
%EVENTS.VALIDATE  Cheap structural validation of an event configuration.
%   EV = events.validate(EV) checks the record returned by an event file.
%   EV = events.validate(EV, CASE_DATA) additionally checks that fault_bus is
%   a real external bus ID of that case. EV = events.validate(EV, CASE_DATA,
%   ANALYSIS) also checks the target analysis.
%
%   This is the CHEAP PRE-RUN check a UI needs before it lets a user press
%   Run. It is PURE: no case loading beyond the bus list already in hand, no
%   solver call, no file write. It does NOT duplicate the runtime gates --
%   the same division wizard.validate_request.m:8-13 states for itself:
%
%     * The legal event-profile NAMES and the admissible ORDERING of a
%       sequence (including which events a profile arms at all) belong to
%       stability.ibr_event_schedule and stability.ts_prevalidate_events.
%       validate() never sorts, never clips, never relaxes.
%     * Coincident-event ambiguity belongs to
%       stability.ibr_event_schedule (tol 1e-12) and
%       ts_prevalidate_events (event_tol 1e-10). validate() does not test it.
%     * Whether a profile REQUIRES a value the user left empty (e.g.
%       profile='combined' needs sg_trip) is decided by the capability row in
%       ibr_event_schedule, so it surfaces there as
%       stability.ibr_event_schedule:missingField.
%
%   The ONE ordering inequality checked here is tripBeforeClear
%   (fault_clear <= trip), because it is the mistake every operator makes and
%   it needs no case and no capability row: a machine cannot be tripped before
%   its fault is cleared. The runtime re-derives it authoritatively.
%
%   Stability: the returned EV is the input, unchanged. Nothing is filled in,
%   reordered, or defaulted here; the derived defaults live in events.schema
%   and are read by the consumer that needs the number (events.resolve).
%
%   Stable failure IDs:
%     events:validate:badSchema            not a record / unknown field /
%                                          no bus list in case_data
%     events:validate:missingField         a required value is unset
%     events:validate:badCaseId            case_id malformed
%     events:validate:unknownFaultBus      fault_bus not an external bus ID
%     events:validate:nonPositiveDuration  ds is not a finite positive scalar
%     events:validate:badFaultTime         an event instant is malformed
%     events:validate:tripBeforeClear      trip < t_fault + ds
%     events:validate:badZf                Zf is not finite non-zero
%     events:validate:badAnalysis          analysis is not ts or ibr
%
%   See also: events.SCHEMA, events.RESOLVE, wizard.VALIDATE_REQUEST,
%   stability.IBR_EVENT_SCHEDULE, stability.TS_PREVALIDATE_EVENTS.

if nargin < 2, case_data = []; end
% Omitted means "the default analysis"; EXPLICITLY empty or unknown fails
% closed, because silently reading '' as 'ts' would hide a caller bug.
if nargin < 3, analysis = 'ts'; end
analysis = lower(char(analysis));

canonical = events.schema();

% --- schema envelope -------------------------------------------------------
if ~isstruct(ev) || ~isscalar(ev)
    error('events:validate:badSchema', ...
        'Event configuration must be one scalar struct (got %s).', class(ev));
end
if ~isfield(ev, 'schema_version') || ~is_text(ev.schema_version) || ...
        ~strcmp(char(ev.schema_version), canonical.schema_version)
    error('events:validate:badSchema', ...
        'Event configuration must start from events.schema() (schema_version "%s").', ...
        canonical.schema_version);
end
required = fieldnames(canonical);
missing = setdiff(required, fieldnames(ev));
if ~isempty(missing)
    error('events:validate:missingField', ...
        'Event configuration is missing field(s): %s.', strjoin(missing, ', '));
end
extra = setdiff(fieldnames(ev), required);
if ~isempty(extra)
    error('events:validate:badSchema', ...
        ['Unknown field(s) in the event configuration: %s.\n' ...
         'The field list is closed on purpose: a typo must fail closed ' ...
         'rather than leave the intended value unset.'], strjoin(extra, ', '));
end

% --- analysis --------------------------------------------------------------
if ~ismember(analysis, {'ts', 'ibr'})
    error('events:validate:badAnalysis', ...
        'analysis must be ''ts'' or ''ibr'' (got "%s").', analysis);
end

% --- case_id ---------------------------------------------------------------
% Structural only. The AUTHORITATIVE pairing between an event and a case is
% events.validate's own unknownFaultBus check against the loaded case's bus
% list -- an id string cannot prove the numbers belong to that network.
if ~is_text(ev.case_id)
    error('events:validate:badCaseId', ...
        'case_id must be a case identifier string (got %s).', class(ev.case_id));
end
case_id = char(ev.case_id);
if isempty(regexp(case_id, '^[a-z][a-z0-9_]*$', 'once'))
    error('events:validate:badCaseId', ...
        ['case_id must be a lowercase case identifier matching ' ...
         '[a-z][a-z0-9_]* (e.g. ''ieee14'', ''ne39''), got "%s".'], case_id);
end

% --- profile ---------------------------------------------------------------
% The set of legal names is owned by stability.ibr_event_schedule (its
% PROFILES list); restating it here would be a second authority that can
% drift. An empty profile is a missing value either way.
if ~is_text(ev.profile) || isempty(char(ev.profile))
    error('events:validate:missingField', ...
        ['profile must name an event profile; leave the events.schema ' ...
         'default ''fault_only'' for a single bus fault.']);
end

% --- notes -----------------------------------------------------------------
if ~(ischar(ev.notes) || iscellstr(ev.notes) || ...
        (isstring(ev.notes) && isvector(ev.notes)))
    error('events:validate:badSchema', ...
        'notes must be text (char or cellstr), got %s.', class(ev.notes));
end

% --- t_fault (derived default allowed) -------------------------------------
t_fault = canonical.t_fault;
if ~isempty(ev.t_fault)
    t_fault = check_instant(ev.t_fault, 't_fault');
end

% --- ds: the single authoritative duration ---------------------------------
if isempty(ev.ds)
    error('events:validate:missingField', ...
        'ds (fault duration, seconds) is not set. It is the SINGLE authoritative duration.');
end
if ~isnumeric(ev.ds) || ~isscalar(ev.ds) || ~isreal(ev.ds) || ...
        ~isfinite(ev.ds) || ev.ds <= 0
    error('events:validate:nonPositiveDuration', ...
        ['ds must be a finite positive real scalar (fault duration, seconds); ' ...
         'got %s.'], describe_value(ev.ds));
end

% --- Zf --------------------------------------------------------------------
if isempty(ev.Zf)
    error('events:validate:missingField', 'Zf (fault impedance, pu) is not set.');
end
if ~isnumeric(ev.Zf) || ~isscalar(ev.Zf) || ~isfinite(ev.Zf) || abs(ev.Zf) < eps
    error('events:validate:badZf', ...
        ['Zf must be a finite non-zero scalar impedance in pu ' ...
         '(e.g. 1i*0.1); got %s.'], describe_value(ev.Zf));
end

% --- fault_bus -------------------------------------------------------------
if isempty(ev.fault_bus)
    error('events:validate:missingField', 'fault_bus (external bus ID) is not set.');
end
if ~isnumeric(ev.fault_bus) || ~isscalar(ev.fault_bus) || ...
        ~isreal(ev.fault_bus) || ~isfinite(ev.fault_bus) || ...
        ev.fault_bus <= 0 || ev.fault_bus ~= fix(ev.fault_bus)
    error('events:validate:unknownFaultBus', ...
        'fault_bus must be a finite positive integer external bus ID; got %s.', ...
        describe_value(ev.fault_bus));
end
if ~isempty(case_data)
    bus_ids = external_bus_ids(case_data);
    if ~any(bus_ids == ev.fault_bus)
        error('events:validate:unknownFaultBus', ...
            ['fault_bus %d is not an external bus ID of this case ' ...
             '(known IDs %g..%g, %d buses).'], ...
            ev.fault_bus, min(bus_ids), max(bus_ids), numel(bus_ids));
    end
end

% --- trip / sg_on: [] means "not armed" -----------------------------------
trip = [];
if ~isempty(ev.trip)
    trip = check_instant(ev.trip, 'trip');
end
if ~isempty(ev.sg_on)
    check_instant(ev.sg_on, 'sg_on');
end

% --- the one ordering inequality the UI must catch ------------------------
% Equality is allowed: the combined profile requires fault_clear <= sg_trip,
% and clearing exactly when the machine trips is a legal, meaningful choice.
if ~isempty(trip) && trip < t_fault + ev.ds
    error('events:validate:tripBeforeClear', ...
        ['trip (%.15g s) is before the derived fault clearing instant ' ...
         't_fault + ds = %.15g + %.15g = %.15g s. A machine cannot be ' ...
         'tripped before its fault is cleared.'], ...
        trip, t_fault, ev.ds, t_fault + ev.ds);
end
end

% =========================================================================
function v = check_instant(v, field)
% An event instant: finite real nonnegative scalar. [] is "not armed" and is
% handled by the caller, never here.
if ~isnumeric(v) || ~isscalar(v) || ~isreal(v) || ~isfinite(v) || v < 0
    error('events:validate:badFaultTime', ...
        '%s must be a finite real nonnegative instant in seconds; got %s.', ...
        field, describe_value(v));
end
end

function ids = external_bus_ids(case_data)
% The external bus IDs of a loaded case, in either case convention ts_simulate
% accepts (MATPOWER-style .mpc, Kundur-style .bus_data). No case is loaded
% here -- the caller already holds it.
if ~isstruct(case_data) || ~isscalar(case_data)
    error('events:validate:badSchema', ...
        'case_data must be one scalar struct (got %s).', class(case_data));
end
if isfield(case_data, 'mpc') && isfield(case_data.mpc, 'bus') && ~isempty(case_data.mpc.bus)
    ids = case_data.mpc.bus(:, 1);
elseif isfield(case_data, 'bus_data') && ~isempty(case_data.bus_data)
    ids = case_data.bus_data(:, 1);
else
    error('events:validate:badSchema', ...
        ['case_data exposes no bus list (.mpc.bus or .bus_data), so fault_bus ' ...
         'cannot be checked against this case.']);
end
end

function tf = is_text(v)
tf = ischar(v) || (isstring(v) && isscalar(v));
end

function s = describe_value(v)
if isempty(v)
    s = '[]';
elseif isnumeric(v) && isscalar(v)
    if isreal(v), s = sprintf('%.15g', v);
    else, s = sprintf('%.15g%+.15gj', real(v), imag(v)); end
else
    s = sprintf('<%s %s>', class(v), mat2str(size(v)));
end
end
