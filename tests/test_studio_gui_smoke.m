function tests = test_studio_gui_smoke()
%TEST_STUDIO_GUI_SMOKE  Headless drive of the Studio GUI + IBR auto-detect.
%   Builds the studio with fig.Visible='off', drives every action, and
%   asserts:
%     - the case offer list is exactly ieee14 and ne39 (gui_visible filter)
%     - import auto-detects resources and reports IBR/SG counts
%       (ne39 -> 0 IBR / 10 SG, ieee14 -> 0 / 5, ieee14_switch -> 4 / 1)
%     - PF / SSSA / TS runs populate table + log without throwing
%     - ZERO figures with Visible='on' exist after driving every action
%       (findall(0,'Type','figure') also returns invisible ones -- filter
%       on Visible, as in test_gui_smoke.m)
%
%   No uiconfirm, no modal dialogs in the drive path.
tests = functiontests(localfunctions);
end

%% ---- detector resolution order ----
function test_detect_resource_table_authority(tc)
% Path 1: case_data.resources (the build_hybrid_scenario shape).
r = synthetic_resources();
rep = studio.detect_resources(r);
tc.verifyEqual(rep.authority, 'resource_table');
tc.verifyTrue(rep.is_device_evidence);
tc.verifyEqual(rep.n_ibr, 3);
tc.verifyEqual(rep.n_sg, 1);
tc.verifyTrue(rep.complete);
tc.verifyTrue(rep.has_ibr);
tc.verifyTrue(contains(rep.headline, 'contains'), ...
    'device evidence says "contains", not "declares"');
% GFM capability counted only from can_switch_mode + gfm in supported_modes.
tc.verifyTrue(contains(rep.detail, 'GFM-capable IBR units: 1'), ...
    'exactly one IBR is GFM-capable in the synthetic table');
end

function test_detect_no_default_to_ibr_on_missing_type(tc)
% A missing resource_type increments n_unknown and must NOT be counted as
% an IBR (the selector stack's default-to-'ibr' would over-count).
% Case A: empty resource_type on one entry of the 4-entry table.
r = synthetic_resources();
r.resources(1).resource_type = '';
rep = studio.detect_resources(r);
tc.verifyEqual(rep.n_ibr, 3, 'empty resource_type must not raise n_ibr');
tc.verifyEqual(rep.n_unknown, 1);
tc.verifyFalse(rep.complete, 'unknown resource_type makes counts incomplete');

% Case B: the field is absent from the entry entirely.
s = struct('resource_id', 'X1', 'bus_id', 2);
rep = studio.detect_resources(struct('resources', s));
tc.verifyEqual(rep.n_ibr, 0, 'absent resource_type must not raise n_ibr');
tc.verifyEqual(rep.n_unknown, 1);
tc.verifyFalse(rep.complete);
end

function test_detect_bus_role_label_authority(tc)
% Path 2: bus_role labels (SLACK/PV/PQ/GFM/GFL). Labels are presentational.
r = struct();
r.bus_role = ["SLACK"; "PV"; "GFL"; "GFM"; "PQ"];
r.bus_data = zeros(5, 2);
rep = studio.detect_resources(r);
tc.verifyEqual(rep.authority, 'bus_role_label');
tc.verifyFalse(rep.is_device_evidence);
tc.verifyEqual(rep.n_ibr, 2);
tc.verifyEqual(rep.n_sg, 2);
tc.verifyTrue(contains(rep.headline, 'declares'), ...
    'bus_role evidence says "declares", not "contains"');
tc.verifyTrue(contains(rep.detail, 'do not prove a device exists'));
tc.verifyTrue(contains(rep.detail, 'GFM capability: not declared'), ...
    'GFM capability is not declared without device evidence');
end

function test_detect_generator_bus_fallback(tc)
% Path 3: generator buses alone.
r = struct();
r.bus_data = [1 1; 2 2; 3 3; 4 2; 5 3];
rep = studio.detect_resources(r);
tc.verifyEqual(rep.authority, 'generator_bus_type');
tc.verifyFalse(rep.is_device_evidence);
tc.verifyEqual(rep.n_ibr, 0);
tc.verifyEqual(rep.n_sg, 3);
end

function test_detect_real_cases(tc)
pf_init_paths();
ne39 = cases.case_ne39();
rep = studio.detect_resources(ne39);
tc.verifyEqual(rep.n_ibr, 0, 'ne39 declares 0 IBR');
tc.verifyEqual(rep.n_sg, 10, 'ne39 declares 10 SG');

ie14 = cases.case_ieee14bus();
rep = studio.detect_resources(ie14);
tc.verifyEqual(rep.n_ibr, 0, 'ieee14 declares 0 IBR');
tc.verifyEqual(rep.n_sg, 5, 'ieee14 declares 5 SG');

sw = cases.case_ieee14bus_eecon49_switch();
rep = studio.detect_resources(sw);
tc.verifyEqual(rep.n_ibr, 4, 'ieee14_switch declares 4 IBR');
tc.verifyEqual(rep.n_sg, 1, 'ieee14_switch declares 1 SG');
tc.verifyFalse(rep.is_device_evidence, 'bus_role labels are not device evidence');
tc.verifyTrue(contains(rep.detail, 'GFM capability: not declared'), ...
    'GFM capability not declared from labels alone');
end

%% ---- headless GUI drive ----
function test_gui_drive_no_visible_figures(tc)
pf_init_paths();
app = studio.launch('Visible', 'off');
fig = app.fig;
tc.verifyTrue(isgraphics(fig), 'studio figure created');

% Offer list: exactly the two production networks.
ids = sort({app.catalog.id});
tc.verifyEqual(ids, {'ieee14', 'ne39'}, 'catalog offers exactly ieee14 and ne39');

% --- import ne39: 0 IBR / 10 SG ---
app.case_dropdown.Value = 'IEEE 39-bus New England (10-machine)';
app.do.case_changed();
app = fig.UserData.app;
tc.verifyEqual(app.case_id, 'ne39');
tc.verifyEqual(app.resource_report.n_ibr, 0);
tc.verifyEqual(app.resource_report.n_sg, 10);
ov = app.overview_area.Value;
tc.verifyTrue(any(contains(ov, '0 IBR unit(s) and 10 synchronous generator(s)')), ...
    'overview prints 0 IBR / 10 SG for ne39');

% --- import ieee14: 0 IBR / 5 SG ---
app.case_dropdown.Value = 'IEEE 14-bus';
app.do.case_changed();
app = fig.UserData.app;
tc.verifyEqual(app.case_id, 'ieee14');
tc.verifyEqual(app.resource_report.n_ibr, 0);
tc.verifyEqual(app.resource_report.n_sg, 5);

% --- event dropdown: real event files offered (template excluded) ---
ev_ids = app.event_dropdown.ItemsData;
tc.verifyTrue(any(strcmp(ev_ids, 'ne39_bus_fault')), ...
    'the ne39 event file is offered in the dropdown');
tc.verifyFalse(any(strcmp(ev_ids, 'template')), ...
    'the copy-me template is not offered');
app.event_dropdown.Value = 'None';
app.do.event_changed();
app = fig.UserData.app;
tc.verifyFalse(app.event_ok);

% --- run PF ---
app.do.run_pf();
app = fig.UserData.app;
tc.verifyFalse(app.running, 'running flag cleared after PF');
tc.verifyTrue(isstruct(app.last_result) && isfield(app.last_result, 'converged'), ...
    'PF result stored');
tc.verifyTrue(app.last_result.converged, 'PF on ieee14 converges');
tc.verifyTrue(size(app.table.Data, 1) > 0, 'PF table populated');
logv = [app.log_area.Value{:}];
tc.verifyTrue(contains(logv, 'STATUS: COMPLETE'), 'PF logs STATUS: COMPLETE');

% --- run SSSA ---
app.do.run_sssa();
app = fig.UserData.app;
tc.verifyTrue(isstruct(app.last_result) && isfield(app.last_result, 'eigenvalues'), ...
    'SSSA result stored');
tc.verifyTrue(size(app.eigen_box.Value, 1) > 0, 'eigenvalue box populated');

% --- run TS (event-free) ---
app.do.run_ts();
app = fig.UserData.app;
tc.verifyTrue(isstruct(app.last_result) && isfield(app.last_result, 't'), ...
    'TS result stored');
tc.verifyTrue(numel(app.last_result.t) > 1, 'TS produced samples');

% --- ne39 with its event file: validated, ds echoed, TS runs ---
app.case_dropdown.Value = 'IEEE 39-bus New England (10-machine)';
app.do.case_changed();
app = fig.UserData.app;
app.event_dropdown.Value = 'ne39_bus_fault';
app.do.event_changed();
app = fig.UserData.app;
tc.verifyTrue(app.event_ok, 'ne39_bus_fault validates against the ne39 case');
ov = app.overview_area.Value;
tc.verifyTrue(any(contains(ov, 'ds:')), 'ds echoed in the Overview band');
app.do.run_ts();
app = fig.UserData.app;
tc.verifyTrue(isstruct(app.last_result) && isfield(app.last_result, 't'), ...
    'TS with the ne39 event produced a result');
logv = [app.log_area.Value{:}];
tc.verifyTrue(contains(logv, 'STATUS: COMPLETE'), 'TS with event logs COMPLETE');

% --- plots / expand / save / clear / about ---
app.outdir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'tmp', 'studio_gui_smoke_out');
fig.UserData.app = app;
if exist(app.outdir, 'dir'), rmdir(app.outdir, 's'); end
app.do.plots();
app.do.expand();
app.do.save();
app = fig.UserData.app;
tc.verifyTrue(exist(fullfile(app.outdir, 'pf_bus_results.csv'), 'file') == 2 || ...
    exist(fullfile(app.outdir, 'ts_samples.csv'), 'file') == 2 || ...
    exist(fullfile(app.outdir, 'sssa_eigenvalues.csv'), 'file') == 2, ...
    'save diagnostics wrote at least one CSV');
app.do.clear_log();
app.do.about();

% --- THE assertion: no figure window may appear unless asked for ---
leaked = findall(0, 'Type', 'figure', 'Visible', 'on');
tc.verifyEmpty(leaked, sprintf( ...
    'zero visible figures after driving every action (found %d)', numel(leaked)));

app.do.close();
if exist(app.outdir, 'dir'), rmdir(app.outdir, 's'); end
end

%% ---- event selected but not validated fails closed ----
function test_run_refuses_unvalidated_event(tc)
pf_init_paths();
app = studio.launch('Visible', 'off');
fig = app.fig;
app.case_dropdown.Value = 'IEEE 14-bus';
app.do.case_changed();
app = fig.UserData.app;
app.event_id = 'phantom';
app.event_ok = false;
fig.UserData.app = app;
app.do.run_ts();
app = fig.UserData.app;
logv = [app.log_area.Value{:}];
tc.verifyTrue(contains(logv, 'STATUS: FAILED CLOSED'), ...
    'TS refuses to run with an unvalidated event (no hidden default fault)');
tc.verifyTrue(contains(logv, 'studio:event:NotReady'), ...
    'the failure identifier is surfaced verbatim');
tc.verifyFalse(app.running);
leaked = findall(0, 'Type', 'figure', 'Visible', 'on');
tc.verifyEmpty(leaked, 'refusal path leaves no visible figures');
app.do.close();
end

%% ---- synthetic resource table (build_hybrid_scenario shape) ----
function r = synthetic_resources()
res(1) = mkres('SG1', 'sg', 'synchronous', true, "synchronous");
res(2) = mkres('IBR2', 'ibr', 'gfm', true, ["gfl", "gfm"]);
res(3) = mkres('IBR3', 'ibr', 'gfl', false, ["gfl", "gfm"]);
res(4) = mkres('IBR6', 'ibr', 'gfl', true, ["gfl"]);
r = struct('resources', res);
end

function s = mkres(id, rtype, initial_mode, can_switch, modes)
s = struct('resource_id', id, 'bus_id', 1, 'resource_type', rtype, ...
    'model_id', 'eecon49_dual', 'supported_modes', modes, ...
    'voltage_forming_modes', "gfm", 'initial_mode', initial_mode, ...
    'initial_online', true, 'can_switch_mode', can_switch, ...
    'can_switch_online', true, 'has_current_limiter', true, 'has_frt', true, ...
    'can_black_start', false, 'limits', struct(), 'ratings', struct(), ...
    'dynamic_params', struct(), 'provenance', struct( ...
    'model', 'm', 'source', 's', 'classification', 'CASE_DEFINED', 'details', 'd'));
if strcmp(rtype, 'sg')
    s.supported_modes = "synchronous";
    s.voltage_forming_modes = "synchronous";
    s.has_current_limiter = false;
    s.has_frt = false;
end
end
