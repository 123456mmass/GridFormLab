function fig = smib_plot_root_locus(sweep, options)
%SMIB_PLOT_ROOT_LOCUS Eigenvalue trajectory as a parameter is swept.
%   FIG = SMIB_PLOT_ROOT_LOCUS(SWEEP, OPTIONS) plots the migration of the
%   SMIB eigenvalues on the complex s-plane as a scalar parameter is varied.
%
%   SWEEP (struct):
%     values      - vector of swept parameter values
%     eigenvalues - cell array (one entry per value) of eigenvalue vectors
%     param_name  - name of the swept parameter (for labels), e.g. 'K_D'
%     title       - figure title
%   OPTIONS (struct, optional):
%     save_path   - if set, export the figure to this PNG path
%     visible     - 'on' (default) or 'off' for headless rendering
%     shade       - shade the stable (LHP) / unstable (RHP) regions
%                   (default true)
%     mark_points - struct array of points to annotate on the locus, each
%                   with fields .value (swept-parameter value) and optional
%                   .label; the upper-half swing eigenvalue at that value is
%                   circled and labelled (e.g. K_D = -10, 0, 10)
%
%   The swing (rotor) mode and other modes are colour-coded; the stability
%   boundary (imaginary axis) is highlighted, and the half-planes are shaded
%   to read stability at a glance.

if nargin < 2, options = struct(); end
visible = get_opt(options, 'visible', 'on');
shade   = get_opt(options, 'shade', true);

values = sweep.values(:);
nval = numel(values);
colors = smib_palette();

fig = figure('Name', get_field(sweep, 'title', 'SMIB root locus'), ...
    'Color', 'w', 'Position', [80 80 760 620], 'Visible', visible);
ax = axes(fig); hold(ax, 'on');

% Colour map across the sweep
cmap = parula(max(nval, 2));

for i = 1:nval
    lam = sweep.eigenvalues{i};
    scatter(ax, real(lam), imag(lam), 42, cmap(i, :), 'filled', ...
        'MarkerEdgeColor', 'w', 'LineWidth', 0.5, 'HandleVisibility', 'off');
end

% Connect trajectories for the upper-half oscillatory mode
osc_re = nan(nval, 1); osc_im = nan(nval, 1);
for i = 1:nval
    lam = sweep.eigenvalues{i};
    up = lam(imag(lam) > 1e-6);
    if ~isempty(up)
        [~, k] = max(imag(up));
        osc_re(i) = real(up(k));
        osc_im(i) = imag(up(k));
    end
end
plot(ax, osc_re, osc_im, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.0, ...
    'HandleVisibility', 'off');

% Fix axis extents now so shading and labels have a stable frame
axis(ax, 'tight');
xl = xlim(ax); yl = ylim(ax);
padx = 0.08 * (xl(2) - xl(1) + eps); pady = 0.08 * (yl(2) - yl(1) + eps);
xl = [xl(1) - padx, xl(2) + padx];
yl = [yl(1) - pady, yl(2) + pady];
% Ensure the imaginary axis (stability boundary) is always in view
xl(1) = min(xl(1), -0.05 * (xl(2) - xl(1)));
xl(2) = max(xl(2),  0.05 * (xl(2) - xl(1)));
xlim(ax, xl); ylim(ax, yl);

% Shade the stable (left) and unstable (right) half-planes
if shade
    ph1 = patch(ax, [xl(1) 0 0 xl(1)], [yl(1) yl(1) yl(2) yl(2)], ...
        [0.86 0.93 0.86], 'EdgeColor', 'none', 'FaceAlpha', 0.45, ...
        'HandleVisibility', 'off');
    ph2 = patch(ax, [0 xl(2) xl(2) 0], [yl(1) yl(1) yl(2) yl(2)], ...
        [0.97 0.88 0.86], 'EdgeColor', 'none', 'FaceAlpha', 0.45, ...
        'HandleVisibility', 'off');
    uistack([ph1 ph2], 'bottom');
    text(ax, xl(1) + 0.04*(xl(2)-xl(1)), yl(1) + 0.07*(yl(2)-yl(1)), ...
        'stable region', 'Color', [0.18 0.40 0.18], 'FontWeight', 'bold', ...
        'FontSize', 10, 'HorizontalAlignment', 'left', ...
        'BackgroundColor', [1 1 1], 'Margin', 1);
    text(ax, xl(2) - 0.04*(xl(2)-xl(1)), yl(1) + 0.07*(yl(2)-yl(1)), ...
        'unstable region', 'Color', [0.66 0.16 0.13], 'FontWeight', 'bold', ...
        'FontSize', 10, 'HorizontalAlignment', 'right', ...
        'BackgroundColor', [1 1 1], 'Margin', 1);
end

% Stability boundary (imaginary axis)
xline(ax, 0, '--', 'Color', [0.72 0.18 0.14], 'LineWidth', 1.4, ...
    'Label', 'stability boundary', 'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'middle', 'LabelHorizontalAlignment', 'center');

% Annotate requested swept-parameter points on the upper-half swing branch
mark_points = get_opt(options, 'mark_points', []);
for m = 1:numel(mark_points)
    mp = mark_points(m);
    [~, idx] = min(abs(values - mp.value));
    lam = sweep.eigenvalues{idx};
    up = lam(imag(lam) > 1e-6);
    if isempty(up); continue; end
    [~, k] = max(imag(up)); z = up(k);
    plot(ax, real(z), imag(z), 'o', 'MarkerSize', 11, 'LineWidth', 1.6, ...
        'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'none', 'HandleVisibility', 'off');
    if isfield(mp, 'label') && ~isempty(mp.label); lbl = mp.label; ...
    else; lbl = sprintf('%s=%g', get_field(sweep, 'param_name', 'p'), mp.value); end
    % Place the label below the marker (markers cluster near the top of the
    % frame); nudge horizontally so it stays clear of the trajectory line.
    dyl = -0.10*(yl(2)-yl(1));
    text(ax, real(z), imag(z) + dyl, lbl, 'FontSize', 9, ...
        'FontWeight', 'bold', 'Color', [0.1 0.1 0.1], ...
        'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1], 'Margin', 1);
end

% Colour bar mapping to swept parameter
cb = colorbar(ax);
cb.Label.String = get_field(sweep, 'param_name', 'parameter');
clim(ax, [values(1) values(end)]);

style_axis(ax);
xlabel(ax, 'Real part  \sigma  (1/s)');
ylabel(ax, 'Imaginary part  \omega  (rad/s)');
title(ax, get_field(sweep, 'title', 'Eigenvalue trajectory'), 'FontWeight', 'bold', 'Color', [0 0 0]);
st = subtitle(ax, sprintf('%s swept from %.3g to %.3g', ...
    get_field(sweep, 'param_name', 'param'), values(1), values(end)));
st.Color = [0 0 0];
hold(ax, 'off');

save_if_requested(fig, options);
end

% ------------------------------------------------------------------------
function v = get_opt(o, n, d)
if isstruct(o) && isfield(o, n) && ~isempty(o.(n)); v = o.(n); else; v = d; end
end
function v = get_field(s, n, d)
if isfield(s, n) && ~isempty(s.(n)); v = s.(n); else; v = d; end
end
function colors = smib_palette()
colors = struct('swing', [0.83 0.20 0.15], 'other', [0.05 0.36 0.60], ...
    'grid', [0.88 0.90 0.92]);
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
