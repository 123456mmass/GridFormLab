function [opt, accepted] = ibr_settings_dialog(case_data, opt, case_label)
%IBR_SETTINGS_DIALOG  Base-MATLAB three-column IBR settings editor.
%   [OPT, ACCEPTED] = wizard.ibr_settings_dialog(CASE_DATA, OPT, CASE_LABEL)
%   opens the IBR settings dialog (three-column base-MATLAB uipanel/uicontrol)
%   and returns the accepted options or the original options on cancel.
%
%   This is the EXACT IBR settings section that lived in solve_case.m before
%   the Extract+delegate refactor, moved verbatim into +wizard/ to preserve
%   the base-MATLAB three-column contract (test_ibr_launcher_settings_ui.m).
%   The wizard UI calls this for the IBR analysis interactive path.
%
%   Non-interactive (batch) callers never reach this function; the programmatic
%   path goes through wizard.build_request -> wizard.dispatch_analysis instead.

base = cases.scenario_ieee14_1sg_4ibr();
ids = {base.resources.resource_id};
eligible = find(strcmp({base.resources.resource_type}, 'ibr'));
bus_text = format_bus_ids(case_bus_ids(case_data));
ev = opt.ibr_events;
delay = ibr_dialog_delay_defaults(case_data, opt);
defaults = {num_text(opt.t_end), num_text(opt.dt), logical_text(opt.plot_results), ...
    logical_text(opt.plot_visible), logical_text(opt.verbose), num_text(opt.initial_gfm_count), ...
    num_text(opt.initial_gfl_count), index_text(opt.initial_gfm_indices), ...
    index_text(opt.initial_reference_resource_index), logical_text(ev.enabled), ...
    num_text(ev.fault_bus), num_text(real(ev.Zf)), num_text(imag(ev.Zf)), ...
    num_text(ev.fault_on), num_text(ev.fault_clear), num_text(ev.sg_trip), ...
    num_text(ev.sg_on), index_text(ev.selected_gfm_indices), ...
    num_text(ev.reference_resource_index), num_text(delay.dwell_s), ...
    num_text(delay.timeout_s)};
accepted = false;
while true
    [dlg, fields] = create_ibr_settings_dialog(case_label, bus_text, eligible, ids, defaults);
    uiwait(dlg);
    if ~isgraphics(dlg), return; end
    submitted = getappdata(dlg, 'submitted');
    if ~submitted, delete(dlg); return; end
    answer = cellfun(@(h) get(h, 'String'), fields, 'UniformOutput', false);
    delete(dlg);
    if isempty(answer), return; end
    [candidate, message] = parse_ibr_dialog(opt, answer, case_bus_ids(case_data), eligible, ids);
    if isempty(message), opt = candidate; accepted = true; return; end
    errordlg(message, 'Invalid IBR settings', 'modal'); defaults = answer;
end
end

function [opt, message] = parse_ibr_dialog(opt, a, bus_ids, eligible, resource_ids)
message = '';
nums = cellfun(@str2double, a([1 2 6 7 11:17 19:21]));
if any(~isfinite(nums)), message = 'All required numeric IBR settings must be finite.'; return; end
opt.t_end = nums(1); opt.dt = nums(2);
[opt.plot_results, ok_plot] = parse_logical_text(a{3});
[opt.plot_visible, ok_vis] = parse_logical_text(a{4});
[opt.verbose, ok_verbose] = parse_logical_text(a{5});
opt.initial_gfm_count = nums(3); opt.initial_gfl_count = nums(4);
[initial, ok_i] = parse_index_text(a{8}); [iref, ok_ir] = parse_optional_scalar(a{9});
[enabled, ok_e] = parse_logical_text(a{10});
ev = struct('enabled', enabled, 'fault_bus', nums(5), 'Zf', nums(6) + 1i*nums(7), ...
    'fault_on', nums(8), 'fault_clear', nums(9), 'sg_trip', nums(10), ...
    'sg_on', nums(11), 'reference_resource_index', nums(12));
[post, ok_p] = parse_index_text(a{18}); ev.selected_gfm_indices = post;
dwell_s = nums(13); timeout_s = nums(14);
if opt.t_end <= 0 || opt.dt <= 0 || opt.dt > opt.t_end
    message = 'Require 0 < dt <= t_end.';
elseif opt.initial_gfm_count < 0 || opt.initial_gfm_count ~= fix(opt.initial_gfm_count) || ...
        opt.initial_gfm_count > numel(eligible), message = 'Initial GFM count is out of range.';
elseif opt.initial_gfl_count < 0 || opt.initial_gfl_count ~= fix(opt.initial_gfl_count) || ...
        opt.initial_gfm_count + opt.initial_gfl_count ~= numel(eligible)
    message = sprintf('Initial GFM+GFL counts must equal %d.', numel(eligible));
elseif ~ok_i || any(~ismember(initial, eligible)) || numel(unique(initial)) ~= numel(initial)
    message = sprintf('Initial indices must be unique members of %s (%s).', mat2str(eligible), strjoin(resource_ids(eligible), ','));
elseif ~isempty(initial) && numel(initial) ~= opt.initial_gfm_count
    message = 'Initial count must equal the explicit initial-index count.';
elseif ~ok_ir || (~isempty(iref) && ~ismember(iref, initial))
    message = 'Initial reference must belong to explicit initial GFM indices.';
elseif ~ok_e || ~ok_plot || ~ok_vis || ~ok_verbose
    message = 'Logical settings must be true/false.';
elseif dwell_s < 0 || timeout_s < 0 || dwell_s > timeout_s
    message = 'Require 0 <= synchronism dwell <= synchronism timeout.';
elseif enabled && (~ismember(ev.fault_bus, bus_ids) || abs(ev.Zf) < eps)
    message = 'Fault bus must be a valid external ID and Zf must be nonzero.';
elseif enabled && ~(ev.fault_on < ev.fault_clear && ev.fault_clear <= ev.sg_trip && ...
        ev.sg_trip < ev.sg_on && ev.sg_on <= opt.t_end)
    message = 'Require fault_on < fault_clear <= sg_trip < sg_on <= t_end.';
elseif enabled && (~ok_p || isempty(post) || any(~ismember(post, eligible)) || ...
        numel(unique(post)) ~= numel(post) || ~ismember(ev.reference_resource_index, post))
    message = 'Post-trip indices must be unique eligible resources and include the reference.';
end
if ~isempty(message), return; end
opt.initial_gfm_indices=initial;
opt.initial_reference_resource_index=iref;
opt.ibr_events=ev;
delay=option_value(opt,'delays_overrides',struct());
delay.dwell_s=dwell_s; delay.timeout_s=timeout_s;
opt.delays_overrides=delay;
end

function delay = ibr_dialog_delay_defaults(case_data, opt)
if ~isfield(case_data, 'synchronism') || ...
        ~all(isfield(case_data.synchronism, {'dwell_s', 'timeout_s'}))
    error('solve_case:ibr:dialogDefaults', ...
        'IBR case must define synchronism.dwell_s and synchronism.timeout_s.');
end
delay = struct('dwell_s', case_data.synchronism.dwell_s, ...
    'timeout_s', case_data.synchronism.timeout_s);
if isfield(opt, 'delays_overrides') && isstruct(opt.delays_overrides)
    if isfield(opt.delays_overrides, 'dwell_s') && ~isempty(opt.delays_overrides.dwell_s)
        delay.dwell_s = opt.delays_overrides.dwell_s;
    end
    if isfield(opt.delays_overrides, 'timeout_s') && ~isempty(opt.delays_overrides.timeout_s)
        delay.timeout_s = opt.delays_overrides.timeout_s;
    end
end
end

function [dlg,fields]=create_ibr_settings_dialog(case_label,bus_text,eligible,resource_ids,defaults)
% CREATE_IBR_SETTINGS_DIALOG Base-MATLAB three-column IBR settings editor.
dlg=dialog('Name',sprintf('IBR settings - %s',case_label), ...
    'Units','pixels','Position',[80 80 1240 720],'Resize','on', ...
    'WindowStyle','normal','CloseRequestFcn',@(src,~)finish_ibr_dialog(src,false));
setappdata(dlg,'submitted',false);

panels={ ...
    uipanel('Parent',dlg,'Title','Simulation','Units','normalized', ...
        'Position',[0.015 0.10 0.31 0.86]), ...
    uipanel('Parent',dlg,'Title','Initial IBR configuration','Units','normalized', ...
        'Position',[0.345 0.10 0.31 0.86]), ...
    uipanel('Parent',dlg,'Title','Events','Units','normalized', ...
        'Position',[0.675 0.10 0.31 0.86])};

sim_labels={'Simulation end t_end (s)','Fixed step dt (s)', ...
    'Generate/export two plots (true/false)','Show plot windows (true/false)', ...
    'Verbose run log (true/false)'};
initial_labels={sprintf('Initial GFM count [0..%d]',numel(eligible)), ...
    sprintf('Initial GFL count [0..%d]; sum=%d',numel(eligible),numel(eligible)), ...
    sprintf('GFM indices %s (%s); blank=count selector', ...
        mat2str(eligible),strjoin(resource_ids(eligible),',')), ...
    'GFM reference index (blank=automatic)'};
event_labels={'Enable fault/trip/reclose events (true/false)', ...
    sprintf('Fault bus (valid external IDs: %s)',bus_text),'Fault R (pu)','Fault X (pu)', ...
    'fault_on (s)','fault_clear (s)','sg_trip (s)', ...
    'sg_on / reclose request (s)','Post-trip GFM indices', ...
    'Post-trip GFM reference index','Synchronism dwell (s)', ...
    'Synchronism timeout (s)'};

fields=[add_ibr_dialog_fields(panels{1},sim_labels,defaults(1:5)); ...
    add_ibr_dialog_fields(panels{2},initial_labels,defaults(6:9)); ...
    add_ibr_dialog_fields(panels{3},event_labels,defaults(10:21))];
uicontrol('Parent',dlg,'Style','pushbutton','String','Run', ...
    'Units','normalized','Position',[0.40 0.025 0.09 0.05], ...
    'FontWeight','bold','Callback',@(src,~)finish_ibr_dialog(ancestor(src,'figure'),true));
uicontrol('Parent',dlg,'Style','pushbutton','String','Cancel', ...
    'Units','normalized','Position',[0.51 0.025 0.09 0.05], ...
    'Callback',@(src,~)finish_ibr_dialog(ancestor(src,'figure'),false));
movegui(dlg,'center');
end

function fields=add_ibr_dialog_fields(panel,labels,values)
n=numel(labels); fields=cell(n,1);
top=0.93; row_height=min(0.125,0.84/max(n,1));
for k=1:n
    y=top-(k-1)*row_height;
    uicontrol('Parent',panel,'Style','text','String',labels{k}, ...
        'Units','normalized','HorizontalAlignment','left', ...
        'Position',[0.035 y-0.012 0.57 0.055]);
    fields{k}=uicontrol('Parent',panel,'Style','edit','String',values{k}, ...
        'Units','normalized','BackgroundColor','white','HorizontalAlignment','left', ...
        'Position',[0.62 y-0.005 0.345 0.052]);
end
end

function finish_ibr_dialog(dlg, submitted)
if isgraphics(dlg)
    setappdata(dlg, 'submitted', logical(submitted));
    uiresume(dlg);
end
end

function ids = case_bus_ids(c)
if isfield(c, 'mpc') && isfield(c.mpc, 'bus'), ids = c.mpc.bus(:, 1);
elseif isfield(c, 'bus_data'), ids = c.bus_data(:, 1);
else error('solve_case:busIds', 'No bus IDs.'); end
ids = unique(ids(:), 'stable');
end

function text = format_bus_ids(ids)
ids = ids(:).';
if numel(ids) <= 24, text = strjoin(compose('%g', ids), ', ');
else text = sprintf('%s,... (%d buses)', strjoin(compose('%g', ids(1:20)), ', '), numel(ids)); end
end

function text = num_text(value), text = sprintf('%.12g', value); end
function text = index_text(value)
if isempty(value), text = ''; else, text = strjoin(compose('%d', reshape(value, 1, [])), ','); end
end
function [value, ok] = parse_index_text(text)
text = strtrim(text);
if isempty(text), value = []; ok = true; return; end
parts = regexp(text, '[,;\s]+', 'split'); value = str2double(parts);
ok = all(isfinite(value)) && all(value == fix(value));
if ok, value = reshape(value, 1, []); else, value = []; end
end
function [value, ok] = parse_optional_scalar(text)
if isempty(strtrim(text)), value = []; ok = true; return; end
value = str2double(text); ok = isscalar(value) && isfinite(value) && value == fix(value);
if ~ok, value = []; end
end
function text = logical_text(value), if value, text = 'true'; else, text = 'false'; end; end
function [value, ok] = parse_logical_text(text)
switch lower(strtrim(text))
    case {'true', '1', 'yes', 'on'}, value = true; ok = true;
    case {'false', '0', 'no', 'off'}, value = false; ok = true;
    otherwise, value = false; ok = false;
end
end
function value = option_value(s, name, default)
value = default; if isfield(s, name) && ~isempty(s.(name)), value = s.(name); end
end
