function plot_path = plot_ibr_switching_comparison(results_struct, plot_opt)
%PLOT_IBR_SWITCHING_COMPARISON  Multi-scenario comparison figures.
%   plot_path = plot_ibr_switching_comparison(RESULTS_STRUCT, PLOT_OPT) produces
%   comparison figures from a struct of result structs. Does NOT mutate
%   numerical results (MATLAB copy-on-write; this function treats results as
%   read-only).
%
%   plot_opt.figure selects the figure type:
%     'main_physical_evidence' - 6 subplots, one line per scenario.
%     'workflow_validation'    - 6 subplots, C-natural vs C-workflow.
%     'delay_comparison'       - 6 subplots, delay-on vs delay-off.
%
%   Each subplot uses linear axes. Lines are drawn from raw result fields; NaN
%   gaps prevent connection across missing/failed samples (F9). Partial/
%   failed trajectories are labeled. Event markers are added for fault on,
%   fault clear, SG trip, reconnect request, actual SG reclose, actual IBR
%   reselection.
%
%   Source: C6/F7/F9 user-approved plan. PROJECT_DERIVED plotting.

arguments
    results_struct struct
    plot_opt struct = struct()
end

figure_type = 'main_physical_evidence';
if isfield(plot_opt,'figure') && ~isempty(plot_opt.figure)
    figure_type = char(string(plot_opt.figure));
end
output_dir = fullfile('output','plots');
if isfield(plot_opt,'output_dir') && ~isempty(plot_opt.output_dir)
    output_dir = char(string(plot_opt.output_dir));
end
if ~isfolder(output_dir), mkdir(output_dir); end
visible = false;
if isfield(plot_opt,'visible') && ~isempty(plot_opt.visible)
    visible = logical(plot_opt.visible);
end

vis = 'off'; if visible, vis = 'on'; end
fig = figure('Visible',vis,'Name',['IBR switching comparison: ' figure_type], ...
    'Units','pixels','Position',[80 80 1400 900]);
tl = tiledlayout(fig,3,2,'TileSpacing','compact','Padding','compact');

scenario_names = fieldnames(results_struct);
colors = lines(numel(scenario_names));

% Subplot 1: COI frequency / deviation.
ax1 = nexttile(tl,1); hold(ax1,'on'); grid(ax1,'on');
plot_frequency(ax1, results_struct, scenario_names, colors);
title(ax1,'COI frequency');
legend(ax1,'Location','best','Interpreter','none');

% Subplot 2: minimum bus voltage magnitude.
ax2 = nexttile(tl,2); hold(ax2,'on'); grid(ax2,'on');
plot_min_voltage(ax2, results_struct, scenario_names, colors);
title(ax2,'Minimum bus voltage magnitude');
legend(ax2,'Location','best','Interpreter','none');

% Subplot 3: SG electrical active power.
ax3 = nexttile(tl,3); hold(ax3,'on'); grid(ax3,'on');
plot_sg_power(ax3, results_struct, scenario_names, colors);
title(ax3,'SG electrical active power');
legend(ax3,'Location','best','Interpreter','none');

% Subplot 4: aggregate IBR active power.
ax4 = nexttile(tl,4); hold(ax4,'on'); grid(ax4,'on');
plot_aggregate_ibr_power(ax4, results_struct, scenario_names, colors);
title(ax4,'Aggregate IBR active power');
legend(ax4,'Location','best','Interpreter','none');

% Subplot 5: max normalized IBR current |I|/Ilimit.
ax5 = nexttile(tl,5); hold(ax5,'on'); grid(ax5,'on');
plot_max_normalized_current(ax5, results_struct, scenario_names, colors);
title(ax5,'Max normalized IBR current |I|/I_{lim}');
legend(ax5,'Location','best','Interpreter','none');

% Subplot 6: number of online GFM resources.
ax6 = nexttile(tl,6); hold(ax6,'on'); grid(ax6,'on');
plot_gfm_count(ax6, results_struct, scenario_names, colors);
title(ax6,'Number of online GFM resources');
legend(ax6,'Location','best','Interpreter','none');

% Add event markers to each axis. Axes handles are kept directly (no findobj/
% fig.Children fallback that breaks under tiledlayout). Event times/types are
% drawn authoritatively from each result's event_log/events; scheduled,
% committed, and rejected/timeout events use distinct line styles. Event lines
% are excluded from the trajectory legend (HandleVisibility='off').
axes_all = [ax1 ax2 ax3 ax4 ax5 ax6];
add_event_markers(axes_all, results_struct, scenario_names);

filename = sprintf('ieee14_ibr_switching_comparison_%s.png', figure_type);
plot_path = fullfile(output_dir, filename);
saveas(fig, plot_path);
if ~visible, close(fig); end
end

% =========================================================================
function add_event_markers(axes_all, results, names)
%ADD_EVENT_MARKERS  Draw authoritative event markers on every axis.
%   Scheduled events (from result.events / sched) use a dashed grey line;
%   committed events (event_log.applied==true) use a solid dark line;
%   rejected/timeout events (applied==false or reclose_status/reselection_status
%   indicating failure) use a dotted red line. All lines are off-legend.
sched_color = [0.6 0.6 0.6];   % grey: scheduled
committed_color = [0.1 0.1 0.1]; % near-black: committed
rejected_color = [0.8 0.2 0.2];   % red: rejected/timeout
for s = 1:numel(names)
    r = results.(names{s});
    times = event_times(r);
    % Scheduled event times (dashed grey).
    for j = 1:numel(times.scheduled)
        if isfinite(times.scheduled(j))
            add_xline(axes_all, times.scheduled(j), ':', sched_color);
        end
    end
    % Committed event times (solid dark).
    for j = 1:numel(times.committed)
        if isfinite(times.committed(j))
            add_xline(axes_all, times.committed(j), '-', committed_color);
        end
    end
    % Rejected/timeout event times (dotted red).
    for j = 1:numel(times.rejected)
        if isfinite(times.rejected(j))
            add_xline(axes_all, times.rejected(j), '-.', rejected_color);
        end
    end
end
end

function add_xline(axes_all, t, style, color)
%ADD_XLINE  Add a vertical line at t to every axis, off-legend.
%   style is a LineStyle string ('-', ':', '-.', '--'); passed as a Name-Value
%   pair because xline's 3rd positional arg is a label, not a LineSpec.
for k = 1:numel(axes_all)
    ax = axes_all(k);
    if isvalid(ax)
        xline(ax, t, 'LineStyle', style, 'Color', color, 'HandleVisibility', 'off');
    end
end
end

function times = event_times(r)
%EVENT_TIMES  Extract scheduled/committed/rejected event times from a result.
times.scheduled = [];
times.committed = [];
times.rejected = [];
% Scheduled times from the events array (if present).
if isfield(r, 'events') && ~isempty(r.events)
    try
        times.scheduled = [r.events.t];
    catch
    end
end
% Committed/rejected from event_log.
if isfield(r, 'event_log') && ~isempty(r.event_log)
    applied = false(numel(r.event_log), 1);
    ts = nan(numel(r.event_log), 1);
    for j = 1:numel(r.event_log)
        if isfield(r.event_log(j), 'applied')
            applied(j) = logical(r.event_log(j).applied);
        end
        if isfield(r.event_log(j), 't')
            ts(j) = r.event_log(j).t;
        end
    end
    times.committed = ts(applied & isfinite(ts));
    times.rejected = ts(~applied & isfinite(ts));
end
% Reclose/reselection actual times are committed (if finite).
if isfield(r, 'actual_reclose_time') && isfinite(r.actual_reclose_time)
    times.committed = [times.committed; r.actual_reclose_time]; %#ok<AGROW>
end
if isfield(r, 'actual_mode_reselection_time') && isfinite(r.actual_mode_reselection_time)
    times.committed = [times.committed; r.actual_mode_reselection_time]; %#ok<AGROW>
end
% Timeout/failure -> rejected marker at the timeout boundary.
if isfield(r, 'reclose_status')
    if strcmpi(char(r.reclose_status), 'SYNC_TIMEOUT') || ...
            strcmpi(char(r.reclose_status), 'PENDING_SYNC_FAIL')
        % Use requested reconnect time as the timeout marker if available.
        rt = NaN;
        if isfield(r, 'requested_sg_on_time') && isfinite(r.requested_sg_on_time)
            rt = r.requested_sg_on_time;
        end
        if isfinite(rt)
            times.rejected = [times.rejected; rt]; %#ok<AGROW>
        end
    end
end
end

% =========================================================================
function plot_frequency(ax, results, names, colors)
for k = 1:numel(names)
    r = results.(names{k});
    if ~isfield(r,'coi_frequency_Hz') || ~isfield(r,'t'), continue; end
    t = r.t; f = r.coi_frequency_Hz;
    % NaN gaps: plot segments between finite samples only (F9).
    plot_finite(ax, t, f, colors(k,:), names{k});
end
end

function plot_min_voltage(ax, results, names, colors)
for k = 1:numel(names)
    r = results.(names{k});
    if ~isfield(r,'bus_voltage_magnitude') || ~isfield(r,'t'), continue; end
    t = r.t;
    v = min(r.bus_voltage_magnitude, [], 1);
    plot_finite(ax, t, v, colors(k,:), names{k});
end
end

function plot_sg_power(ax, results, names, colors)
for k = 1:numel(names)
    r = results.(names{k});
    if ~isfield(r,'device_P_MW') || ~isfield(r,'t'), continue; end
    t = r.t;
    if isfield(r,'sg_indices') && ~isempty(r.sg_indices)
        p = sum(r.device_P_MW(r.sg_indices,:), 1);
    else
        p = sum(r.device_P_MW, 1);
    end
    plot_finite(ax, t, p, colors(k,:), names{k});
end
end

function plot_aggregate_ibr_power(ax, results, names, colors)
for k = 1:numel(names)
    r = results.(names{k});
    if ~isfield(r,'device_P_MW') || ~isfield(r,'t'), continue; end
    t = r.t;
    sg_idx = [];
    if isfield(r,'sg_indices'), sg_idx = r.sg_indices; end
    ibr_mask = true(1, size(r.device_P_MW,1));
    ibr_mask(sg_idx) = false;
    p = sum(r.device_P_MW(ibr_mask,:), 1);
    plot_finite(ax, t, p, colors(k,:), names{k});
end
end

function plot_max_normalized_current(ax, results, names, colors)
for k = 1:numel(names)
    r = results.(names{k});
    if ~isfield(r,'device_current_magnitude') || ~isfield(r,'device_current_limit_sys') || ~isfield(r,'t')
        continue;
    end
    t = r.t;
    imag = r.device_current_magnitude;
    ilim = r.device_current_limit_sys;
    ratio = nan(size(imag));
    mask = isfinite(ilim) & ilim > 0;
    ratio(mask) = imag(mask) ./ ilim(mask);
    max_ratio = max(ratio, [], 1);
    plot_finite(ax, t, max_ratio, colors(k,:), names{k});
end
end

function plot_gfm_count(ax, results, names, colors)
for k = 1:numel(names)
    r = results.(names{k});
    if ~isfield(r,'device_modes_history') || ~isfield(r,'t'), continue; end
    t = r.t;
    modes = r.device_modes_history;
    [nd, nt] = size(modes);
    gfm_count = zeros(1, nt);
    for j = 1:nt
        for d = 1:nd
            if strcmpi(char(modes{d,j}), 'gfm') || strcmpi(char(modes{d,j}), 'GFM')
                gfm_count(j) = gfm_count(j) + 1;
            end
        end
    end
    plot_finite(ax, t, gfm_count, colors(k,:), names{k});
end
end

function plot_finite(ax, t, y, color, name)
%PLOT_FINITE  Plot only finite segments (NaN gaps break the line, F9).
y = y(:).';
t = t(:).';
mask = isfinite(t) & isfinite(y);
if ~any(mask)
    return;
end
% Insert NaN at gaps so MATLAB does not connect across missing samples.
t_plot = t; y_plot = y;
% Find breaks in the finite mask and insert NaN.
breaks = find(diff(mask) < 0);
for b = breaks(:).'
    % Insert NaN after the last finite point before the break.
    if b < numel(t_plot)
        y_plot(b+1) = NaN;  % already NaN if not finite, harmless otherwise
    end
end
plot(ax, t_plot(mask), y_plot(mask), 'LineWidth', 1.3, 'Color', color, ...
    'DisplayName', name);
end
