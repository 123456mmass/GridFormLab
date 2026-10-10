function app = launch(varargin)
%LAUNCH  Open the N-Bus Power Flow Studio GUI.
%   app = studio.launch() opens the studio window: case import with IBR
%   auto-detect, PF / SSSA / TS runs through the one pure dispatcher
%   (studio.run_analysis), and a PGAz-faithful four-band layout on uifigure.
%
%   app = studio.launch('Visible', 'off') builds the window hidden (smoke
%   tests drive it headless).  State lives on fig.UserData.app -- the
%   pattern +pfapp/run_powerflow_gui.m and the wizard figure already use.
%   Nothing is written to the base workspace, nothing is evalc-captured,
%   and no root-global appdata is used, so a clearvars cannot break it.
%
%   Only PF, SSSA and TS run here (the owner: "เอาหนักๆแค่นี้ก่อน" -- heavy
%   on these first).  Failures are rendered, never thrown past the UI: a
%   non-converging power flow paints its reason and logs
%   STATUS: FAILED CLOSED; a TS error surfaces e.identifier and e.message
%   verbatim.
%
%   Visual language after PGAz v1.3, © 2024 PSDSC Research Center, KMITL —
%   used with acknowledgement; this application is an independent
%   implementation.  PGAz is a visual reference only; no PGAz code is
%   reproduced -- this app is written from scratch on uifigure, which PGAz
%   does not use at all.
%
%   See also: studio.RUN_ANALYSIS, studio.DETECT_RESOURCES,
%   studio.CASE_CATALOG, studio.ui.BUILD_LAYOUT.

pf_init_paths();

p = inputParser;
addParameter(p, 'Visible', 'on', @(x) ischar(x) || isstring(x));
parse(p, varargin{:});
visible = char(p.Results.Visible);

c = studio.ui.layout_constants();
fig = uifigure('Name', 'N-Bus Power Flow Studio', ...
    'NumberTitle', 'off', ...
    'Position', c.figure_position, ...
    'Color', c.bg, ...
    'Resize', 'on', ...
    'Visible', 'off');

app = struct();
app.fig = fig;
app.axes = [];
app.table = [];
app.log_area = [];
app.overview_area = [];
app.catalog = [];
app.analysis = 'pf';
app.case_id = '';
app.case_data = [];
app.resource_report = [];
app.event_files = struct('id', {}, 'label', {});
app.event_id = 'None';
app.event_def = [];
app.event_ok = false;
app.last_result = [];
app.running = false;
app.hover = struct('index', 0);
app.bar = struct();
app.outdir = fullfile(pwd, 'tmp', 'studio_diagnostics');

app = studio.ui.build_layout(fig, app);
fig.UserData.app = app;

fig.Visible = visible;
end
