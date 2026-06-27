function fig = smib_plot_mode_shape(result, options)
%SMIB_PLOT_MODE_SHAPE Compass plot of a mode's right-eigenvector entries.
%   FIG = SMIB_PLOT_MODE_SHAPE(RESULT, OPTIONS) draws the right-eigenvector
%   (mode shape) of one oscillatory mode as phasors on a compass plot, and
%   the per-state participation factors as a companion bar chart. The mode
%   shape shows the relative magnitude and phase with which each state
%   participates in the selected mode.
%
%   RESULT (struct from SMIB_ANALYZE): fields eigenvalues, right_vectors,
%     participation, state_names
%   OPTIONS (struct, optional):
%     mode_index - index of the eigenvalue/eigenvector to display. If unset,
%                  the lightly damped oscillatory (swing) mode is chosen.
%     save_path  - export PNG if set
%     visible    - 'on' (default) / 'off'
%
%   Reference: Kundur Sec 12.1.6 (mode shape) and 12.1.7 (participation).

if nargin < 2, options = struct(); end
visible = get_opt(options, 'visible', 'on');

lambda = result.eigenvalues;
V = result.right_vectors;
names = result.state_names;

mode_index = get_opt(options, 'mode_index', pick_swing_mode(lambda));

phi = V(:, mode_index);
% Normalize so the largest-magnitude entry has unit length and zero phase
[~, ref] = max(abs(phi));
phi = phi / phi(ref);

lam = lambda(mode_index);
zeta = -real(lam) / max(abs(lam), eps);

fig = figure('Name', 'SMIB mode shape', 'Color', 'w', ...
    'Position', [80 80 1000 460], 'Visible', visible);
layout = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

% --- Compass (phasor) plot of the mode shape ---
ax1 = nexttile(layout);
cmap = lines(numel(phi));
hold(ax1, 'on');
maxr = max(abs(phi));
for k = 1:numel(phi)
    cm = compass(ax1, real(phi(k)), imag(phi(k)));
    set(cm, 'Color', cmap(k, :), 'LineWidth', 2.0);
end
hold(ax1, 'off');
style_axis(ax1);
title(ax1, 'Mode shape (right eigenvector)', 'FontWeight', 'bold', 'Color', [0 0 0]);
lgd = legend(ax1, names, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
    'Interpreter', 'tex', 'Box', 'off');
lgd.TextColor = [0 0 0];

% --- Participation factors bar chart ---
ax2 = nexttile(layout);
p = result.participation(:, mode_index);
b = bar(ax2, p, 'FaceColor', 'flat');
for k = 1:numel(p); b.CData(k, :) = cmap(k, :); end
style_axis(ax2);
ax2.XTick = 1:numel(p);
ax2.XTickLabel = names;
ax2.TickLabelInterpreter = 'tex';
ylabel(ax2, 'Participation factor');
title(ax2, 'Participation factors', 'FontWeight', 'bold', 'Color', [0 0 0]);
ylim(ax2, [0, 1.05 * max(p)]);

model = getfield_default(result, 'model', '');
st = sgtitle(layout, sprintf('%s mode \\lambda = %.3f %+.3fj  (\\zeta = %.3f, f = %.3f Hz)', ...
    model_label(model), real(lam), imag(lam), zeta, abs(imag(lam))/(2*pi)), ...
    'FontWeight', 'bold');
st.Color = [0 0 0];

save_if_requested(fig, options);
end

% ------------------------------------------------------------------------
function idx = pick_swing_mode(lambda)
% Choose the oscillatory mode with the smallest |real| that has a positive
% imaginary part (the lightly-damped swing mode near ~1 Hz).
osc = find(imag(lambda) > 1e-3);
if isempty(osc)
    idx = 1;
    return;
end
[~, j] = min(abs(real(lambda(osc))));
idx = osc(j);
end
function v = get_opt(o, n, d)
if isstruct(o) && isfield(o, n) && ~isempty(o.(n)); v = o.(n); else; v = d; end
end
function v = getfield_default(s, n, d)
if isfield(s, n) && ~isempty(s.(n)); v = s.(n); else; v = d; end
end
function s = model_label(m)
switch upper(m)
    case 'A'; s = 'classical';
    case 'B'; s = 'field-circuit';
    case 'C'; s = 'AVR';
    case 'D'; s = 'AVR+PSS';
    otherwise; s = m;
end
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
