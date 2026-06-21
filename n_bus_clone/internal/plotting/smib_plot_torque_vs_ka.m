function fig = smib_plot_torque_vs_ka(K, exciter, H, w0, options)
%SMIB_PLOT_TORQUE_VS_KA Synchronizing/damping torque vs exciter gain K_A.
%   FIG = SMIB_PLOT_TORQUE_VS_KA(K, EXCITER, H, W0, OPTIONS) sweeps the AVR
%   gain K_A and plots how the field-flux/AVR loop contributes to the
%   synchronizing torque coefficient K_S and the damping torque coefficient
%   K_D of the rotor (swing) mode. This reproduces the trend of Kundur
%   Table 12.1: with K5 < 0, increasing K_A raises K_S but drives K_D
%   negative, eventually destabilizing the swing mode.
%
%   K        - K-constant struct (K1..K6, T3); see SMIB_K_CONSTANTS / case
%   EXCITER  - struct with field TR (transducer time constant); KA is swept
%   H, W0    - inertia constant and base speed (rad/s)
%   OPTIONS (struct, optional):
%     ka_values  - vector of K_A values to sweep (default logspace-like set)
%     omega_eval - rotor frequency (rad/s) to evaluate torque (default from
%                  the undamped swing frequency sqrt(K1*w0/(2H)))
%     save_path  - export PNG if set
%     visible    - 'on' (default) / 'off'
%
%   Reference: Kundur Sec 12.4, Table 12.1, eqs 12.142-12.147.

if nargin < 5, options = struct(); end
visible = get_opt(options, 'visible', 'on');

ka_values = get_opt(options, 'ka_values', [0 1 5 10 15 25 50 100 200 400]);
omega0 = sqrt(max(K.K1, eps) * w0 / (2 * H));   % undamped swing frequency
omega_eval = get_opt(options, 'omega_eval', omega0);

ka_values = ka_values(:);
nka = numel(ka_values);
Ks = zeros(nka, 1); KD = zeros(nka, 1); Ks_tot = zeros(nka, 1);
for i = 1:nka
    ex = exciter; ex.KA = ka_values(i);
    td = smib.smib_torque_components(K, ex, H, w0, omega_eval);
    Ks(i) = td.Ks_dpsifd;
    KD(i) = td.KD_dpsifd;
    Ks_tot(i) = td.Ks_total;
end

fig = figure('Name', 'SMIB torque vs K_A', 'Color', 'w', ...
    'Position', [80 80 1000 460], 'Visible', visible);
layout = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

% --- Damping coefficient KD(delta_psi_fd) vs KA ---
ax1 = nexttile(layout);
plot(ax1, ka_values, KD, '-o', 'LineWidth', 1.8, 'Color', [0.83 0.20 0.15], ...
    'MarkerFaceColor', [0.83 0.20 0.15], 'MarkerSize', 5);
yline(ax1, 0, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
    'Label', 'K_D = 0 (stability boundary)', 'LabelHorizontalAlignment', 'left');
style_axis(ax1);
xlabel(ax1, 'Exciter gain  K_A');
ylabel(ax1, 'K_D  (damping torque coefficient)');
title(ax1, 'Damping vs AVR gain', 'FontWeight', 'bold', 'Color', [0 0 0]);

% --- Synchronizing coefficient vs KA ---
ax2 = nexttile(layout);
hold(ax2, 'on');
plot(ax2, ka_values, Ks_tot, '-s', 'LineWidth', 1.8, 'Color', [0.05 0.36 0.60], ...
    'MarkerFaceColor', [0.05 0.36 0.60], 'MarkerSize', 5, ...
    'DisplayName', 'K_S total (K_1 + \DeltaK_S)');
plot(ax2, ka_values, Ks, '-^', 'LineWidth', 1.4, 'Color', [0.30 0.62 0.32], ...
    'MarkerFaceColor', [0.30 0.62 0.32], 'MarkerSize', 5, ...
    'DisplayName', '\DeltaK_S (\Delta\psi_{fd} component)');
hold(ax2, 'off');
style_axis(ax2);
xlabel(ax2, 'Exciter gain  K_A');
ylabel(ax2, 'K_S  (synchronizing torque coefficient)');
title(ax2, 'Synchronizing torque vs AVR gain', 'FontWeight', 'bold', 'Color', [0 0 0]);
lgd = legend(ax2, 'Location', 'best', 'Box', 'off');
lgd.TextColor = [0 0 0];

st = sgtitle(layout, sprintf(['Torque components vs exciter gain  ' ...
    '(evaluated at \\omega = %.3g rad/s, K_5 = %.3g)'], ...
    omega_eval, K.K5), 'FontWeight', 'bold');
st.Color = [0 0 0];

save_if_requested(fig, options);
end

% ------------------------------------------------------------------------
function v = get_opt(o, n, d)
if isstruct(o) && isfield(o, n) && ~isempty(o.(n)); v = o.(n); else; v = d; end
end
function style_axis(ax)
ax.FontName = 'Segoe UI';
ax.FontSize = 10;
ax.Color = [1 1 1];
ax.XColor = [0 0 0];
ax.YColor = [0 0 0];
ax.GridColor = [0.82 0.82 0.82];
ax.MinorGridColor = [0.88 0.88 0.88];
grid(ax, 'on'); ax.GridAlpha = 0.6; ax.MinorGridAlpha = 0.4;
ax.Layer = 'top';
ax.Title.FontName = 'Segoe UI';
ax.Title.Color = [0 0 0];
ax.Title.FontWeight = 'bold';
ax.XLabel.Color = [0 0 0];
ax.YLabel.Color = [0 0 0];
if isprop(ax, 'Subtitle'); ax.Subtitle.Color = [0 0 0]; end
end
function save_if_requested(fig, options)
if isfield(options, 'save_path') && ~isempty(options.save_path)
    exportgraphics(fig, options.save_path, 'Resolution', 150);
end
end
