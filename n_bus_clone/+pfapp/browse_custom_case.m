function app = browse_custom_case(app, fig)
%BROWSE_CUSTOM_CASE File-picker for custom .m/.mat cases. Returns modified app.

[file, path] = uigetfile( ...
    {'*.m;*.mat', 'MATLAB case files (*.m, *.mat)'; ...
     '*.m', 'MATLAB function (*.m)'; ...
     '*.mat', 'MAT-file (*.mat)'}, ...
    'Select n-bus case file');
if isequal(file, 0)
    return;
end

full_path = fullfile(path, file);
try
    [~, name, ext] = fileparts(full_path);
    switch lower(ext)
        case '.m'
            % Validate function name: must start with letter, contain only
            % alphanumeric + underscore, to prevent executing builtins
            if isempty(regexp(name, '^[a-zA-Z]\w*$', 'once'))
                error(['Unsafe or invalid function name: %s. ' ...
                    'Function name must start with a letter and contain ' ...
                    'only letters, numbers, and underscores.'], name);
            end
            % Temporarily add path, load, then remove to avoid permanent pollution
            cleanup_path = onCleanup(@() rmpath(path));
            addpath(path);
            loader = str2func(name);
            case_data = loader();

        case '.mat'
            vars = load(full_path);
            if isfield(vars, 'case_data')
                case_data = vars.case_data;
            else
                fields = fieldnames(vars);
                case_data = [];
                for k = 1:numel(fields)
                    candidate = vars.(fields{k});
                    if isstruct(candidate) && isfield(candidate, 'bus_data') ...
                            && isfield(candidate, 'line_data')
                        case_data = candidate;
                        break;
                    end
                end
                if isempty(case_data)
                    error('MAT file must contain case_data or a struct with bus_data and line_data.');
                end
            end
        otherwise
            error('Unsupported case file extension: %s', ext);
    end

    case_data = pf_prepare_case(case_data);
    if ~isfield(case_data, 'system_name') || isempty(case_data.system_name)
        case_data.system_name = sprintf('Custom n-bus: %s', name);
    end
    app.custom_case_data = case_data;

    % Use dedicated custom-case slot instead of overwriting registry{end}
    custom_label = sprintf('Custom n-bus: %s', name);
    app.case_labels{custom_slot_idx()} = custom_label;
    app.case_loaders{custom_slot_idx()} = [];
    app.case_dropdown.Items = app.case_labels;
    app.case_dropdown.Value = custom_label;
    pfapp.append_log(app, sprintf('Loaded custom n-bus case: %s', full_path));
catch err
    pfapp.append_log(app, sprintf('CUSTOM CASE ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'Custom Case Failed');
    catch
    end
end
end

function idx = custom_slot_idx()
%CUSTOM_SLOT_IDX Return the index of the custom-case slot in the registry.
persistent slot
if isempty(slot)
    [labels, ~] = pfapp.make_case_registry();
    slot = numel(labels) + 1;  % one past the fixed registry
end
idx = slot;
end
