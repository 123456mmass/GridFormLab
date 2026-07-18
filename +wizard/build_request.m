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
if ~events_applicable
    events_policy = 'not_applicable';
    ev = [];
elseif isempty(ev)
    events_policy = 'event_free';
else
    events_policy = 'configured';
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
