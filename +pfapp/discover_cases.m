function [case_labels, case_loaders] = discover_cases(cases_dir)
%DISCOVER_CASES Auto-discover case functions in +cases/ package.
%   Scans the +cases/ directory for functions matching case_*.m pattern.
%   Returns cell arrays of human-readable labels and function handles.

if nargin < 1 || isempty(cases_dir)
    cases_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+cases');
end

case_labels = {};
case_loaders = {};

if ~exist(cases_dir, 'dir')
    return;
end

files = dir(fullfile(cases_dir, '*.m'));
for i = 1:numel(files)
    [~, name] = fileparts(files(i).name);
    % Skip private/ and non-case files
    if strcmp(name, 'Contents') || startsWith(name, 'private')
        continue;
    end

    % Try to get the function handle (resolve via the +cases package so
    % cases without a root-level wrapper — e.g. the Kundur SMIB cases —
    % are still discoverable).
    try
        fh = str2func(['cases.' name]);
        case_labels{end + 1} = make_label(name);
        case_loaders{end + 1} = fh;
    catch
        % Skip functions that can't be resolved
    end
end

% Sort by label
[case_labels, idx] = sort(case_labels);
case_loaders = case_loaders(idx);
end

function label = make_label(func_name)
% Convert case_ieee14bus -> "IEEE 14 Bus"
name = strrep(func_name, 'case_', '');
name = strrep(name, '_', ' ');
% Insert spaces between letter/digit boundaries (ieee14bus -> ieee 14 bus)
name = regexprep(name, '([a-zA-Z])(\d)', '$1 $2');
name = regexprep(name, '(\d)([a-zA-Z])', '$1 $2');
% Capitalize known acronyms (now whole words thanks to the spaces)
name = regexprep(name, '\<ieee\>', 'IEEE', 'ignorecase');
name = regexprep(name, '\<opf\>', 'OPF', 'ignorecase');
name = regexprep(name, '\<cpf\>', 'CPF', 'ignorecase');
name = regexprep(name, '\<matpower\>', 'MATPOWER', 'ignorecase');
name = regexprep(name, '\<saadat\>', 'Saadat', 'ignorecase');
name = regexprep(name, '\<kundur\>', 'Kundur', 'ignorecase');
name = regexprep(name, '\<smib\>', 'SMIB', 'ignorecase');
name = regexprep(name, '\<avr\>', 'AVR', 'ignorecase');
name = regexprep(name, '\<pss\>', 'PSS', 'ignorecase');
name = regexprep(name, '\<nr\>', 'NR', 'ignorecase');
name = regexprep(name, '\<gs\>', 'GS', 'ignorecase');
% Capitalize the first letter of every remaining lowercase word
name = regexprep(name, '\<([a-z])', '${upper($1)}');
label = strtrim(name);
end
