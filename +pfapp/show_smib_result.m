function show_smib_result(app)
%SHOW_SMIB_RESULT Render the SMIB stability result into the GUI.
%   Populates the SMIB Stability tab (s-plane eigenvalues + impulse step
%   response + eigenvalue table) and the dashboard metric cards, then
%   switches the active tab to SMIB.

res = app.last_smib;
model = res.model;
r = res.analyze;
lam = r.eigenvalues;
sigma = real(lam);
omega = imag(lam);
stable = r.is_stable;

% ── Eigenvalue table ────────────────────────────────────────
n = numel(lam);
eig_str = cell(n, 1);
for k = 1:n
    eig_str{k} = sprintf('%8.4f %+8.4fj', sigma(k), omega(k));
end
stab_str = cell(n, 1);
for k = 1:n
    if sigma(k) < 0; stab_str{k} = '✓ stable'; else; stab_str{k} = '✗ unstable'; end
end
data = [eig_str, num2cell(sigma), num2cell(omega), num2cell(r.damping), ...
    num2cell(r.freq_Hz), stab_str];
app.smib_table.Data = data;
pfapp.style_result_table(app, 'smib');

% Point the (power-flow) Results Table tab at a friendly note so it does not
% show a stale bus-result table alongside the SMIB run.
if isfield(app, 'result_table') && isvalid(app.result_table)
    app.result_table.Data = table({'← SMIB eigenvalues are on the SMIB Stability tab.'}, ...
        'VariableNames', {'Note'});
end

% ── Dashboard metrics ──────────────────────────────────────
swing = pick_swing(lam);
if isempty(swing)
    dom_freq = 0; dom_zeta = 0;
else
    dom_freq = abs(imag(swing)) / (2 * pi);
    dom_zeta = -real(swing) / max(abs(swing), eps);
end
if stable
    status_value = 'Stable'; status_color = app.theme.success;
else
    status_value = 'Unstable'; status_color = app.theme.danger;
end
model_label = model_name(model);
nstates = numel(r.state_names);

pfapp.update_dashboard_metrics(app, ...
    {'STABILITY', 'MODEL', 'SWING MODE', 'STATES'}, ...
    {status_value, model_label, sprintf('%.3f Hz', dom_freq), sprintf('%d', nstates)}, ...
    {res.case.system_name, sprintf('Kundur Model %s', model), sprintf('ζ = %.3f', dom_zeta), 'state variables'}, ...
    {status_color, app.theme.primary, app.theme.accent, app.theme.purple});

% ── s-plane eigenvalue plot ─────────────────────────────────
ax = app.ax_smib_plane;
pfapp.reset_axes_state(ax);
hold(ax, 'on');
% axis window focusing on the swing region
allre = [real(lam)]; if isfield(res, 'analyze_avr'); allre = [allre; real(res.analyze_avr.eigenvalues)]; end
re_max = max(2.5, 2.2 * max(abs(allre)));
im_max = max(2.0, 1.35 * max(abs(omega(:))));
if isfield(res, 'analyze_avr')
    im_max = max(im_max, 1.35 * max(abs(imag(res.analyze_avr.eigenvalues))));
end
xlim(ax, [-re_max, re_max]);
ylim(ax, [-im_max, im_max]);
yl = ylim(ax);
% shaded half-planes
patch(ax, [-re_max 0 0 -re_max], [yl(1) yl(1) yl(2) yl(2)], app.theme.success, ...
    'EdgeColor', 'none', 'FaceAlpha', 0.18, 'HandleVisibility', 'off');
patch(ax, [0 re_max re_max 0], [yl(1) yl(1) yl(2) yl(2)], app.theme.danger, ...
    'EdgeColor', 'none', 'FaceAlpha', 0.18, 'HandleVisibility', 'off');
xline(ax, 0, '--', 'Color', app.theme.danger, 'LineWidth', 1.3, ...
    'Label', '\sigma = 0', 'HandleVisibility', 'off');
yline(ax, 0, '-', 'Color', app.theme.muted, 'LineWidth', 0.5, 'HandleVisibility', 'off');
% AVR-only set (model D) in red
if isfield(res, 'analyze_avr')
    lam_avr = res.analyze_avr.eigenvalues;
    inwin = real(lam_avr) >= -re_max & real(lam_avr) <= re_max & abs(imag(lam_avr)) <= im_max;
    scatter(ax, real(lam_avr(inwin)), imag(lam_avr(inwin)), 90, app.theme.danger, 'o', ...
        'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.6, 'DisplayName', 'AVR only');
end
% PSS / primary set in primary colour
inwin2 = abs(omega) <= im_max & sigma >= -re_max & sigma <= re_max;
scatter(ax, sigma(inwin2), omega(inwin2), 100, app.theme.primary, 's', ...
    'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.6, ...
    'DisplayName', ternary(isfield(res,'analyze_avr'), 'AVR + PSS', 'eigenvalues'));
hold(ax, 'off');
xlabel(ax, '\sigma  (1/s)');
ylabel(ax, '\omega  (rad/s)');
title(ax, sprintf('Model %s — eigenvalues on s-plane', model_label), 'Interpreter', 'tex');
if isfield(res, 'analyze_avr')
    legend(ax, 'Location', 'best', 'Box', 'off');
end
grid(ax, 'on');

% ── Step / impulse response ────────────────────────────────
ax2 = app.ax_smib_step;
pfapp.reset_axes_state(ax2);
plot_response(ax2, res, app.theme);
xlabel(ax2, 'Time (s)');
ylabel(ax2, 'deviation');
title(ax2, sprintf('Impulse response (\\DeltaT_m) — Model %s', model_label), 'Interpreter', 'tex');
grid(ax2, 'on');

% ── Switch to SMIB tab ──────────────────────────────────────
try
    if isfield(app, 'smib_tab') && isvalid(app.smib_tab)
        app.tab_group.SelectedTab = app.smib_tab;
    end
catch
end
end

% ── helpers ─────────────────────────────────────────────────
function z = pick_swing(lam)
up = lam(imag(lam) > 1e-3);
if isempty(up)
    z = [];
    return;
end
[~, k] = min(abs(real(up)));
z = up(k);
end

function lbl = model_name(m)
switch upper(m)
    case 'A'; lbl = 'Classical';
    case 'B'; lbl = 'Field Circuit';
    case 'C'; lbl = 'AVR';
    case 'D'; lbl = 'AVR + PSS';
    otherwise; lbl = m;
end
end

function out = ternary(cond, a, b)
if cond; out = a; else; out = b; end
end

function plot_response(ax, res, theme)
% Integrate d/dt x = A x + b*u for an impulse on delta_Tm and plot
% delta_omega_r and delta_delta (first 2 states).
sys = res.sys;
A = sys.A;
b = sys.b(:, 1);
n = size(A, 1);
t_end = 5; dt = 0.005; mag = 0.05;
t = 0:dt:t_end; nt = numel(t);
x = zeros(n, nt);
x0 = b * mag;
Phi = expm(A * dt);
x(:, 1) = x0;
for k = 2:nt
    x(:, k) = Phi * x(:, k-1);
end
dwr = x(1, :);
ddelta = rad2deg(x(2, :));
yyaxis(ax, 'left');
plot(ax, t, dwr, 'LineWidth', 1.8, 'Color', theme.primary);
ylabel(ax, '\Delta\omega_r (pu)');
yyaxis(ax, 'right');
plot(ax, t, ddelta, 'LineWidth', 1.8, 'Color', theme.accent);
ylabel(ax, '\Delta\delta (deg)');
plot_ink = [0.10 0.10 0.10];
ax.XColor = plot_ink;
ax.YColor = plot_ink;
ax.XLabel.Color = plot_ink;
ax.YLabel.Color = plot_ink;
ax.Title.Color = plot_ink;
end
