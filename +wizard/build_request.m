function req = build_request(analysis_id, case_id, varargin)
%BUILD_REQUEST  Pure builder: selections -> unvalidated request struct.
%   req = wizard.build_request(analysis_id, case_id) builds a minimal request
%   for the given analysis and case using defaults.
%   req = wizard.build_request(..., 'options', opt) merges user options.
%   req = wizard.build_request(..., 'events', ev) attaches an event spec
%   (TS/IBR only; for PF/SSSA events are NOT_APPLICABLE).
%   req = wizard.build_request(..., 'interactive', true) marks the request
%   as interactive (the wizard UI path); partial calls open the wizard with
%   supplied selections pre-populated and NEVER auto-execute (correction #3).
%
%   This function is PURE: it performs NO validation, NO case loading, and NO
%   solver invocation. It only assembles a struct. Use wizard.validate_request
%   to check schema/events/compatibility, and wizard.dispatch_analysis to run.
%
%   The request struct fields:
%     analysis      - stable analysis ID
%     case_id       - stable case ID
%     options       - merged options struct (defaults + user overrides)
%     events        - event spec struct (or [] for NOT_APPLICABLE / none)
%     events_policy - 'not_applicable' | 'event_free' | 'configured'
%     interactive   - logical (true when built from the wizard UI)
%     schema_version- 'wizard_request_v1'
%
%   See also: wizard.VALIDATE_REQUEST, wizard.DISPATCH_ANALYSIS.

p = inputParser;
addParameter(p, 'options', struct(), @isstruct);
addParameter(p, 'events', [], @(x) isstruct(x) || isempty(x));
addParameter(p, 'interactive', false, @islogical);
parse(p, varargin{:});

analysis_id = lower(char(analysis_id));
case_id = lower(char(case_id));

% Resolve defaults lazily through the catalog (pure metadata; no case load).
case_entry = find_case_entry(analysis_id, case_id);
opt = wizard.defaults_for_method(analysis_id, case_entry);
opt = merge_options(opt, p.Results.options);

% Determine events policy.
registry = wizard.analysis_registry();
aidx = find(strcmp(analysis_id, {registry.id}), 1);
events_applicable = registry(aidx).events_applicable;
ev = p.Results.events;
events_explicit = ~isempty(p.Results.events) || ...
    (isfield(p.Results.options, 'ibr_events') && ...
     ~isempty(p.Results.options.ibr_events));
% For IBR, the legacy launcher carries events inside options.ibr_events
% (nested). Extract it into the request's events field so the dispatcher
% attaches it correctly (correction #6: events must reach the production
% runtime; do not hide them inside options for one analysis only).
if events_applicable && isempty(ev) && isfield(opt, 'ibr_events') ...
        && isstruct(opt.ibr_events) && ~isempty(opt.ibr_events)
    ev = opt.ibr_events;
    opt = rmfield(opt, 'ibr_events');
end
if ~events_applicable
    events_policy = 'not_applicable';
    ev = [];
elseif isempty(ev)
    events_policy = 'event_free';
elseif isstruct(ev) && isfield(ev, 'enabled') && ~logical(ev.enabled)
    % An explicit disabled event struct reaches the runtime as an empty
    % schedule (correction #6). Treat it as event_free for the request
    % policy, but KEEP the disabled struct so the dispatcher can pass it
    % through to the production runtime as the empty-schedule sentinel.
    events_policy = 'event_free';
else
    events_policy = 'configured';
end

% The top-level IBR family supports events, but its PF and SSSA products do
% not.  Suppress only the inherited TS default event here.  An event supplied
% explicitly by the caller is retained and rejected by validate_request.
if strcmp(analysis_id, 'ibr') && isfield(opt, 'ibr_analysis') && ...
        ismember(lower(char(opt.ibr_analysis)), ...
            {'pf','pf_compare','sssa','sssa_compare'}) && ...
        ~events_explicit
    ev = struct('enabled', false);
    events_policy = 'event_free';
end

req = struct( ...
    'analysis', analysis_id, ...
    'case_id', case_id, ...
    'options', opt, ...
    'events', ev, ...
    'events_policy', events_policy, ...
    'interactive', logical(p.Results.interactive), ...
    'schema_version', 'wizard_request_v1');
end

function entry = find_case_entry(analysis_id, case_id)
% Lazy discovery (correction #8): enumerates case metadata without loading
% solved states or invoking solvers.
entries = wizard.discover_cases(analysis_id);
idx = find(strcmp(case_id, {entries.id}), 1);
if isempty(idx)
    entry = struct();
else
    entry = entries(idx);
end
end

function out = merge_options(defaults, user)
out = defaults;
if ~isstruct(user) || isempty(user), return; end
names = fieldnames(user);
for k = 1:numel(names)
    out.(names{k}) = user.(names{k});
end
end
