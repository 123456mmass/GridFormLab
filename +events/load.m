function ev = load(id_or_path)
%EVENTS.LOAD  Execute one hand-editable event file and check its envelope.
%   EV = events.load(ID) resolves ID through events.list() and calls the file.
%   ID is the list ID ('ne39_bus_fault') or the function name with its
%   mandatory prefix ('evt_ne39_bus_fault').
%
%   EV = events.load(PATH) evaluates one explicit file. PATH must live inside
%   <root>/events/; anything else fails closed, so a name that happens to
%   resolve elsewhere on the MATLAB path can never be executed as a config.
%
%   This function does the ENVELOPE check only -- it is a struct with the
%   canonical schema version. Field-level rules are events.validate's job
%   (call it, or call events.resolve, which calls it). Keeping the two apart
%   means a malformed VALUE names the field that is wrong, while this file
%   only has to answer "is this even one of ours".
%
%   Stable failure IDs:
%     events:load:unknownEvent   ID is not in events.list()
%     events:load:badSchema      the file did not return the canonical record
%     events:load:badPath        explicit path is outside <root>/events/
%
%   See also: events.LIST, events.VALIDATE, events.SCHEMA.

ev = [];
if ischar(id_or_path)
    id_or_path = strtrim(id_or_path);
elseif isstring(id_or_path) && isscalar(id_or_path)
    id_or_path = strtrim(char(id_or_path));
end
if isempty(id_or_path)
    error('events:load:unknownEvent', 'Event ID must be a non-empty name.');
end

root = pf_init_paths();
config_dir = fullfile(root, 'events');

if is_explicit_path(id_or_path)
    file = id_or_path;
    if ~exist(file, 'file')
        error('events:load:unknownEvent', 'Event file not found: %s', file);
    end
    folder = fileparts(file);
    if ~strcmpi(normalize_folder(folder), normalize_folder(config_dir))
        error('events:load:badPath', ...
            ['Event file %s is outside the hand-editable folder %s.\n' ...
             'Refusing to execute a config from anywhere else.'], ...
            file, config_dir);
    end
    [~, name] = fileparts(file);
else
    % Resolve through the listing so the which()/shadow check applies here
    % too: load() must never execute a definition list() would refuse.
    entries = events.list();
    id = regexprep(id_or_path, '^evt_', '');
    idx = find(strcmp(id, {entries.id}), 1);
    if isempty(idx)
        error('events:load:unknownEvent', ...
            'Unknown event "%s". Available: %s.', ...
            id_or_path, strjoin({entries.id}, ', '));
    end
    name = entries(idx).name;
end

fn = str2func(name);
ev = fn();

canonical = events.schema();
if ~isstruct(ev) || ~isscalar(ev)
    error('events:load:badSchema', ...
        'Event file %s must return one struct (got %s).', name, class(ev));
end
if ~isfield(ev, 'schema_version') || ...
        ~strcmp(char(ev.schema_version), canonical.schema_version)
    error('events:load:badSchema', ...
        'Event file %s must start from events.schema() (schema_version "%s").', ...
        name, canonical.schema_version);
end
end

% =========================================================================
function tf = is_explicit_path(s)
% A path, not an ID: it carries a separator or the .m extension. An ID is a
% bare lowercase identifier, so this test is unambiguous.
tf = ~isempty(strfind(s, filesep)) || ... %#ok<STREMP>
     ~isempty(strfind(s, '/')) || ... %#ok<STREMP>
     endsWith(lower(s), '.m');
end

function p = normalize_folder(p)
p = regexprep(char(p), '[\\/]+', '/');
if numel(p) > 1 && p(end) == '/'
    p(end) = [];
end
end
