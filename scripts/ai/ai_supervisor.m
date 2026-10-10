function report = ai_supervisor(scenario_id, varargin)
%AI_SUPERVISOR  Event-triggered AI supervisory control for GFL/GFM switching.
%
%   REPORT = ai_supervisor(SCENARIO_ID, Name, Value, ...)
%
%   Closed supervisory loop over one cached scenario run:
%       detect the emergency -> cut a short transient window -> read the
%       physics -> ask the model which IBR bus(es) should form -> validate the
%       reply -> apply it to the supervisor's own mode table -> continue.
%
%   The grid it supervises is the one this repository studies: IEEE 14-bus,
%   one synchronous machine at bus 1 and dual-mode IBRs at buses 2, 3, 6 and 8.
%   In normal operation the machine is the reference and every IBR follows. The
%   emergency this loop exists for is the loss of that machine, after which the
%   island is 100% inverter-based, has lost most of its inertia, and has no
%   reference at all until something forms one.
%
%   NOTHING HERE RE-SIMULATES AND NOTHING HERE STEERS THE ENGINE. Input is a
%   cache written by scripts/reporting/run_ieee14_scenario_suite.m; output is a
%   report and the supervisor's own committed mode table. The production
%   switching contract inside stability.ts_simulate_ibr_hybrid is untouched --
%   it still triggers on J_V and J_f alone (+stability/agsi_reference_terms.m
%   header). This is a parallel, auditable layer, which is what makes its
%   verdicts comparable to the engine's rather than entangled with them.
%
%   Options (any field of ai.ai_supervisor_defaults):
%       trigger_rule     "spec" (default) or "production"
%       model            e.g. "ocg/deepseek-v4.1-flash"
%       endpoint         OpenAI-compatible chat-completions URL
%       force_fallback   true runs the whole loop with no network at all
%       window_ms        length of the transient window, default 100
%       cache_dir        where the scenario caches live
%       escr_study       true adds the MI-ESCR-vs-damping table (pre-trip,
%                        islanded, 1-2 forming, all four forming). Diagnostics
%                        only, off by default because it builds and solves the
%                        case rather than reading a cache.
%
%   The API key is read from the environment variable named by api_key_env
%   (default LLM_API_KEY). It is never read from a file in this repository.
%
%   See also ai.ai_supervisor_defaults, ai.snapshot_from_cache,
%   ai.ai_detect_event, ai.ai_call_llm.

if nargin < 1 || strlength(string(scenario_id)) == 0
    scenario_id = "sg_fault_cycle160";
end
scenario_id = string(scenario_id);

base = ai.ai_supervisor_defaults();
overrides = parse_overrides(varargin, base);
opts = ai.ai_supervisor_defaults(overrides);

say(opts, sprintf('=== AI supervisor :: %s :: rule=%s ===', ...
    scenario_id, opts.trigger_rule));

% --- [1] read the recorded state -----------------------------------------
[snap, ~, meta] = ai.snapshot_from_cache(scenario_id, opts, opts.cache_dir);
say(opts, sprintf('cache %s | %d samples | IBR buses %s | ESCR %s', ...
    meta.cache_file, snap.n, mat2str(snap.ibr_bus_ids), snap.escr_source));

% --- [2] detect the emergency --------------------------------------------
det = ai.ai_detect_event(snap, opts);
say(opts, sprintf('rule "%s": %d trigger instant(s) over %.3f s', ...
    det.rule, numel(det.trigger_indices), snap.t(end)));

% --- [3..7] one decision per trigger -------------------------------------
mode_table = build_mode_table(snap);
rows = repmat(decision_row(), 0, 1);
for kk = 1:numel(det.trigger_indices)
    k = det.trigger_indices(kk);
    w = window_indices(snap.t, snap.t(k), opts.window_ms);
    % The supervisor's own commitments are passed back in, so a bus it already
    % switched is not offered again at the next trigger.
    feat = ai.ai_extract_features(snap, w, already_committed(mode_table));
    trigger_reason = det.trigger_reasons(kk);
    context = struct('scenario_id', scenario_id, ...
        'trigger_time_s', snap.t(k), 'trigger_reason', trigger_reason);
    [sys_prompt, user_payload] = ai.ai_build_prompt(feat, opts, context);

    resp = ai.ai_call_llm(sys_prompt, user_payload, opts);
    if resp.ok
        [dec, ok, why] = ai.ai_parse_decision(resp.content, feat, opts);
        if ~ok
            dec = ai.ai_fallback_selector(feat, opts, "reply rejected: " + why);
        end
    else
        dec = ai.ai_fallback_selector(feat, opts, ...
            resp.error_id + ": " + resp.error_message);
    end

    t_decision = snap.t(w(end));
    [mode_table, entry] = ai.ai_apply_decision(mode_table, dec, t_decision, opts);

    row = decision_row();
    row.trigger_time_s = snap.t(k);
    row.decision_time_s = t_decision;
    row.trigger_reason = trigger_reason;
    row.source = string(dec.source);
    row.target_buses = dec.target_buses;
    row.confidence = dec.confidence;
    row.applied = entry.applied;
    row.primary_reason = string(dec.primary_reason);
    row.rocof_peak_Hz_s = feat.rocof_peak_Hz_s;
    row.V_min_pu = feat.V_min_pu;
    row.escr_median = [feat.buses.escr_median];
    row.llm_ok = resp.ok;
    row.http_status = resp.http_status;
    row.error_id = resp.error_id;
    row.attempts = resp.attempts;
    row.content = resp.content;
    row.warnings = strjoin([dec.warnings, feat.notes], " | ");
    if isempty(rows), rows = row; else, rows(end+1) = row; end %#ok<AGROW>

    say(opts, sprintf(['  t=%.4f s | %s | buses %s | conf %.2f | %s'], ...
        row.trigger_time_s, row.source, mat2str(row.target_buses), ...
        row.confidence, first_line(row.primary_reason)));
    if ~resp.ok
        say(opts, sprintf('    model unavailable: %s', resp.error_id));
    end
end

report = struct();
report.schema = 'ai_supervisor/1.0';
report.scenario_id = scenario_id;
report.generated_utc = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
report.opts = opts;
report.cache = meta;
report.trigger_rule = det.rule;
report.trigger_times_s = det.trigger_times;
report.decisions = rows;
report.mode_table = mode_table;
report.snapshot_summary = struct( ...
    'n_samples', snap.n, 'ibr_bus_ids', snap.ibr_bus_ids, ...
    'escr_source', snap.escr_source, ...
    'rocof_sources', strjoin(unique(snap.rocof_source), "+"), ...
    'V_min_pu', min(snap.V_min_pu), 'S_max', max_or_nan(snap.S));

% --- [8] optional: short-circuit strength across the switchable conditions -
% ESCR and damping are two separate non-tradeable gates (README.md:84-86); this
% block prints them side by side and never combines them into one score.
report.escr_study = struct([]);
if opts.escr_study
    [~, T] = ai.miescr_condition_study("eecon49_figure4", ...
        struct('form', opts.escr_form, 'zeta_table', opts.escr_zeta_table, ...
        'verbose', false));
    report.escr_study = T;
    print_escr_study(T, opts);
end

if opts.verbose
    print_table(rows, mode_table);
end
end

% =========================================================================
function row = decision_row()
%DECISION_ROW  One row per trigger; every field present so rows() can grow.
row = struct('trigger_time_s', NaN, 'decision_time_s', NaN, ...
    'trigger_reason', "", 'source', "", 'target_buses', [], ...
    'confidence', NaN, 'applied', false, 'primary_reason', "", ...
    'rocof_peak_Hz_s', NaN, 'V_min_pu', NaN, 'escr_median', [], ...
    'llm_ok', false, 'http_status', NaN, 'error_id', "", 'attempts', 0, ...
    'content', "", 'warnings', "");
end

function mt = build_mode_table(snap)
%BUILD_MODE_TABLE  The supervisor's committed modes, starting from the run's.
mt = struct();
mt.ibr_buses = snap.ibr_bus_ids;
% The IBR subset, not the whole device list: modes is aligned with the IBR
% buses, so indexing device_ids against it would print SG1 as the name of
% bus 2.
if isempty(snap.device_ids)
    mt.device_ids = repmat({''}, 1, numel(snap.ibr_bus_ids));
else
    mt.device_ids = snap.device_ids(snap.ibr_device_indices);
end
if isempty(snap.modes_ibr)
    mt.modes = repmat({''}, numel(snap.ibr_bus_ids), 1);
else
    mt.modes = snap.modes_ibr(:, 1);
end
mt.history = struct([]);
end

function b = already_committed(mt)
%ALREADY_COMMITTED  Buses this supervisor has switched to GFM so far.
mask = strcmpi(mt.modes, 'gfm');
b = mt.ibr_buses(mask(:)');
end

function w = window_indices(t, t0, window_ms)
%WINDOW_INDICES  Samples from the trigger to the end of the transient window.
w = find(t >= t0 - 1e-12 & t <= t0 + window_ms/1000 + 1e-12);
if isempty(w)
    w = find(t >= t0 - 1e-12, 1);
end
if isempty(w)
    w = numel(t);
end
end

function overrides = parse_overrides(args, base)
%PARSE_OVERRIDES  Name-value pairs checked against the known option names.
%   An unknown name is refused rather than ignored, so a typo cannot look like
%   a working configuration.
overrides = struct();
if isempty(args)
    return;
end
if mod(numel(args), 2) ~= 0
    error('ai_supervisor:oddNameValue', ...
        'Options must be given as name/value pairs.');
end
known = fieldnames(base);
for k = 1:2:numel(args)
    name = char(string(args{k}));
    if ~any(strcmp(known, name))
        error('ai_supervisor:unknownOption', ...
            'Unknown option "%s". Known options: %s', ...
            name, strjoin(known, ', '));
    end
    overrides.(name) = args{k+1};
end
end

function s = first_line(txt)
s = char(txt);
nl = find(s == newline, 1);
if ~isempty(nl)
    s = s(1:nl-1);
end
if numel(s) > 90
    s = [s(1:87) '...'];
end
end

function v = max_or_nan(x)
if isempty(x) || all(~isfinite(x))
    v = NaN;
else
    v = max(x(isfinite(x)));
end
end

function say(opts, msg)
if opts.verbose
    fprintf('%s\n', msg);
end
end

function print_escr_study(T, opts)
%PRINT_ESCR_STUDY  MI-ESCR next to the certified damping ratio, per condition.
%   The point of printing them together is that they disagree in direction:
%   adding grid-forming converters raises ESCR while lowering the worst damping
%   ratio. They are separate non-tradeable gates (README.md:84-86), so both
%   columns are reported and neither is converted into the other. Every number
%   is a DIAGNOSTIC -- the SCR gate for this model family is forced to
%   'not_applicable_full_state_source_model' and consults neither column.
fprintf('\n--- MI-ESCR vs damping margin :: form=%s ---\n', opts.escr_form);
fprintf('  %-18s %5s %11s %11s %11s %11s\n', ...
    'condition', 'nGFM', 'ESCR(IBR2)', 'ESCR(min)', 'ESCR(max)', 'zeta_worst');
for k = 1:height(T)
    fprintf('  %-18s %5d %11.4f %11.4f %11.4f %11s\n', ...
        T.id(k), T.n_forming(k), T.escr_ibr2(k), T.escr_min(k), ...
        T.escr_max(k), num2str(T.zeta_worst(k), '%.4f'));
end
ok = isfinite(T.zeta_worst);
if any(ok)
    fprintf(['  certified damping over %d condition(s): %.4f .. %.4f; ' ...
        'a condition with no certified set prints NaN.\n'], ...
        sum(ok), min(T.zeta_worst(ok)), max(T.zeta_worst(ok)));
end
fprintf(['  Diagnostic only: the production SCR gate admits this model family ' ...
    'without consulting any short-circuit number.\n']);
end

function print_table(rows, mode_table)
fprintf('\n--- committed modes after the loop ---\n');
for k = 1:numel(mode_table.ibr_buses)
    fprintf('  bus %2d (%s): %s\n', mode_table.ibr_buses(k), ...
        mode_table.device_ids{k}, mode_table.modes{k});
end
if isempty(rows)
    fprintf('\nNo trigger fired; the supervisor committed nothing.\n');
    return;
end
fprintf('\n--- decisions ---\n');
for k = 1:numel(rows)
    fprintf(['  %8.4f s  %-13s buses %-9s conf %.2f  %s\n'], ...
        rows(k).trigger_time_s, rows(k).source, ...
        mat2str(rows(k).target_buses), rows(k).confidence, ...
        first_line(rows(k).primary_reason));
end
end
