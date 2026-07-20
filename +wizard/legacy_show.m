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
ts_events_enabled = true;

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
        event_mode = choose_one('Time-Domain Simulation events', ...
            {'No events - normal event-free simulation', ...
             'Configure fault event'}, {'off','on'}, 1, [470 120]);
        if isempty(event_mode), result = []; return; end
        ts_events_enabled = strcmp(event_mode, 'on');
        [opt, accepted] = edit_options(opt, entry.label, {'ibr_events'});
    case 'ibr'
        is_smib = endsWith(case_id,'_smib');
        if is_smib
            sub_ids = {'pf','sssa','ts','full'};
            sub_labels = { ...
                'PF / Equilibrium - phasor, KCL and power identity', ...
                'Small-Signal Stability - Schur/direct SMIB oracle', ...
                'Time-Domain Simulation - event-free SMIB oracle', ...
                'Full Verification - PF/equilibrium + SSSA + event-free TDS'};
            current=4;
            if isfield(opt,'ibr_analysis')
                found=find(strcmp(sub_ids,lower(char(opt.ibr_analysis))),1);
                if ~isempty(found), current=found; end
            end
            selected=choose_one('Select Single Infinite Bus verification', ...
                sub_labels,sub_ids,current,[590 150]);
            if isempty(selected), result=[]; return; end
            opt.ibr_analysis=selected;
            opt.ibr_events=struct('enabled',false);
            % SMIB contains exactly one converter of the case-selected type.
            % IEEE14 family/profile/mode-count controls are not applicable.
            excluded={'ibr_events','ibr_analysis','ibr_profile', ...
                'initial_gfm_count','initial_gfl_count','initial_gfm_indices', ...
                'initial_reference_resource_index','automatic_gfm_switching', ...
                'pf_verbose'};
            [opt,accepted]=edit_options(opt,entry.label,excluded);
        else
        % The launcher is bound to RMS10-capable containers. The initial
        % GFM/GFL mix remains editable; Profile B (1 GFM + 3 GFL) is default.
        opt.ibr_profile = 'rms10_profile_b';
        sub_ids = {'pf','pf_compare','sssa','sssa_compare','ts','full'};
        sub_labels = { ...
            'Power Flow - network operating point', ...
            'Power Flow Comparison - SG pre-trip / tripped / returned', ...
            'Small-Signal Stability - mixed SG/GFM/GFL full-state model', ...
            'SSSA Comparison - SG pre-trip / tripped / returned', ...
            'Time-Domain Simulation (TS) - mixed-resource time simulation', ...
            'Full Analysis - PF + equilibrium + SSSA + TS'};
        current = 5;
        if isfield(opt, 'ibr_analysis')
            found = find(strcmp(sub_ids, lower(char(opt.ibr_analysis))), 1);
            if ~isempty(found), current = found; end
        end
        selected = choose_one('Select IEEE14 1-SG + 4-IBR analysis', ...
            sub_labels, sub_ids, current, [560 180]);
        if isempty(selected), result = []; return; end
        opt.ibr_analysis = selected;
        if strcmp(selected,'full')
            link_choice=choose_one('Full Analysis IBR mode configuration', ...
                {'Use one GFM/GFL device map for PF, SSSA and TS', ...
                 'Configure PF, SSSA and TS device maps separately'}, ...
                {'linked','separate'},1,[570 120]);
            if isempty(link_choice), result=[]; return; end
            if strcmp(link_choice,'linked')
                [opt,mode_ok]=choose_ibr_device_modes(opt,'PF / SSSA / TS');
                if ~mode_ok, result=[]; return; end
                cfg=mode_config(opt);
                opt.ibr_method_modes=struct('linked',true,'pf',cfg,'sssa',cfg,'ts',cfg);
            else
                cfgs=struct('linked',false);
                names={'pf','sssa','ts'};
                working=opt;
                for km=1:numel(names)
                    [working,mode_ok]=choose_ibr_device_modes(working,upper(names{km}));
                    if ~mode_ok, result=[]; return; end
                    cfgs.(names{km})=mode_config(working);
                end
                opt.ibr_method_modes=cfgs;
                opt=apply_mode_config(opt,cfgs.ts);
            end
        else
            [opt,mode_ok]=choose_ibr_device_modes(opt,upper(strrep(selected,'_',' ')));
            if ~mode_ok, result=[]; return; end
        end
        case_data = entry.loader();
        if strcmp(selected, 'ts')
            % The mixed-resource TS uses the same canonical fixed-step
            % implicit trapezoidal kernel as the SG path.  Method is frozen;
            % only time grid, outputs, and event choice are user settings.
            opt.method = 'trapezoidal';
            opt.integrator = 'trapezoidal';
            event_mode = choose_one('IBR Time-Domain Simulation events', ...
                {'No events - normal event-free simulation', ...
                 'Fault only - fail-closed diagnostic (RMS10 LVRT not ready)', ...
                 'SG trip/reclose only - no network fault', ...
                 'Combined - fault + SG trip/reclose'}, ...
                {'off','fault_only','sg_cycle','combined'}, 1, [560 150]);
            if isempty(event_mode), result = []; return; end
            if ~strcmp(event_mode, 'off')
                opt.ibr_events.event_profile = event_mode;
                [opt, accepted] = wizard.ibr_settings_dialog( ...
                    case_data, opt, entry.label, event_mode);
            else
                opt.ibr_events = struct('enabled', false);
                [opt, accepted] = edit_options(opt, ...
                    sprintf('%s - Time-Domain Simulation (event-free)', entry.label), ...
                    {'ibr_events','ibr_analysis','ibr_profile', ...
                     'initial_gfm_indices','initial_reference_resource_index', ...
                     'automatic_gfm_switching'});
            end
        elseif strcmp(selected, 'full')
            event_mode = choose_one('IBR Full Analysis events', ...
                {'No events - PF + equilibrium + SSSA + event-free TS (default)', ...
                 'Fault only - fail-closed diagnostic (RMS10 LVRT not ready)', ...
                 'SG trip/reclose only - no network fault', ...
                 'Combined - fault + SG trip/reclose'}, ...
                {'off','fault_only','sg_cycle','combined'},1,[610 150]);
            if isempty(event_mode), result=[]; return; end
            if strcmp(event_mode,'off')
                opt.ibr_events=struct('enabled',false);
                [opt,accepted]=edit_options(opt, ...
                    sprintf('%s - Full Analysis (event-free)',entry.label), ...
                    {'ibr_events','ibr_analysis','ibr_profile', ...
                     'initial_gfm_indices', ...
                     'initial_reference_resource_index','automatic_gfm_switching'});
            else
                opt.ibr_events.event_profile=event_mode;
                [opt,accepted]=wizard.ibr_settings_dialog( ...
                    case_data,opt,entry.label,event_mode);
            end
        else
            % PF/SSSA have no event transaction.  Keep the compact editable
            % settings dialog and explicitly disable the nested event route.
            opt.ibr_events = struct('enabled', false);
            comparison_name = upper(strrep(selected,'_',' '));
            [opt, accepted] = edit_options(opt, ...
                sprintf('%s - %s', entry.label, comparison_name), ...
                {'ibr_events','initial_gfm_indices', ...
                 'initial_reference_resource_index'});
        end
        end
    otherwise
        error('solve_case:analysis', 'Unknown analysis %s.', analysis);
end

if ~accepted, result = []; return; end
if strcmp(analysis, 'ibr') && ~endsWith(case_id,'_smib')
    opt = wizard.normalize_ibr_mode_selection(opt);
end

args = {'options', opt, 'interactive', true};
if strcmp(analysis, 'ts')
    ev = struct('enabled', ts_events_enabled);
    if ts_events_enabled
        ev.fault_bus = opt.fault_bus;
        ev.fault_on = opt.t_fault;
        ev.fault_clear = opt.t_clear;
        ev.Zf = opt.Zf;
    end
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

function [opt,accepted]=choose_ibr_device_modes(opt,method_label)
labels={'NONE - all four IBRs use GFL-RMS10', ...
    'IBR2 @ Bus 2  -> GFM-13', ...
    'IBR3 @ Bus 3  -> GFM-13', ...
    'IBR6 @ Bus 6  -> GFM-13', ...
    'IBR8 @ Bus 8  -> GFM-13'};
eligible=2:5;
initial=opt.initial_gfm_indices(:).';
if isempty(initial), initial=1; end
accepted=false;
while true
    [k,ok]=listdlg('PromptString',sprintf([ ...
        '%s: select every device that shall operate as GFM.\n' ...
        'Unselected devices operate as GFL-RMS10.'],method_label), ...
        'SelectionMode','multiple','ListString',labels, ...
        'InitialValue',initial,'ListSize',[470 180]);
    if ~ok, return; end
    if ismember(1,k) && numel(k)>1
        errordlg('Select NONE alone, or select one or more IBR devices.','Invalid mode map','modal');
        initial=k;
        continue;
    end
    if isequal(k,1), idx=[]; else, idx=eligible(k(k>1)-1); end
    opt.initial_gfm_count=numel(idx);
    opt.initial_gfl_count=numel(eligible)-numel(idx);
    opt.initial_gfm_indices=idx;
    opt.initial_reference_resource_index=[];
    opt=wizard.normalize_ibr_mode_selection(opt);
    accepted=true;
    return;
end
end

function cfg=mode_config(opt)
cfg=struct('initial_gfm_count',opt.initial_gfm_count, ...
    'initial_gfl_count',opt.initial_gfl_count, ...
    'initial_gfm_indices',opt.initial_gfm_indices, ...
    'initial_reference_resource_index',opt.initial_reference_resource_index);
end

function opt=apply_mode_config(opt,cfg)
names=fieldnames(cfg);
for k=1:numel(names), opt.(names{k})=cfg.(names{k}); end
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
