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

data = stability.sssa_load_sweep_plot_data(points,mode_tracking);
eig_data = data.eigenvalues;
pct_data = data.load_percentages;
plot_status.plot_data = data;

% Plot A: eigenvalue plane overlay.
[fig, figfile] = make_fig(vis, output_root, 'plot_A_eigenvalue_overlay');
hold on;
colors = lines(npts);
markers = {'o','s','d','^','v','>','<','p','h'};
for k = 1:npts
    lam = eig_data{k};
    if isempty(lam), continue; end
    m = markers{mod(k-1,numel(markers))+1};
    plot(real(lam), imag(lam), m, 'LineStyle','none', 'Color', colors(k,:), ...
        'MarkerFaceColor', colors(k,:), 'MarkerSize', 6, ...
        'DisplayName', sprintf('+%d%% (alpha=%.2f)', pct_data(k), 1+pct_data(k)/100));
end
xline(0,'--k','Re=0','HandleVisibility','off');
xlabel('Real(\lambda) (1/s)'); ylabel('Imag(\lambda) (1/s)');
title(sprintf('Plot A — Eigenvalue plane overlay [%s]', case_id), ...
    'Interpreter','none');
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
        detail_limit = 1e3; % 1/s, display-only low-frequency window
        detail_found = false;
        for k = 1:npts
            lam = eig_data{k};
            if isempty(lam), continue; end
            lam = lam(abs(lam) <= detail_limit);
            if isempty(lam), continue; end
            detail_found = true;
            m = markers{mod(k-1,numel(markers))+1};
            plot(real(lam), imag(lam), m, 'LineStyle','none', 'Color', colors(k,:), ...
                'MarkerFaceColor', colors(k,:), 'MarkerSize', 6, ...
                'DisplayName', sprintf('+%d%%', pct_data(k)));
        end
        xline(0,'--k','Re=0','HandleVisibility','off');
        xlabel('Real(\lambda) (1/s) — detail'); ylabel('Imag(\lambda) (1/s)');
        title(sprintf('Plot A detail — low-frequency view [%s]', case_id), ...
            'Interpreter','none');
        if detail_found
            legend('Location','bestoutside'); grid on;
            fig_files = save_fig(fig, figfile, save_plots, fig_files);
            plot_status.plot_A_detail = true;
            plot_status.plot_A_detail_limit_per_s = detail_limit;
        else
            close(fig);
            plot_status.plot_A_detail = false;
            plot_status.plot_A_detail_reason = 'NO_ROOTS_INSIDE_LOW_FREQUENCY_WINDOW';
        end
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
    xline(0,'--k','HandleVisibility','off');
    axis([xr yr]);
    title(sprintf('+%d%%', pct_data(k)));
    grid on;
    xlabel('Real'); ylabel('Imag');
end
sgtitle(sprintf('Plot B — Eigenvalue plane by load level [%s]', case_id), ...
    'Interpreter','none');
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
title(sprintf('Plot C — Max real eigenvalue vs load [%s]', case_id), ...
    'Interpreter','none');
grid on;
fig_files = save_fig(fig, figfile, save_plots, fig_files);
plot_status.plot_C = true;

% Plot D: tracked modal trajectories (gated by tracking validity).
if isfield(mode_tracking,'available') && mode_tracking.available
    [fig, figfile] = make_fig(vis, output_root, 'plot_D_tracked_trajectories');
    hold on;
    for s = 1:numel(data.tracked_segments)
        seg = data.tracked_segments{s};
        for m = 1:size(seg.eigenvalues,2)
            lams = seg.eigenvalues(:,m);
            plot(real(lams),imag(lams),'-o','DisplayName', ...
                sprintf('mode %d',m));
        end
    end
    xlabel('Real(\lambda)'); ylabel('Imag(\lambda)');
    title(sprintf('Plot D — Tracked modal trajectories [%s]', case_id), ...
        'Interpreter','none');
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
    oscillatory_found = false;
    subplot(2,1,1);
    hold on;
    for s = 1:numel(data.tracked_segments)
        seg = data.tracked_segments{s};
        for m = 1:size(seg.eigenvalues,2)
            lams = seg.eigenvalues(:,m);
            nz = find(abs(imag(lams)) > 1e-9,1,'first');
            if isempty(nz) || imag(lams(nz)) < 0, continue; end
            oscillatory_found = true;
            plot(seg.load_percentages,abs(imag(lams))/(2*pi),'-o', ...
                'DisplayName',sprintf('mode %d',m));
        end
    end
    ylabel('Frequency (Hz)'); grid on;
    subplot(2,1,2);
    hold on;
    for s = 1:numel(data.tracked_segments)
        seg = data.tracked_segments{s};
        for m = 1:size(seg.eigenvalues,2)
            lams = seg.eigenvalues(:,m);
            nz = find(abs(imag(lams)) > 1e-9,1,'first');
            if isempty(nz) || imag(lams(nz)) < 0, continue; end
            zeta = -real(lams)./abs(lams);
            plot(seg.load_percentages,zeta,'-o', ...
                'DisplayName',sprintf('mode %d',m));
        end
    end
    ylabel('\zeta'); grid on;
    xlabel('Load increase (%)');
    sgtitle(sprintf('Plot E — Frequency and damping vs load [%s]', case_id), ...
        'Interpreter','none');
    if ~oscillatory_found
        subplot(2,1,1); text(0.5,0.5,'No oscillatory eigenvalues', ...
            'Units','normalized','HorizontalAlignment','center');
        subplot(2,1,2); text(0.5,0.5, ...
            'Damping ratio not applicable to real modes', ...
            'Units','normalized','HorizontalAlignment','center');
        plot_status.plot_E_reason = 'NO_OSCILLATORY_EIGENVALUES';
    end
    fig_files = save_fig(fig, figfile, save_plots, fig_files);
    plot_status.plot_E = true;
else
    plot_status.plot_E = false;
    plot_status.plot_E_reason = 'MODE_TRACKING_UNAVAILABLE';
end

% Plot F: min bus voltage + PF/equilibrium diagnostics vs load.
[fig, figfile] = make_fig(vis, output_root, 'plot_F_voltage_diagnostics_vs_load');
subplot(2,1,1);
plot(pct_data, data.voltage_min_pu, '-o', 'LineWidth', 1.5);
xlabel('Load increase (%)'); ylabel('Min bus voltage (pu)');
title(sprintf('Plot F — Min voltage + diagnostics vs load [%s]', case_id), ...
    'Interpreter','none');
grid on;
subplot(2,1,2);
plot(pct_data, data.f_active_inf, '-o', 'LineWidth', 1.5); hold on;
plot(pct_data, data.g_inf, '-s', 'LineWidth', 1.5);
xlabel('Load increase (%)'); ylabel('Residual');
legend('||f_{active}||','||g||','Location','best');
grid on;
fig_files = save_fig(fig, figfile, save_plots, fig_files);
plot_status.plot_F = true;

% Plot G: accepted-equilibrium dq currents and injected P/Q.
if any(isfinite(data.i_d_pu_inverter)) && any(isfinite(data.i_q_pu_inverter)) && ...
        any(isfinite(data.P_MW)) && any(isfinite(data.Q_MVAr))
    [fig, figfile] = make_fig(vis, output_root, 'plot_G_device_dq_power_vs_load');
    subplot(2,1,1);
    plot(pct_data,data.i_d_pu_inverter,'-o','LineWidth',1.5, ...
        'DisplayName','i_d'); hold on;
    plot(pct_data,data.i_q_pu_inverter,'-s','LineWidth',1.5, ...
        'DisplayName','i_q');
    ylabel('Current (pu, inverter base)');
    legend('Location','best'); grid on;
    if ~isempty(data.current_source) && ~isempty(data.current_source{1})
        title(sprintf('Current source: %s',data.current_source{1}), ...
            'Interpreter','none','FontWeight','normal');
    end
    subplot(2,1,2);
    plot(pct_data,data.P_MW,'-o','LineWidth',1.5,'DisplayName','P'); hold on;
    plot(pct_data,data.Q_MVAr,'-s','LineWidth',1.5,'DisplayName','Q');
    xlabel('Load increase (%)'); ylabel('Injection (MW / MVAr)');
    legend('Location','best'); grid on;
    sgtitle(sprintf('Plot G — Device dq current and injected power [%s]',case_id), ...
        'Interpreter','none');
    fig_files = save_fig(fig,figfile,save_plots,fig_files);
    plot_status.plot_G = true;
else
    plot_status.plot_G = false;
    plot_status.plot_G_reason = 'DEVICE_DQ_OR_POWER_DIAGNOSTICS_UNAVAILABLE';
end
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
