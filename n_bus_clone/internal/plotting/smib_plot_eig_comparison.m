function fig = smib_plot_eig_comparison(sets, options)
%SMIB_PLOT_EIG_COMPARISON Compare swing-mode eigenvalues on the complex plane.
%   FIG = SMIB_PLOT_EIG_COMPARISON(SETS, OPTIONS) plots two (or more) sets of
%   eigenvalues on the same s-plane so the migration of the rotor (swing) mode
%   can be read directly. It is used to contrast the AVR-only configuration
%   (whose high-gain swing mode sits in the right-half plane) with the
%   AVR + PSS configuration (whose swing mode is pulled back into the
%   left-half plane). The left half-plane is shaded as the stable region and
%   the right half-plane as the unstable region; the imaginary axis is the
%   stability boundary.
%
%   SETS : struct array, one element per configuration, with fields
%     eigenvalues - vector of eigenvalues
%     name        - legend label (e.g. 'AVR only')
%     color       - 1x3 RGB (optional; auto-assigned if absent)
%     marker      - marker symbol (optional; default 'o')
%   OPTIONS (struct, optional):
%     highlight   - if true, annotate the dominant swing mode of each set and
%                   draw an arrow from the first set's swing mode to the
%                   last set's swing mode (default true)
%     save_path   - export PNG if set
%     visible     - 'on' (default) / 'off'
%
%   Reference: Kundur Example 12.6 (PSS restores stability).

if nargin < 2, options = struct(); end
visible   = get_opt(options, 'visible', 'on');
highlight = get_opt(options, 'highlight', true);

defcolors = [0.83 0.20 0.15;     % red   - unstable / AVR only
             0.05 0.36 0.60;     % blue  - stable / AVR + PSS
             0.18 0.49 0.20];    % green - spare
nset = numel(sets);

fig = figure('Name', 'SMIB eigenvalue comparison', 'Color', 'w', ...
    'Position', [80 80 760 620], 'Visible', visible);
ax = axes(fig); hold(ax, 'on');

% --- Collect swing modes (the electromechanical ~1 Hz mode of each set) ---
swing = zeros(nset, 1);
for s = 1:nset
    swing(s) = pick_swing(sets(s).eigenvalues(:));
end

% --- View window: focus on the swing region so the sigma=0 crossing is the
%     visible story. Far-off exciter/field modes are intentionally outside. ---
sw_re = real(swing); sw_im = abs(imag(swing));
remax = max(2.5, max(abs(sw_re)) * 2.2);
imc   = max(sw_im);                  % swing imaginary magnitude (~6-7)
immax = imc + max(2.0, 0.35 * imc);  % pad above the conjugate pair
xlim(ax, [-remax, remax]);
ylim(ax, [-immax, immax]);

% --- Shaded stable (LHP) and unstable (RHP) half-planes ---
yl = ylim(ax);
patch(ax, [-remax 0 0 -remax], [yl(1) yl(1) yl(2) yl(2)], ...
    [0.86 0.93 0.86], 'EdgeColor', 'none', 'FaceAlpha', 0.55, ...
    'HandleVisibility', 'off');
patch(ax, [0 remax remax 0], [yl(1) yl(1) yl(2) yl(2)], ...
    [0.97 0.88 0.86], 'EdgeColor', 'none', 'FaceAlpha', 0.55, ...
    'HandleVisibility', 'off');
text(ax, -remax*0.97, immax*0.92, 'STABLE (LHP)', 'Color', [0.18 0.40 0.18], ...
    'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'left');
text(ax, remax*0.97, immax*0.92, 'UNSTABLE (RHP)', 'Color', [0.66 0.16 0.13], ...
    'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'right');

% --- Stability boundary (imaginary axis) ---
xline(ax, 0, '--', 'Color', [0.30 0.30 0.30], 'LineWidth', 1.4, ...
    'Label', 'stability boundary (\sigma = 0)', 'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
yline(ax, 0, '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.6, ...
    'HandleVisibility', 'off');

% --- Plot the in-window eigenvalues of each set (swing pair stays visible) ---
for s = 1:nset
    lam = sets(s).eigenvalues(:);
    col = get_field(sets(s), 'color', defcolors(mod(s-1, size(defcolors,1))+1, :));
    mk  = get_field(sets(s), 'marker', 'o');
    inwin = real(lam) >= -remax & real(lam) <= remax & ...
            imag(lam) >= -immax & imag(lam) <= immax;
    scatter(ax, real(lam(inwin)), imag(lam(inwin)), 110, col, mk, 'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.8, 'DisplayName', sets(s).name);
end

% --- Highlight the swing-mode migration ---
if highlight && nset >= 2
    z1 = swing(1); z2 = swing(end);
    annotation_arrow(ax, z1, z2);
    label_point(ax, z1, sprintf('%+.3f%+.3fj', real(z1), imag(z1)), [0.66 0.16 0.13], 0.7);
    label_point(ax, z2, sprintf('%+.3f%+.3fj', real(z2), imag(z2)), [0.05 0.30 0.52], -0.9);
end

style_axis(ax);
xlabel(ax, 'Real part  \sigma  (1/s)');
ylabel(ax, 'Imaginary part  \omega  (rad/s)');
title(ax, 'Swing-mode eigenvalues: AVR only vs AVR + PSS', 'FontWeight', 'bold', 'Color', [0 0 0]);
st = subtitle(ax, 'view focused on the electromechanical mode; far-off exciter/field modes omitted');
st.Color = [0 0 0];
lgd = legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
lgd.TextColor = [0 0 0];
hold(ax, 'off');

save_if_requested(fig, options);
end

% ------------------------------------------------------------------------
function z = pick_swing(lam)
% Dominant swing mode: largest positive imaginary part (upper conjugate).
up = lam(imag(lam) > 1e-6);
if isempty(up)
    [~, k] = max(real(lam)); z = lam(k); return;
end
% Prefer the ~1 Hz electromechanical mode (imag near 6-8 rad/s): pick the
% one with the smallest |imag| among the lightly damped oscillatory modes.
[~, k] = min(abs(imag(up)));
z = up(k);
end
function annotation_arrow(ax, z1, z2)
plot(ax, [real(z1) real(z2)], [imag(z1) imag(z2)], '-', ...
    'Color', [0.20 0.20 0.20], 'LineWidth', 1.2, 'HandleVisibility', 'off');
% Arrowhead via quiver at the destination
dx = real(z2) - real(z1); dy = imag(z2) - imag(z1);
quiver(ax, real(z1), imag(z1), dx, dy, 0, 'Color', [0.20 0.20 0.20], ...
    'LineWidth', 1.2, 'MaxHeadSize', 0.4, 'HandleVisibility', 'off');
text(ax, (real(z1)+real(z2))/2, (imag(z1)+imag(z2))/2 - 0.7, 'PSS shifts mode', ...
    'Color', [0.20 0.20 0.20], 'FontWeight', 'bold', 'FontSize', 10, ...
    'HorizontalAlignment', 'center');
end
function label_point(ax, z, txt, col, dy)
if nargin < 5, dy = 0.35; end
ha = 'left'; off = 0.12 * abs(real(z)) + 0.15;
if real(z) > 0; ha = 'right'; off = -off; end
text(ax, real(z) + off, imag(z) + dy, txt, 'Color', col, ...
    'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', ha);
end
function v = get_opt(o, n, d)
if isstruct(o) && isfield(o, n) && ~isempty(o.(n)); v = o.(n); else; v = d; end
end
function v = get_field(s, n, d)
if isfield(s, n) && ~isempty(s.(n)); v = s.(n); else; v = d; end
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
