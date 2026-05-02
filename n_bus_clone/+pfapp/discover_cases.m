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

    % Try to get the function handle
    try
        fh = str2func(name);
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
% Convert case_ieee5bus -> "IEEE 5-bus"
name = strrep(func_name, 'case_', '');
name = strrep(name, '_', ' ');
% Capitalize known acronyms
name = regexprep(name, '\<ieee\>', 'IEEE', 'ignorecase');
name = regexprep(name, '\<opf\>', 'OPF', 'ignorecase');
name = regexprep(name, '\<cpf\>', 'CPF', 'ignorecase');
name = regexprep(name, '\<matpower\>', 'MATPOWER', 'ignorecase');
name = regexprep(name, '\<saadat\>', 'Saadat', 'ignorecase');
name = regexprep(name, '\<nr\>', 'NR', 'ignorecase');
name = regexprep(name, '\<gs\>', 'GS', 'ignorecase');
% Capitalize first letter if not already done by acronym step
name = regexprep(name, '^(\w)', '${upper($1)}');
label = strtrim(name);
end
