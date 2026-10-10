function entries = list()
%EVENTS.LIST  Lazy enumeration of the hand-editable event files.
%   ENTRIES = events.list() returns a struct array, one entry per file
%   matching <root>/events/evt_*.m, sorted by id. It is PURE and LAZY in the
%   same sense as wizard.discover_cases: it lists files and attaches loaders
%   as function handles. It NEVER executes an event file, loads a case, or
%   calls a solver, so opening a dropdown cannot throw or block.
%
%   Entry fields:
%     id          stable ID (char, lowercase, e.g. 'ne39_bus_fault').
%                 This is the file stem with the mandatory 'evt_' prefix
%                 removed; it is what events.load accepts.
%     name        the MATLAB function name ('evt_ne39_bus_fault').
%     label       display name derived from the id (no file execution).
%     file        absolute path of the file.
%     loader      zero-argument function handle returning the event struct.
%     is_template true for evt_template.m, the copy-me starter.
%
%   WHY THE evt_ PREFIX AND THE which() CHECK.
%   Two similarly named folders exist on purpose: the plain folder
%   <root>/events/ (hand-editable) and the package <root>/+events/ (the
%   machinery). MATLAB always resolves events.something to the PACKAGE, so
%   the plain folder is only ever reached by explicit name -- which is why
%   every file in it is prefixed evt_. That leaves one failure mode: a
%   file of the same name earlier on the MATLAB path (a toolbox, another
%   project, a stray scratch folder) would be executed instead of ours,
%   silently. list() therefore asks which(...) where the name actually
%   resolves and FAILS CLOSED unless it resolves inside <root>/events/.
%
%   Stable failure IDs:
%     events:list:noConfigDir          the plain config folder is missing
%     events:list:shadowedDefinition   a name does not resolve to our folder
%
%   See also: events.LOAD, events.DESCRIBE, wizard.DISCOVER_CASES.

root = pf_init_paths();
config_dir = fullfile(root, 'events');
if ~exist(config_dir, 'dir')
    error('events:list:noConfigDir', ...
        ['The hand-editable event folder is missing:\n  %s\n' ...
         'Create it (or restore it from version control) -- an empty list ' ...
         'would look like "no configurations exist", which is not the truth.'], ...
        config_dir);
end

d = dir(fullfile(config_dir, 'evt_*.m'));
entries = repmat(entry_template(), 0, 1);
for k = 1:numel(d)
    [~, name] = fileparts(d(k).name);
    resolved = which(name);
    if isempty(resolved) || ~same_folder(fileparts(resolved), config_dir)
        error('events:list:shadowedDefinition', ...
            ['Event file %s does not resolve to %s.\n' ...
             '  which(''%s'') -> %s\n' ...
             'Another file of the same name is earlier on the MATLAB path, ' ...
             'or the folder is not on the path at all. Refusing to list a ' ...
             'definition that is not the one in the hand-editable folder.'], ...
            d(k).name, config_dir, name, ...
            ternary(isempty(resolved), '<not found>', resolved));
    end
    id = strip_prefix(name);
    s = entry_template();
    s.id = id;
    s.name = name;
    s.label = label_from_id(id);
    s.file = fullfile(config_dir, d(k).name);
    s.loader = str2func(name);
    s.is_template = strcmpi(id, 'template');
    entries(end+1, 1) = s; %#ok<AGROW>
end

% Deterministic order independent of the filesystem's.
[~, order] = sort({entries.id});
entries = entries(order);
end

% =========================================================================
function s = entry_template()
s = struct('id', '', 'name', '', 'label', '', 'file', '', ...
    'loader', [], 'is_template', false);
end

function id = strip_prefix(name)
% The evt_ prefix is mandatory (see the header); strip exactly one.
id = regexprep(name, '^evt_', '');
end

function label = label_from_id(id)
% Display label from the ID alone. The file is deliberately NOT executed and
% its help text is NOT read here, so listing stays lazy.
words = strsplit(id, '_');
words = cellfun(@(w) [upper(w(1)) lower(w(2:end))], words, 'UniformOutput', false);
label = strjoin(words, ' ');
end

function tf = same_folder(a, b)
% Compare two folder paths case-insensitively and with one separator
% convention. Windows is case-insensitive; the repository is developed there.
tf = strcmpi(normalize_folder(a), normalize_folder(b));
end

function p = normalize_folder(p)
p = regexprep(char(p), '[\\/]+', '/');
if numel(p) > 1 && p(end) == '/'
    p(end) = [];
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
