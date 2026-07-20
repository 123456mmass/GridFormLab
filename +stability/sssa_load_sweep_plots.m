function [fig_files, plot_status] = sssa_load_sweep_plots(points, mode_tracking, opt)
%SSSA_LOAD_SWEEP_PLOTS  Six plot types, headless.
%   [FIG_FILES, PLOT_STATUS] = stability.sssa_load_sweep_plots(POINTS, ...)
%   generates six plot types from fresh per-point results; no fabrication,
%   smoothing, or rescaling. Saves .fig + .png under
%   output/figures/sssa_load_sweep/<case_id>/.
%
%   Plot A: eigenvalue plane overlay (all load levels).
%   Plot B: eigenvalue plane by load level (symmetric subplots).
%   Plot C: max real eigenvalue vs load increase.
%   Plot D: tracked modal trajectories (gated by tracking validity).
%   Plot E: frequency and damping vs load (gated by tracking validity).
%   Plot F: min bus voltage + PF/equilibrium diagnostics vs load.
%
%   If an extreme eigenvalue compresses Plot A, also provide a labelled
%   low-frequency detail view; the detail view never replaces the complete
%   spectrum. figure_files contains only files actually written.

visible = logical(option_value(opt,'visible',true));
save_plots = logical(option_value(opt,'save_plots',true));
case_id = option_value(opt,'case_id','sweep');
output_root = option_value(opt,'output_root','');
if isempty(output_root)
    output_root = fullfile(pwd,'output','figures','sssa_load_sweep',case_id);
end
if ~exist(output_root,'dir'), mkdir(output_root); end

vis = 'off'; if visible, vis = 'on'; end
fig_files = {};
plot_status = struct();

success_idx = find(cellfun(@(p) strcmp(p.status,'SUCCESS'), points));
npts = numel(success_idx);
if npts == 0
    plot_status.no_successful_points = true;
    return;
end
plot_status.no_successful_points = false;

% Gather eigenvalues per successful point.
eig_data = cell(npts,1);
pct_data = zeros(npts,1);
for k = 1:npts
    p = points{success_idx(k)};
    pct_data(k) = p.load_percentage;
    if isfield(p,'sssa') && isstruct(p.sssa) && isfield(p.sssa,'eigenvalues')
        eig_data{k} = p.sssa.eigenvalues(:);
    else
        eig_data{k} = [];
    end
end

% Plot A: eigenvalue plane overlay.
[fig, figfile] = make_fig(vis, output_root, 'plot_A_eigenvalue_overlay');
hold on;
colors = lines(npts);
markers = {'o','s','d','^','v','>','<','p','h'};
for k = 1:npts
    lam = eig_data{k};
    if isempty(lam), continue; end
    m = markers{mod(k-1,numel(markers))+1};
    plot(real(lam), imag(lam), [m '-'], 'Color', colors(k,:), ...
        'MarkerFaceColor', colors(k,:), 'MarkerSize', 6, ...
        'DisplayName', sprintf('+%d%% (alpha=%.2f)', pct_data(k), 1+pct_data(k)/100));
end
xline(0,'--k','Re=0');
xlabel('Real(\lambda) (1/s)'); ylabel('Imag(\lambda) (1/s)');
title(sprintf('Plot A — Eigenvalue plane overlay [%s]', case_id));
legend('Location','bestoutside'); grid on;
fig_files = save_fig(fig, figfile, save_plots, fig_files);
plot_status.plot_A = true;

% Plot A detail (low-frequency view) if extreme eigenvalue compresses.
all_reals = [];
for k = 1:npts
    if ~isempty(eig_data{k}), all_reals = [all_reals; real(eig_data{k})]; end
end
if ~isempty(all_reals)
    rrange = range(all_reals);
    if rrange > 1e3   % extreme compression threshold
        [fig, figfile] = make_fig(vis, output_root, 'plot_A_detail_low_frequency');
        hold on;
        for k = 1:npts
            lam = eig_data{k};
            if isempty(lam), continue; end
            m = markers{mod(k-1,numel(markers))+1};
            plot(real(lam), imag(lam), [m '-'], 'Color', colors(k,:), ...
                'MarkerFaceColor', colors(k,:), 'MarkerSize', 6, ...
                'DisplayName', sprintf('+%d%%', pct_data(k)));
        end
        xline(0,'--k','Re=0');
        xlabel('Real(\lambda) (1/s) — detail'); ylabel('Imag(\lambda) (1/s)');
        title(sprintf('Plot A detail — low-frequency view [%s]', case_id));
        legend('Location','bestoutside'); grid on;
        fig_files = save_fig(fig, figfile, save_plots, fig_files);
        plot_status.plot_A_detail = true;
    end
end

% Plot B: eigenvalue plane by load level (symmetric subplots).
[fig, figfile] = make_fig(vis, output_root, 'plot_B_eigenvalue_by_load');
ncols = ceil(sqrt(npts)); nrows = ceil(npts/ncols);
% Common axis limits for visual comparability.
all_lams = [];
for k = 1:npts, all_lams = [all_lams; eig_data{k}]; end
if isempty(all_lams)
    xr = [-1 1]; yr = [-1 1];
else
    xr = [min(real(all_lams))-0.1*range(real(all_lams))-1e-6, ...
          max(real(all_lams))+0.1*range(real(all_lams))+1e-6];
    yr = [min(imag(all_lams))-0.1*range(imag(all_lams))-1e-6, ...
          max(imag(all_lams))+0.1*range(imag(all_lams))+1e-6];
end
for k = 1:npts
    subplot(nrows, ncols, k);
    lam = eig_data{k};
    if ~isempty(lam)
        plot(real(lam), imag(lam), 'o', 'MarkerFaceColor', colors(k,:));
    end
    xline(0,'--k');
    axis([xr yr]);
    title(sprintf('+%d%%', pct_data(k)));
    grid on;
    xlabel('Real'); ylabel('Imag');
end
sgtitle(sprintf('Plot B — Eigenvalue plane by load level [%s]', case_id));
fig_files = save_fig(fig, figfile, save_plots, fig_files);
plot_status.plot_B = true;

% Plot C: max real eigenvalue vs load increase.
[fig, figfile] = make_fig(vis, output_root, 'plot_C_max_real_vs_load');
max_reals = zeros(npts,1);
for k = 1:npts
    lam = eig_data{k};
    if isempty(lam), max_reals(k) = NaN; else, max_reals(k) = max(real(lam)); end
end
plot(pct_data, max_reals, '-o', 'LineWidth', 1.5);
yline(0,'--k','stability boundary');
xlabel('Load increase (%)'); ylabel('max Real(\lambda) (1/s)');
title(sprintf('Plot C — Max real eigenvalue vs load [%s]', case_id));
grid on;
fig_files = save_fig(fig, figfile, save_plots, fig_files);
plot_status.plot_C = true;

% Plot D: tracked modal trajectories (gated by tracking validity).
if isfield(mode_tracking,'available') && mode_tracking.available
    [fig, figfile] = make_fig(vis, output_root, 'plot_D_tracked_trajectories');
    hold on;
    for s = 1:numel(mode_tracking.segments)
        seg = mode_tracking.segments{s};
        if ~isfield(seg,'available') || ~seg.available, continue; end
        idx_range = seg.point_indices;
        for m = 1:numel(seg.matches)
            mt = seg.matches{m};
            if ~isfield(mt,'assigned') || ~mt.assigned, continue; end
            % Plot the trajectory of matched eigenvalues across the segment.
            lams = NaN(numel(idx_range),1);
            for kk = 1:numel(idx_range)
                % success_idx maps segment-relative kk -> successful point
                % position in eig_data; idx_range(kk) is the absolute point
                % index. mt.assignment(kk) is the matched column at the
                % "from" point of pair kk.
                si = find(success_idx == idx_range(kk), 1);
                if isempty(si), continue; end
                lam_k = eig_data{si};
                if isempty(lam_k), continue; end
                j = mt.assignment(kk);
                if j ~= 0 && j <= numel(lam_k)
                    lams(kk) = lam_k(j);
                end
            end
            plot(real(lams), imag(lams), '-o', 'DisplayName', ...
                sprintf('mode %d', m));
        end
    end
    xlabel('Real(\lambda)'); ylabel('Imag(\lambda)');
    title(sprintf('Plot D — Tracked modal trajectories [%s]', case_id));
    legend('Location','bestoutside'); grid on;
    fig_files = save_fig(fig, figfile, save_plots, fig_files);
    plot_status.plot_D = true;
else
    plot_status.plot_D = false;
    plot_status.plot_D_reason = 'MODE_TRACKING_UNAVAILABLE';
end

% Plot E: frequency and damping vs load (gated by tracking validity).
if isfield(mode_tracking,'available') && mode_tracking.available
    [fig, figfile] = make_fig(vis, output_root, 'plot_E_freq_damping_vs_load');
    % Collect per-mode frequency and damping across tracked segments.
    % Each segment contains npts-1 matches; match kk links point idx_range(kk)
    % ("from") to idx_range(kk+1) ("to"), and mt.assignment(kk) is the matched
    % eigenvalue column at the "from" point. We plot the "from" eigenvalue
    % per (segment, mode, point) tuple.
    fdata = []; zdata = [];
    for s = 1:numel(mode_tracking.segments)
        seg = mode_tracking.segments{s};
        if ~isfield(seg,'available') || ~seg.available, continue; end
        idx_range = seg.point_indices;
        for m = 1:numel(seg.matches)
            mt = seg.matches{m};
            if ~isfield(mt,'assigned') || ~mt.assigned, continue; end
            for kk = 1:numel(idx_range)
                si = find(success_idx == idx_range(kk), 1);
                if isempty(si), continue; end
                p_kk = points{idx_range(kk)};
                if ~isfield(p_kk,'sssa') || ~isstruct(p_kk.sssa) || ...
                        ~isfield(p_kk.sssa,'eigenvalues'), continue; end
                lam_k = p_kk.sssa.eigenvalues(:);
                j = mt.assignment(kk);
                if j == 0 || j > numel(lam_k), continue; end
                lam = lam_k(j);
                if abs(imag(lam)) > 1e-9
                    fdata(end+1,1:2) = [p_kk.load_percentage, abs(imag(lam))/(2*pi)]; %#ok<AGROW>
                    zdata(end+1,1:2) = [p_kk.load_percentage, ...
                        -real(lam)/sqrt(real(lam)^2+imag(lam)^2)]; %#ok<AGROW>
                end
            end
        end
    end
    subplot(2,1,1);
    if ~isempty(fdata)
        plot(fdata(:,1), fdata(:,2), 'o');
    end
    ylabel('Frequency (Hz)'); grid on;
    subplot(2,1,2);
    if ~isempty(zdata)
        plot(zdata(:,1), zdata(:,2), 'o');
    end
    ylabel('\zeta'); grid on;
    xlabel('Load increase (%)');
    sgtitle(sprintf('Plot E — Frequency and damping vs load [%s]', case_id));
    fig_files = save_fig(fig, figfile, save_plots, fig_files);
    plot_status.plot_E = true;
else
    plot_status.plot_E = false;
    plot_status.plot_E_reason = 'MODE_TRACKING_UNAVAILABLE';
end

% Plot F: min bus voltage + PF/equilibrium diagnostics vs load.
[fig, figfile] = make_fig(vis, output_root, 'plot_F_voltage_diagnostics_vs_load');
vmin = zeros(npts,1);
fres = zeros(npts,1);
gres = zeros(npts,1);
for k = 1:npts
    p = points{success_idx(k)};
    pf = struct();
    if isfield(p,'pf') && isstruct(p.pf), pf = p.pf; end
    if isfield(pf,'voltage_min_pu')
        vmin(k) = pf.voltage_min_pu;
    elseif isfield(pf,'bus_voltage')
        vmin(k) = min(abs(pf.bus_voltage));
    else
        vmin(k) = NaN;
    end
    eq = struct();
    if isfield(p,'equilibrium') && isstruct(p.equilibrium), eq = p.equilibrium; end
    fres(k) = option_value(eq,'residual_norm',NaN);
    gres(k) = option_value(eq,'physical_kcl_norm',NaN);
end
subplot(2,1,1);
plot(pct_data, vmin, '-o', 'LineWidth', 1.5);
xlabel('Load increase (%)'); ylabel('Min bus voltage (pu)');
title(sprintf('Plot F — Min voltage + diagnostics vs load [%s]', case_id));
grid on;
subplot(2,1,2);
plot(pct_data, fres, '-o', 'LineWidth', 1.5); hold on;
plot(pct_data, gres, '-s', 'LineWidth', 1.5);
xlabel('Load increase (%)'); ylabel('Residual');
legend('||f_{active}||','||g||','Location','best');
grid on;
fig_files = save_fig(fig, figfile, save_plots, fig_files);
plot_status.plot_F = true;
end

% =========================================================================
function [fig, figfile] = make_fig(vis, output_root, name)
fig = figure('Visible', vis, 'Position', [100 100 900 600]);
figfile = fullfile(output_root, [name '.png']);
end

function fig_files = save_fig(fig, figfile, save_plots, fig_files)
if save_plots
    figfile_fig = [figfile(1:end-4) '.fig'];
    savefig(fig, figfile_fig);
    exportgraphics(fig, figfile, 'Resolution', 150);
    fig_files{end+1} = figfile; %#ok<AGROW>
    fig_files{end+1} = figfile_fig; %#ok<AGROW>
end
close(fig);
end

function v = option_value(s, name, fallback)
v = fallback;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
