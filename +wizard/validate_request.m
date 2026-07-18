function req = validate_request(req)
%VALIDATE_REQUEST  Pure validation of a wizard request struct.
%   req = wizard.validate_request(req) validates the request in place and
%   returns it (unchanged on success). Throws with stable failure IDs on
%   schema, compatibility, or event-contract violations.
%
%   This function is PURE: no UI, no case loading, no solver invocation. It
%   performs STRUCTURAL and TIME-RANGE validation only. Full event-target
%   resolution (bus/resource/device identity, atomic transaction semantics)
%   is delegated to the production validators at dispatch time
%   (stability.ts_prevalidate_events, stability.ibr_event_schedule) — the
%   wizard must NOT duplicate that logic. This pre-check catches cheap
%   contract violations before the user clicks Run.
%
%   Stable failure IDs:
%     wizard:validate_request:badSchema
%     wizard:validate_request:unknownAnalysis
%     wizard:validate_request:unknownCase
%     wizard:validate_request:eventsNotApplicable
%     wizard:validate_request:badEventStruct
%     wizard:validate_request:badEventOrdering
%     wizard:validate_request:eventOutOfRange
%
%   Correction #6: events_policy='event_free' must reach the production
%   TS/IBR runtime as an ACTUALLY empty schedule. validate_request does NOT
%   synthesize or hide canonical events; it only confirms the user's explicit
%   event-free choice and leaves events=[] for dispatch to pass through.
%
%   See also: wizard.BUILD_REQUEST, wizard.DISPATCH_ANALYSIS.

% --- schema ---
if ~isstruct(req)
    error('wizard:validate_request:badSchema', 'Request must be a struct.');
end
required = {'analysis','case_id','options','events','events_policy','interactive','schema_version'};
missing = setdiff(required, fieldnames(req));
if ~isempty(missing)
    error('wizard:validate_request:badSchema', ...
        'Request missing fields: %s.', strjoin(missing, ','));
end
if ~strcmp(req.schema_version, 'wizard_request_v1')
    error('wizard:validate_request:badSchema', ...
        'Unsupported schema_version %s.', req.schema_version);
end

% --- analysis ID ---
registry = wizard.analysis_registry();
aidx = find(strcmp(req.analysis, {registry.id}), 1);
if isempty(aidx)
    % Preserve the original solve_case error identifier (characterization gate).
    error('solve_case:analysis', 'Unknown analysis %s.', req.analysis);
end
analysis_meta = registry(aidx);

% IBR is a resource family, while ibr_analysis selects the requested
% analysis product.  Keep 'ts' as the backward-compatible default used by
% every pre-submenu request.
if strcmp(req.analysis, 'ibr')
    if ~isfield(req.options, 'ibr_analysis') || isempty(req.options.ibr_analysis)
        req.options.ibr_analysis = 'ts';
    end
    if ~(ischar(req.options.ibr_analysis) || ...
            (isstring(req.options.ibr_analysis) && isscalar(req.options.ibr_analysis)))
        error('wizard:validate_request:badIbrAnalysis', ...
            'options.ibr_analysis must be pf, sssa, ts, or full.');
    end
    req.options.ibr_analysis = lower(char(req.options.ibr_analysis));
    if ~ismember(req.options.ibr_analysis, {'pf','sssa','ts','full'})
        error('wizard:validate_request:badIbrAnalysis', ...
            'Unknown IBR analysis %s.', req.options.ibr_analysis);
    end
    if isfield(req.options, 'ibr_profile') && ~isempty(req.options.ibr_profile)
        if ~(ischar(req.options.ibr_profile) || ...
                (isstring(req.options.ibr_profile) && isscalar(req.options.ibr_profile)))
            error('wizard:validate_request:badIbrProfile', ...
                'options.ibr_profile must be legacy or rms10_profile_b.');
        end
        req.options.ibr_profile = lower(char(req.options.ibr_profile));
        if ~ismember(req.options.ibr_profile, {'legacy','rms10_profile_b'})
            error('wizard:validate_request:badIbrProfile', ...
                'Unknown IBR profile %s.', req.options.ibr_profile);
        end
    end
end

% --- case ID ---
entries = wizard.discover_cases(req.analysis);
if ~any(strcmp(req.case_id, {entries.id}))
    % Preserve the original solve_case error identifier (characterization gate).
    error('solve_case:case', 'Case %s not supported for %s.', req.case_id, req.analysis);
end

% --- events policy vs analysis applicability ---
switch req.events_policy
    case 'not_applicable'
        if analysis_meta.events_applicable
            error('wizard:validate_request:eventsNotApplicable', ...
                'Analysis %s supports events; use event_free or configured.', req.analysis);
        end
        if ~isempty(req.events)
            error('wizard:validate_request:eventsNotApplicable', ...
                'Analysis %s must not carry an event struct.', req.analysis);
        end
    case 'event_free'
        if ~analysis_meta.events_applicable
            error('wizard:validate_request:eventsNotApplicable', ...
                'Analysis %s does not support events; use not_applicable.', req.analysis);
        end
        % event_free => events must carry no enabled/hidden canonical events.
        % A disabled event struct is allowed: it reaches the production
        % runtime as the empty-schedule sentinel (correction #6). An empty
        % events value is also allowed (TS path; no event fields attached).
        if ~isempty(req.events)
            if ~(isstruct(req.events) && isfield(req.events, 'enabled') ...
                    && ~logical(req.events.enabled))
                error('wizard:validate_request:badEventStruct', ...
                    'event_free policy requires an empty or disabled event struct.');
            end
        end
    case 'configured'
        if ~analysis_meta.events_applicable
            error('wizard:validate_request:eventsNotApplicable', ...
                'Analysis %s does not support events; use not_applicable.', req.analysis);
        end
        validate_event_struct(req);
    otherwise
        error('wizard:validate_request:badSchema', ...
            'Unknown events_policy %s.', req.events_policy);
end

% PF and SSSA are operating-point analyses.  They cannot consume a hidden
% time-domain event merely because the top-level IBR family supports events.
if strcmp(req.analysis, 'ibr') && ...
        ismember(req.options.ibr_analysis, {'pf','sssa'}) && ...
        strcmp(req.events_policy, 'configured')
    error('wizard:validate_request:ibrEventsNotApplicable', ...
        'IBR %s does not accept events; select TS or Full Analysis.', ...
        upper(req.options.ibr_analysis));
end
end

function validate_event_struct(req)
% Structural + time-range validation only. Target resolution is deferred to
% the production validators at dispatch (correction #6: do not hide events
% at the UI layer; pass through and let the runtime validate fully).
ev = req.events;
if ~isstruct(ev) || isempty(ev)
    error('wizard:validate_request:badEventStruct', ...
        'Configured events must be a non-empty struct.');
end
required_fields = {'enabled'};
missing = setdiff(required_fields, fieldnames(ev));
if ~isempty(missing)
    error('wizard:validate_request:badEventStruct', ...
        'Event struct missing fields: %s.', strjoin(missing, ','));
end
if ~islogical(ev.enabled) && ~(isnumeric(ev.enabled) && isscalar(ev.enabled))
    error('wizard:validate_request:badEventStruct', ...
        'events.enabled must be a logical scalar.');
end

% When disabled, the runtime treats it as an empty schedule (event_free).
% No further structural checks needed; dispatch passes it through.
if ~logical(ev.enabled)
    return;
end

% Enabled IBR/TS events: time-range and ordering checks (cheap, no case load).
opt = req.options;
if isfield(opt, 't_end')
    t_end = opt.t_end;
else
    t_end = Inf;  % cannot bound without t_end; defer to runtime
end

times = struct();
time_fields = {'fault_on','fault_clear','sg_trip','sg_on'};
for k = 1:numel(time_fields)
    f = time_fields{k};
    if isfield(ev, f)
        v = ev.(f);
        if ~(isnumeric(v) && isscalar(v) && isfinite(v))
            error('wizard:validate_request:badEventStruct', ...
                'events.%s must be a finite scalar.', f);
        end
        if v < 0 || v > t_end
            error('wizard:validate_request:eventOutOfRange', ...
                'events.%s = %g is outside [0, t_end=%g].', f, v, t_end);
        end
        times.(f) = v;
    end
end

% Ordering: fault_on < fault_clear <= sg_trip < sg_on <= t_end (IBR contract).
if isfield(times,'fault_on') && isfield(times,'fault_clear') ...
        && ~(times.fault_on < times.fault_clear)
    error('wizard:validate_request:badEventOrdering', ...
        'Require fault_on < fault_clear.');
end
if isfield(times,'fault_clear') && isfield(times,'sg_trip') ...
        && ~(times.fault_clear <= times.sg_trip)
    error('wizard:validate_request:badEventOrdering', ...
        'Require fault_clear <= sg_trip.');
end
if isfield(times,'sg_trip') && isfield(times,'sg_on') ...
        && ~(times.sg_trip < times.sg_on)
    error('wizard:validate_request:badEventOrdering', ...
        'Require sg_trip < sg_on.');
end
% Coincident events within the frozen tolerance are rejected by the production
% ts_prevalidate_events gate (ts_event_transition:ambiguousCoincident). The
% wizard does not duplicate that check here; it only checks strict ordering.
end
