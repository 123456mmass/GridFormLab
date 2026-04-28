function app = browse_custom_case(app, fig)
%BROWSE_CUSTOM_CASE File-picker for custom .m/.mat cases. Returns modified app.

[file, path] = uigetfile({'*.m;*.mat', 'MATLAB case files (*.m, *.mat)'; '*.m', 'MATLAB function (*.m)'; '*.mat', 'MAT-file (*.mat)'}, ...
    'Select n-bus case file');
if isequal(file, 0)
    return;
end

full_path = fullfile(path, file);
try
    [~, name, ext] = fileparts(full_path);
    switch lower(ext)
        case '.m'
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
                    if isstruct(candidate) && isfield(candidate, 'bus_data') && isfield(candidate, 'line_data')
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

    pf_prepare_case(case_data);
    if ~isfield(case_data, 'system_name') || isempty(case_data.system_name)
        case_data.system_name = sprintf('Custom n-bus: %s', name);
    end
    app.custom_case_data = case_data;
    app.case_labels{end} = sprintf('Custom n-bus: %s', name);
    app.case_loaders{end} = [];
    app.case_dropdown.Items = app.case_labels;
    app.case_dropdown.Value = app.case_labels{end};
    pfapp.append_log(app, sprintf('Loaded custom n-bus case: %s', full_path));
catch err
    pfapp.append_log(app, sprintf('CUSTOM CASE ERROR: %s', err.message));
    uialert(fig, err.message, 'Custom Case Failed');
end
end
