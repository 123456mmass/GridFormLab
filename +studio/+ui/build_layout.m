function app = build_layout(fig, app)
%BUILD_LAYOUT  Four-band PGAz-faithful studio layout on uifigure.
%   app = studio.ui.build_layout(fig, app) populates FIG with the four bands
%   and returns the app struct carrying every handle:
%
%     band 1  ~95 px icon toolbar      navy / white-"Data:" / navy
%     band 2  middle-left              navy 'Overview' header over a
%                                      read-only multiline box + results
%     band 2  middle-right             plot axes over a 3x3 grid of 75x25
%                                      buttons + the eigenvalue box
%     band 3  bottom                   navy 'Output' header over a
%                                      read-only log + copyright strip
%
%   All colours and fonts come from studio.ui.layout_constants.  State lives
%   on fig.UserData.app only (no assignin/evalin/base workspace, no root
%   appdata).  Every callback re-reads the live app from fig.UserData and
%   writes it back.
%
%   Plots never pop up: results draw into the embedded axes; standalone
%   figures are created 'Visible','off' and shown only when the user clicks
%   Plots/Expand in an interactive session.
%
%   See also: studio.ui.LAYOUT_CONSTANTS, studio.LAUNCH.

c = studio.ui.layout_constants();
W = c.fig_w; H = c.fig_h;

% ============================ BAND 1: toolbar ===========================
t1y = H - c.strip_h;                     % navy title strip (top)
t2y = H - 2 * c.strip_h;                 % white "Data:" strip
t3y = H - 3 * c.strip_h;                 % navy action/status strip

uilabel(fig, 'Text', '   N-Bus Power Flow Studio', ...
    'FontName', c.font_name, 'FontSize', c.font_size + 1, ...
    'FontColor', c.white, 'BackgroundColor', c.navy, ...
    'Position', [0 t1y W c.strip_h]);

app.about_button = studio.ui.icon_button(fig, 'About', '', ...
    @(src, evt) do_about(fig));
app.about_button.Position = [W - 85 t1y + 3 75 25];

uilabel(fig, 'Text', 'Data:', 'FontName', c.font_name, 'FontSize', c.font_size, ...
    'FontColor', c.black, 'BackgroundColor', c.bg, ...
    'Position', [12 t2y 40 c.strip_h]);

app.catalog = studio.case_catalog();
case_labels = {app.catalog.label};
app.case_dropdown = uidropdown(fig, 'Items', case_labels, ...
    'Value', case_labels{1}, ...
    'FontName', c.font_name, 'FontSize', c.font_size, ...
    'Position', [56 t2y + 3 300 25], ...
    'ValueChangedFcn', @(src, evt) do_case_changed(fig));

uilabel(fig, 'Text', 'Event:', 'FontName', c.font_name, 'FontSize', c.font_size, ...
    'FontColor', c.black, 'BackgroundColor', c.bg, ...
    'Position', [372 t2y 45 c.strip_h]);

[app.event_files, ev_note] = list_event_defs();
ev_items = [{'None'}, {app.event_files.label}];
ev_ids = [{'None'}, {app.event_files.id}];
app.event_dropdown = uidropdown(fig, 'Items', ev_items, 'ItemsData', ev_ids, ...
    'Value', 'None', ...
    'FontName', c.font_name, 'FontSize', c.font_size, ...
    'Position', [420 t2y + 3 280 25], ...
    'ValueChangedFcn', @(src, evt) do_event_changed(fig));

app.save_diag_checkbox = uicheckbox(fig, 'Text', 'Save diagnostics on Run', ...
    'FontName', c.font_name, 'FontSize', c.font_size, ...
    'Position', [716 t2y + 5 220 25]);

app.status_label = uilabel(fig, 'Text', 'Ready.', ...
    'FontName', c.font_name, 'FontSize', c.font_size, ...
    'FontColor', c.white, 'BackgroundColor', c.navy, ...
    'Position', [12 t3y 900 c.strip_h]);
app.bar = studio.ui.segment_bar(fig);
app.bar.ax.Position = [W - 220 t3y + 2 200 c.strip_h - 4];

% ============================ BAND 2: middle ============================
mid_top = t3y - c.band_gap;
ov_hdr_y = mid_top - c.header_h;
uilabel(fig, 'Text', '   Overview', 'FontName', c.font_name, ...
    'FontSize', c.font_size, 'FontColor', c.white, 'BackgroundColor', c.navy, ...
    'Position', [8 ov_hdr_y 460 c.header_h]);
app.overview_area = studio.ui.readonly_textarea(fig, ...
    'Position', [8 ov_hdr_y - 164 460 156], 'Tag', 'overview');

res_hdr_y = ov_hdr_y - 164 - c.band_gap - c.header_h;
uilabel(fig, 'Text', '   Results', 'FontName', c.font_name, ...
    'FontSize', c.font_size, 'FontColor', c.white, 'BackgroundColor', c.navy, ...
    'Position', [8 res_hdr_y 460 c.header_h]);
app.table = uitable(fig, 'Position', [8 res_hdr_y - 210 460 202], ...
    'ColumnName', {'Bus', 'V (pu)', 'Angle (deg)'}, 'Data', cell(0, 3), ...
    'Tag', 'results');

app.axes = uiaxes(fig, 'Position', [484 330 688 328]);
title(app.axes, 'Results');
xlabel(app.axes, 'x'); ylabel(app.axes, 'y');
studio.ui.expandable_axes(app.axes);

btn_labels = {'Run PF', 'Run SSSA', 'Run TS'; ...
              'Plots', 'Save', 'Expand'; ...
              'Clear Log', 'About', 'Close'};
btn_cb = {@(s, e) do_run(fig, 'pf'), @(s, e) do_run(fig, 'sssa'), @(s, e) do_run(fig, 'ts'); ...
          @(s, e) do_plots(fig), @(s, e) do_save(fig), @(s, e) do_expand(fig); ...
          @(s, e) do_clear_log(fig), @(s, e) do_about(fig), @(s, e) do_close(fig)};
grid_x0 = 484; grid_y0 = 230;
app.grid_buttons = gobjects(c.grid_n, c.grid_n);
for r = 1:c.grid_n
    for col = 1:c.grid_n
        b = studio.ui.icon_button(fig, btn_labels{r, col}, '', btn_cb{r, col});
        b.Position = [grid_x0 + (col - 1) * c.button_pitch(1), ...
                      grid_y0 + (c.grid_n - r) * c.button_pitch(2), ...
                      c.button_size(1), c.button_size(2)];
        app.grid_buttons(r, col) = b;
    end
end
app.hover = studio.ui.install_hover(fig, app.grid_buttons(:));

app.eigen_box = studio.ui.readonly_textarea(fig, 'Mono', true, ...
    'Position', [744 230 428 91], 'Tag', 'eigenvalues');

% ============================ BAND 3: output ============================
uilabel(fig, 'Text', '   Output', 'FontName', c.font_name, ...
    'FontSize', c.font_size, 'FontColor', c.white, 'BackgroundColor', c.navy, ...
    'Position', [8 192 1164 c.header_h]);
app.log_area = studio.ui.readonly_textarea(fig, ...
    'Position', [8 42 1164 146], 'Tag', 'log');
uilabel(fig, 'Text', ['   ' c.copyright_text], ...
    'FontName', c.font_name, 'FontSize', c.copyright_font_size, ...
    'FontColor', c.text_grey, 'BackgroundColor', c.bg, ...
    'Position', [8 8 1164 28]);

% ============================ actions ==================================
app.do = struct( ...
    'case_changed', @() do_case_changed(fig), ...
    'event_changed', @() do_event_changed(fig), ...
    'run_pf', @() do_run(fig, 'pf'), ...
    'run_sssa', @() do_run(fig, 'sssa'), ...
    'run_ts', @() do_run(fig, 'ts'), ...
    'plots', @() do_plots(fig), ...
    'save', @() do_save(fig), ...
    'expand', @() do_expand(fig), ...
    'clear_log', @() do_clear_log(fig), ...
    'about', @() do_about(fig), ...
    'close', @() do_close(fig));

fig.UserData.app = app;
studio.ui.append_log(app.log_area, 'Studio ready. Select a case to import it.');
if ~isempty(ev_note)
    studio.ui.append_log(app.log_area, ev_note);
end
app = do_case_changed(fig);   % initial import + resource detection
end

% =======================================================================
%  callbacks (all re-read the live app from fig.UserData)
% =======================================================================
function app = do_case_changed(fig)
app = fig.UserData.app;
if app.running, return; end
label = app.case_dropdown.Value;
idx = find(strcmp(label, {app.catalog.label}), 1);
if isempty(idx)
    studio.ui.append_log(app.log_area, sprintf('IMPORT FAILED: unknown case label %s.', label));
    fig.UserData.app = app;
    return;
end
entry = app.catalog(idx);
case_data = entry.loader();
report = studio.detect_resources(case_data);
app.case_id = entry.id;
app.case_data = case_data;
app.resource_report = report;
app.last_result = [];
app.table.Data = cell(0, 3);
cla(app.axes);
app.eigen_box.Value = {''};

overview = studio.format_overview(entry.id, entry.label, case_data, report, ...
    event_overview_lines(app));
app.overview_area.Value = overview;

studio.ui.append_log(app.log_area, sprintf( ...
    'IMPORT %s: %d IBR / %d SG (authority=%s)', entry.id, ...
    report.n_ibr, report.n_sg, report.authority));
if report.has_ibr
    % The owner asked for an alert with the IBR/SG counts on import.  The
    % overview + log always carry the counts; a modal alert appears only
    % when IBRs are detected and the session can show one (never headless).
    msg = sprintf('%s\n%s', report.headline, report.detail);
    if usejava('desktop') && feature('ShowFigureWindows')
        try
            uialert(fig, msg, 'IBR units detected');
        catch
        end
    end
end
set_status(app, 'Ready.', false);
studio.ui.segment_bar(app.bar, 0);
fig.UserData.app = app;
% Re-validate the currently selected event against the NEW case.  The event
% dropdown fires only on its own change, so the sequence "pick ne39 event
% while ieee14 is imported, then import ne39" left event_ok=false forever:
% validate had judged bus 16 against a 14-bus case and the owner's next RUN
% died on studio:event:NotReady even though the event was written for the
% case now loaded.  The event stays rejected-with-reason when it genuinely
% does not match the new case (wrong case_id or a bus the case lacks).
do_event_changed(app.fig);
end

function app = do_event_changed(fig)
app = fig.UserData.app;
if app.running, return; end
eid = app.event_dropdown.Value;
app.event_id = eid;
app.event_def = [];
app.event_ok = false;
if strcmp(eid, 'None')
    studio.ui.append_log(app.log_area, 'EVENT: none (TS runs event-free).');
else
    % The events package ABI (as delivered in +events/):
    %   events.load(id)                   -> event struct (throws events:load:*)
    %   events.validate(ev, case_data, analysis) -> the record, or throws
    %   events.resolve(ev, case_data, opt) -> opt with fault_enabled,
    %     fault_bus, t_fault, t_clear, Zf folded in (t_clear DERIVED as
    %     t_fault + ds).  No parallel event implementation lives here.
    try
        ev = events.load(eid);
        ev = events.validate(ev, app.case_data, 'ts');
        % UI-level guard: an event file names the case it was written for.
        if isfield(ev, 'case_id') && ~isempty(ev.case_id) && ...
                ~strcmp(char(ev.case_id), app.case_id)
            error('studio:event:CaseMismatch', ...
                'Event %s targets case %s, not %s.', eid, char(ev.case_id), app.case_id);
        end
        app.event_def = ev;
        app.event_ok = true;
        studio.ui.append_log(app.log_area, sprintf('EVENT: %s accepted.', eid));
    catch e
        studio.ui.append_log(app.log_area, sprintf( ...
            'EVENT: %s REJECTED (id=%s). Run stays closed.', eid, e.identifier));
        studio.ui.append_log(app.log_area, sprintf('        msg=%s', e.message));
    end
end
fig.UserData.app = app;
if ~isempty(app.case_data)
    lines = event_overview_lines(app);
    ov = studio.format_overview(app.case_id, ...
        app.case_dropdown.Value, app.case_data, app.resource_report, lines);
    app = fig.UserData.app;
    app.overview_area.Value = ov;
end
fig.UserData.app = app;
end

function app = do_run(fig, analysis)
app = fig.UserData.app;
if app.running
    studio.ui.append_log(app.log_area, 'STATUS: BUSY (a run is already in progress).');
    fig.UserData.app = app;
    return;
end
app.running = true;
app.analysis = analysis;
fig.UserData.app = app;
set_status(app, sprintf('Running %s ...', upper(analysis)), false);
studio.ui.segment_bar(app.bar, 0.1);
studio.ui.append_log(app.log_area, sprintf('RUN %s on %s ...', upper(analysis), app.case_id));
try
    opt = build_run_opt(app, analysis);
    fig.UserData.app = app;
    result = studio.run_analysis(analysis, app.case_data, opt);
    app = fig.UserData.app;
    app.last_result = result;
    fig.UserData.app = app;   % persist before any later re-read
    studio.ui.segment_bar(app.bar, 0.8);
    paint_result(app, analysis, result);
    failed = strcmp(analysis, 'pf') && isstruct(result) && ...
        isfield(result, 'converged') && ~logical(result.converged);
    if failed
        reason = 'unknown';
        if isfield(result, 'reason') && ~isempty(result.reason)
            reason = char(result.reason);
        end
        set_status(app, sprintf('PF failed: %s', reason), true);
        studio.ui.append_log(app.log_area, sprintf('reason: %s', reason));
        studio.ui.append_log(app.log_area, 'STATUS: FAILED CLOSED');
    else
        set_status(app, sprintf('%s complete.', upper(analysis)), false);
        studio.ui.append_log(app.log_area, 'STATUS: COMPLETE');
    end
    if isfield(opt, 'save_diagnostics') && logical(opt.save_diagnostics)
        files = studio.save_diagnostics(result, app.outdir, analysis);
        for k = 1:numel(files)
            studio.ui.append_log(app.log_area, sprintf('Saved diagnostics: %s', files{k}));
        end
    end
catch e
    app = fig.UserData.app;
    % Failures are rendered, not thrown.  TS/SSSA errors surface the
    % identifier and message verbatim -- never a generic phrase.
    set_status(app, sprintf('Failed: %s', e.identifier), true);
    studio.ui.append_log(app.log_area, sprintf('ERROR id : %s', e.identifier));
    studio.ui.append_log(app.log_area, sprintf('ERROR msg: %s', e.message));
    studio.ui.append_log(app.log_area, 'STATUS: FAILED CLOSED');
end
app = fig.UserData.app;
app.running = false;
fig.UserData.app = app;
studio.ui.segment_bar(app.bar, 1);
end

function app = do_plots(fig)
app = fig.UserData.app;
if isempty(app.last_result)
    studio.ui.append_log(app.log_area, 'PLOTS: nothing to plot yet.');
    fig.UserData.app = app;
    return;
end
% Standalone copy of the embedded axes, on request only.  The figure is
% created 'Visible','off' and shown only in an interactive session, so a
% headless drive never leaves a window on screen.
studio.ui.expandable_axes(app.axes, true);
studio.ui.append_log(app.log_area, 'PLOTS: opened the current axes in its own window.');
fig.UserData.app = app;
end

function app = do_save(fig)
app = fig.UserData.app;
if isempty(app.last_result)
    studio.ui.append_log(app.log_area, 'SAVE: nothing to save yet.');
    fig.UserData.app = app;
    return;
end
files = studio.save_diagnostics(app.last_result, app.outdir, app.analysis);
if isempty(files)
    studio.ui.append_log(app.log_area, 'SAVE: no numeric diagnostics in the last result.');
else
    for k = 1:numel(files)
        studio.ui.append_log(app.log_area, sprintf('Saved diagnostics: %s', files{k}));
    end
end
fig.UserData.app = app;
end

function app = do_expand(fig)
app = fig.UserData.app;
if isempty(app.axes) || ~isgraphics(app.axes)
    fig.UserData.app = app;
    return;
end
% Same path as the double-click handler on the axes.
studio.ui.expandable_axes(app.axes, true);
studio.ui.append_log(app.log_area, 'EXPAND: opened the current axes in its own window.');
fig.UserData.app = app;
end

function app = do_clear_log(fig)
app = fig.UserData.app;
app.log_area.Value = {''};
fig.UserData.app = app;
end

function app = do_about(fig)
app = fig.UserData.app;
studio.ui.append_log(app.log_area, ...
    'N-Bus Power Flow Studio -- PF / SSSA / TS, base MATLAB, in-house solvers.');
studio.ui.append_log(app.log_area, ...
    'Visual language after PGAz v1.3, (c) 2024 PSDSC Research Center, KMITL - used with acknowledgement; this application is an independent implementation.');
fig.UserData.app = app;
end

function do_close(fig)
if isgraphics(fig)
    delete(fig);
end
end

% =======================================================================
%  helpers
% =======================================================================
function opt = build_run_opt(app, analysis)
entry = app.catalog(strcmp({app.catalog.id}, app.case_id));
if isempty(entry)
    error('studio:build_layout:noCase', 'No imported case; select a case first.');
end
opt = entry.run_opts.(analysis);
% Never pop figures from a run button; plots are on demand only.
opt.verbose = false;
opt.plot_results = false;
switch analysis
    case 'ts'
        if strcmp(app.event_id, 'None')
            % Explicit event-free: TS defaults contain fault times, so
            % merely omitting fields would still create a hidden fault.
            opt.fault_enabled = false;
        elseif ~app.event_ok
            error('studio:event:NotReady', ...
                'Event %s is selected but not validated; refusing to run with a hidden default fault.', ...
                app.event_id);
        else
            % events.resolve folds the event into the launcher ABI:
            % fault_enabled, fault_bus, t_fault, t_clear, Zf (t_clear is
            % DERIVED as t_fault + ds and never stored in the event file).
            resolved = events.resolve(app.event_def, app.case_data, ...
                struct('analysis', 'ts'));
            names = setdiff(fieldnames(resolved), {'analysis'});
            for k = 1:numel(names)
                opt.(names{k}) = resolved.(names{k});
            end
            opt.fault_enabled = true;
        end
end
if app.save_diag_checkbox.Value
    opt.save_diagnostics = true;
else
    opt.save_diagnostics = false;
end
end

function paint_result(app, analysis, result)
switch analysis
    case 'pf'
        if isfield(result, 'bus_voltage')
            v = result.bus_voltage(:);
            if isfield(result, 'external_bus_ids')
                ids = result.external_bus_ids(:);
            else
                ids = (1:numel(v)).';
            end
            a = [];
            if isfield(result, 'bus_angle_deg'), a = result.bus_angle_deg(:); end
            data = cell(numel(v), 3);
            for k = 1:numel(v)
                data{k, 1} = ids(k);
                data{k, 2} = v(k);
                if ~isempty(a), data{k, 3} = a(k); end
            end
            app.table.ColumnName = {'Bus', 'V (pu)', 'Angle (deg)'};
            app.table.Data = data;
            cla(app.axes);
            plot(app.axes, ids, v, '-o');
            title(app.axes, sprintf('Voltage profile (%s)', app.case_id));
            xlabel(app.axes, 'Bus'); ylabel(app.axes, '|V| (pu)');
            grid(app.axes, 'on');
            app.eigen_box.Value = {'n/a for power flow'};
        end
    case 'sssa'
        lam = [];
        if isfield(result, 'eigenvalues'), lam = result.eigenvalues(:); end
        if isempty(lam) && isfield(result, 'reduced_eigenvalues')
            lam = result.reduced_eigenvalues(:);
        end
        if ~isempty(lam)
            data = cell(numel(lam), 5);
            txt = cell(numel(lam), 1);
            for k = 1:numel(lam)
                re_k = real(lam(k)); im_k = imag(lam(k));
                fhz = abs(im_k) / (2 * pi);
                zet = -re_k / (abs(lam(k)) + eps);
                data{k, 1} = k;
                data{k, 2} = re_k;
                data{k, 3} = im_k;
                data{k, 4} = fhz;
                data{k, 5} = zet;
                txt{k} = sprintf('%3d  %+12.5e  %+12.5e  %10.3e  %8.3f', ...
                    k, re_k, im_k, fhz, zet);
            end
            app.table.ColumnName = {'Mode', 'Real (1/s)', 'Imag (1/s)', 'f (Hz)', 'zeta'};
            app.table.Data = data;
            cla(app.axes);
            plot(app.axes, real(lam), imag(lam), 'x');
            title(app.axes, sprintf('Eigenvalues (%s)', app.case_id));
            xlabel(app.axes, 'Re(\lambda) (1/s)'); ylabel(app.axes, 'Im(\lambda) (1/s)');
            grid(app.axes, 'on');
            app.eigen_box.Value = txt;
        end
    case 'ts'
        if isfield(result, 't') && isfield(result, 'Vbus')
            % ts_simulate stores time along dim 1: Vbus is [nt x nb],
            % omega [nt x ng].
            t = result.t(:);
            vmin = min(result.Vbus, [], 2);
            if isfield(result, 'omega') && ~isempty(result.omega)
                if isfield(result, 'omega_is_deviation') && result.omega_is_deviation
                    dw = max(abs(result.omega), [], 2);
                else
                    dw = max(abs(result.omega - 1), [], 2);
                end
            else
                dw = nan(size(t));
            end
            nshow = min(200, numel(t));
            sel = round(linspace(1, numel(t), nshow));
            data = cell(nshow, 3);
            for k = 1:nshow
                data{k, 1} = t(sel(k));
                data{k, 2} = vmin(sel(k));
                data{k, 3} = dw(sel(k));
            end
            app.table.ColumnName = {'t (s)', 'min |V| (pu)', 'max |dw| (pu)'};
            app.table.Data = data;
            cla(app.axes);
            plot(app.axes, t, dw);
            title(app.axes, sprintf('Speed deviation (%s)', app.case_id));
            xlabel(app.axes, 't (s)'); ylabel(app.axes, 'max |\Delta\omega| (pu)');
            grid(app.axes, 'on');
            app.eigen_box.Value = {'n/a for time-domain simulation'};
        end
end
end

function set_status(app, text, is_error)
c = studio.ui.layout_constants();
app.status_label.Text = text;
if is_error
    app.status_label.FontColor = [1 1 1];
    app.status_label.BackgroundColor = [0.75 0 0];
else
    app.status_label.FontColor = c.white;
    app.status_label.BackgroundColor = c.navy;
end
end

function lines = event_overview_lines(app)
lines = {};
if strcmp(app.event_id, 'None')
    lines{end+1} = 'Selected: none (event-free).';
    return;
end
lines{end+1} = sprintf('Selected: %s', app.event_id);
if app.event_ok
    lines{end+1} = 'Status: validated.';
    if isstruct(app.event_def) && isfield(app.event_def, 'ds')
        % The event def's clearing gap is echoed here (overview band).
        lines{end+1} = sprintf('ds: %g s', app.event_def.ds);
    end
    try
        d = events.describe(app.event_def);
        for k = 1:numel(d)
            lines{end+1} = char(d{k}); %#ok<AGROW>
        end
    catch
    end
else
    lines{end+1} = 'Status: NOT validated (runs stay closed).';
end
end

function [defs, note] = list_event_defs()
% Offer the hand-editable event files through events.list() (lazy, pure).
% The copy-me template entry is not offered in the dropdown.  If the
% package is unavailable the list fails soft (empty offer list + logged
% note) -- this layer never implements a parallel event registry.
defs = struct('id', {}, 'label', {});
note = ['EVENTS: the events package is not available; event selection is ' ...
    'disabled until +events/ and events/ are on the path.'];
try
    raw = events.list();
    for k = 1:numel(raw)
        e = raw(k);
        if isfield(e, 'is_template') && e.is_template
            continue
        end
        d = norm_def(e);
        if ~isempty(d.id)
            defs(end+1, 1) = d; %#ok<AGROW>
        end
    end
    note = '';
catch
    % keep the fail-soft note
end
end

function d = norm_def(raw)
d = struct('id', '', 'label', '');
if isfield(raw, 'id'), d.id = char(raw.id); end
if isfield(raw, 'label')
    d.label = char(raw.label);
elseif isfield(raw, 'name')
    d.label = char(raw.name);
else
    d.label = d.id;
end
if isempty(d.id) && isfield(raw, 'name'), d.id = char(raw.name); end
end
