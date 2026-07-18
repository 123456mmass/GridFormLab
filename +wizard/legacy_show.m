function result = legacy_show(varargin)
%LEGACY_SHOW Compact dialog UI backed by the shared wizard dispatcher.
%   Restores the original solve_case interaction style: select analysis,
%   select case, edit method settings, then run. Numerical work remains in
%   wizard.dispatch_analysis; this function contains presentation and safe
%   option parsing only.

p = inputParser;
addParameter(p, 'analysis', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'case', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'options', struct(), @isstruct);
parse(p, varargin{:});
analysis = lower(char(p.Results.analysis));
case_id = lower(char(p.Results.case));
user_opt = p.Results.options;

registry = wizard.analysis_registry();
if isempty(analysis)
    labels = arrayfun(@(x) sprintf('%s - %s', x.label, x.description), ...
        registry, 'UniformOutput', false);
    analysis = choose_one('Select analysis', labels, {registry.id}, 1, [500 170]);
    if isempty(analysis), result = []; return; end
end
idx = find(strcmp({registry.id}, analysis), 1);
if isempty(idx)
    error('solve_case:analysis', 'Unknown analysis %s.', analysis);
end

entries = wizard.discover_cases(analysis);
if isempty(case_id)
    labels = arrayfun(@(x) sprintf('%s - %s', x.id, x.label), ...
        entries, 'UniformOutput', false);
    case_id = choose_one('Select case', labels, {entries.id}, 1, [520 260]);
    if isempty(case_id), result = []; return; end
end
eidx = find(strcmp({entries.id}, case_id), 1);
if isempty(eidx)
    error('solve_case:case', 'Case %s not supported for %s.', case_id, analysis);
end
entry = entries(eidx);
opt = merge_options(wizard.defaults_for_method(analysis, entry), user_opt);

switch analysis
    case 'pf'
        methods = {'newton_raphson','fdpf_xb','fdpf_bx'};
        method_labels = {'Newton-Raphson (default)', ...
            'Fast Decoupled PF - XB', 'Fast Decoupled PF - BX'};
        current = 1;
        if isfield(opt, 'pf_method')
            found = find(strcmp(methods, opt.pf_method), 1);
            if ~isempty(found), current = found; end
        end
        selected = choose_one('Select Power Flow method', method_labels, ...
            methods, current, [400 150]);
        if isempty(selected), result = []; return; end
        opt.pf_method = selected;
        [opt, accepted] = edit_options(opt, entry.label, {'ibr_events'});
    case 'sssa'
        [opt, accepted] = edit_options(opt, entry.label, {'ibr_events'});
    case 'ts'
        methods = {'trapezoidal','backward_euler','rk4'};
        method_labels = {'Trapezoidal (default)', ...
            'Backward Euler', 'RK4 (diagnostic)'};
        selected = choose_one('Select TS integration method', method_labels, ...
            methods, 1, [400 150]);
        if isempty(selected), result = []; return; end
        opt.method = selected;
        opt.integrator = selected;
        [opt, accepted] = edit_options(opt, entry.label, {'ibr_events'});
    case 'ibr'
        case_data = entry.loader();
        [opt, accepted] = wizard.ibr_settings_dialog(case_data, opt, entry.label);
    otherwise
        error('solve_case:analysis', 'Unknown analysis %s.', analysis);
end
if ~accepted, result = []; return; end

args = {'options', opt, 'interactive', true};
if strcmp(analysis, 'ts')
    ev = struct('enabled', true, 'fault_bus', opt.fault_bus, ...
        'fault_on', opt.t_fault, 'fault_clear', opt.t_clear, 'Zf', opt.Zf);
    args = [args {'events', ev}];
elseif strcmp(analysis, 'ibr') && isfield(opt, 'ibr_events')
    args = [args {'events', opt.ibr_events}];
end
req = wizard.build_request(analysis, case_id, args{:});
req = wizard.validate_request(req);
result = wizard.dispatch_analysis(req);

status = 'Run complete';
if isfield(result, 'converged') && ~logical(result.converged)
    status = 'Run finished with a fail-closed result';
end
log_file = '';
if isfield(result, 'launcher') && isfield(result.launcher, 'log_file')
    log_file = result.launcher.log_file;
end
msgbox(sprintf('%s\n%s\n\nLog:\n%s', status, entry.label, log_file), ...
    'solve_case', 'modal');
end

function value = choose_one(prompt, labels, ids, initial, list_size)
[k, ok] = listdlg('PromptString', prompt, 'SelectionMode', 'single', ...
    'ListString', labels, 'InitialValue', initial, 'ListSize', list_size);
if ok, value = ids{k}; else, value = ''; end
end

function [opt, accepted] = edit_options(opt, case_label, excluded)
fields = fieldnames(opt);
fields = fields(~ismember(fields, excluded));
editable = false(size(fields));
for k = 1:numel(fields)
    v = opt.(fields{k});
    editable(k) = islogical(v) || isnumeric(v) || ischar(v) || ...
        (isstring(v) && isscalar(v));
end
fields = fields(editable);
prompts = strrep(fields, '_', '\_');
defaults = cellfun(@(f) wizard.pages.format_value(opt.(f)), fields, ...
    'UniformOutput', false);
accepted = false;
while true
    answer = inputdlg(prompts, sprintf('Settings - %s', case_label), ...
        repmat([1 58], numel(prompts), 1), defaults, struct('Resize', 'on'));
    if isempty(answer), return; end
    candidate = opt;
    message = '';
    for k = 1:numel(fields)
        try
            candidate.(fields{k}) = parse_like(answer{k}, opt.(fields{k}));
        catch e
            message = sprintf('%s: %s', fields{k}, e.message);
            break;
        end
    end
    if isempty(message)
        opt = candidate;
        accepted = true;
        return;
    end
    errordlg(message, 'Invalid setting', 'modal');
    defaults = answer;
end
end

function value = parse_like(text, prototype)
text = strtrim(char(text));
if islogical(prototype)
    if any(strcmpi(text, {'true','1','yes','on'}))
        value = true;
    elseif any(strcmpi(text, {'false','0','no','off'}))
        value = false;
    else
        error('wizard:legacy_show:logical', 'Use true or false.');
    end
elseif isnumeric(prototype)
    value = parse_numeric(text, prototype);
elseif isstring(prototype)
    value = string(text);
else
    value = text;
end
end

function value = parse_numeric(text, prototype)
if strcmp(text, '[]') || isempty(text)
    value = [];
    return;
end
compact = regexprep(text, '\s+', '');
number = '[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?';
tok = regexp(compact, ['^(' number ')(' number ')[ij]$'], 'tokens', 'once');
if isempty(tok)
    tok = regexp(compact, ['^(' number ')([+-](?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)[ij]$'], ...
        'tokens', 'once');
end
if ~isempty(tok)
    value = str2double(tok{1}) + 1i*str2double(tok{2});
elseif endsWith(compact, {'i','j'})
    imag_text = compact(1:end-1);
    if strcmp(imag_text, '+') || isempty(imag_text), imag_text = '1'; end
    if strcmp(imag_text, '-'), imag_text = '-1'; end
    value = 1i * str2double(imag_text);
else
    body = regexprep(text, '[\[\],;]', ' ');
    if isempty(regexp(body, '^[\s+\-0-9.eE]+$', 'once'))
        error('wizard:legacy_show:numeric', 'Use a numeric scalar/vector.');
    end
    value = sscanf(body, '%f').';
end
if isempty(value) || any(~isfinite(value), 'all')
    error('wizard:legacy_show:numeric', 'Use finite numeric values.');
end
if isscalar(prototype) && ~isscalar(value)
    error('wizard:legacy_show:numericShape', 'A scalar value is required.');
end
end

function out = merge_options(defaults, user)
out = defaults;
if ~isstruct(user), return; end
names = fieldnames(user);
for k = 1:numel(names), out.(names{k}) = user.(names{k}); end
end
