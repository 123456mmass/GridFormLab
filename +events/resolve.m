function opt = resolve(ev, case_data, opt)
%EVENTS.RESOLVE  Fold one event configuration into a launcher option struct.
%   OPT = events.resolve(EV, CASE_DATA, OPT) validates EV, derives the
%   fault-clearing instant from the single authoritative duration EV.ds, and
%   writes the fields the production launchers actually read. It is the ONLY
%   place an event file touches the engine.
%
%   THE ABI IT HITS (read from the code, not assumed):
%
%   OPT.analysis == 'ts' -> stability.ts_simulate
%     ts_simulate.m:23-29 declares the option defaults
%       'fault_bus', [] | 't_fault', 1.0 | 't_clear', 1.1 | 'Zf', 1i*0.1 |
%       'fault_enabled', true
%     and consumes them at ts_simulate.m:250-252 (Yfault + 1/Zf),
%     ts_simulate.m:351 (fault window in the topology selector) and
%     ts_simulate.m:364 (event echo). So:
%       opt.fault_enabled = true
%       opt.fault_bus     = ev.fault_bus
%       opt.t_fault       = t_fault       (ev.t_fault, or the schema default)
%       opt.t_clear       = t_fault + ev.ds           <- DERIVED, never stored
%       opt.Zf            = ev.Zf
%     ts_simulate has no trip time: a machine trip is an IBR/chronology event.
%
%   OPT.analysis == 'ibr' -> stability.ibr_event_schedule
%     ibr_event_schedule.m:7-9 documents the struct, and :110-125 / :236-285
%     / :315-328 consume it. Field names are the SCHEDULE's, which differ
%     from the ts_simulate names -- the schedule says fault_on / fault_clear,
%     not t_fault / t_clear, and event_profile, not profile:
%       opt.ibr_events.enabled       = true
%       opt.ibr_events.fault_bus     = ev.fault_bus
%       opt.ibr_events.Zf            = ev.Zf
%       opt.ibr_events.fault_on      = t_fault
%       opt.ibr_events.fault_clear   = t_fault + ev.ds   <- DERIVED
%       opt.ibr_events.event_profile = ev.profile
%       opt.ibr_events.sg_trip       = ev.trip   (only when armed)
%       opt.ibr_events.sg_on         = ev.sg_on  (only when armed)
%     The profile's capability row decides whether sg_trip/sg_on are ARMED
%     (ibr_event_schedule.m:164-196); a profile that does not arm them simply
%     does not read them. resolve does not pre-empt that decision, and does
%     not choose selected_gfm_indices/reference_resource_index: automatic
%     selection is the schedule's default (ibr_event_schedule.m:209-224).
%
%   WHAT IT MUST NOT DO. resolve never clips, sorts, rounds, or relaxes a
%   value. Ordering and coincident-event ambiguity have exactly one authority
%   -- stability.ibr_event_schedule.m:56-62 and stability.ts_prevalidate_events
%   -- so a value the user typed reaches the runtime unmodified and either
%   runs or fails closed there by name.
%
%   Failure IDs are events.validate's (resolve calls it first).
%
%   See also: events.SCHEMA, events.VALIDATE, stability.TS_SIMULATE,
%   stability.IBR_EVENT_SCHEDULE, wizard.DISPATCH_ANALYSIS.

if nargin < 2, case_data = []; end
if nargin < 3, opt = struct(); end
if ~isstruct(opt) || ~isscalar(opt)
    error('events:resolve:badOptions', ...
        'opt must be one scalar struct (got %s).', class(opt));
end

analysis = 'ts';
if isfield(opt, 'analysis') && ~isempty(opt.analysis)
    analysis = lower(char(opt.analysis));
end

% Fail closed before anything is written into opt.
ev = events.validate(ev, case_data, analysis);

% The derived default lives in events.schema (ONE authority); resolve only
% reads it. [] is "take the default", not "zero".
canonical = events.schema();
if isempty(ev.t_fault)
    t_fault = canonical.t_fault;
else
    t_fault = ev.t_fault;
end

% The single authoritative duration. t_clear is DERIVED here and never
% stored, so one edit to ev.ds moves the whole disturbance length. The
% addition is written out literally so the caller can assert it exactly.
t_clear = t_fault + ev.ds;

switch analysis
    case 'ts'
        opt.fault_enabled = true;
        opt.fault_bus = ev.fault_bus;
        opt.t_fault = t_fault;
        opt.t_clear = t_clear;
        opt.Zf = ev.Zf;
    case 'ibr'
        ibr_events = struct( ...
            'enabled', true, ...
            'fault_bus', ev.fault_bus, ...
            'Zf', ev.Zf, ...
            'fault_on', t_fault, ...
            'fault_clear', t_clear, ...
            'event_profile', char(ev.profile));
        % [] means "this event is not armed"; absent and [] are the same
        % thing to ibr_event_schedule, and absent is the clearer signal.
        if ~isempty(ev.trip)
            ibr_events.sg_trip = ev.trip;
        end
        if ~isempty(ev.sg_on)
            ibr_events.sg_on = ev.sg_on;
        end
        opt.ibr_events = ibr_events;
end
end
