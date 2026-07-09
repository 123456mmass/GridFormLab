function fig = smib_plot_step_response(sys, options)
%SMIB_PLOT_STEP_RESPONSE Time-domain response to a small torque disturbance.
%   FIG = SMIB_PLOT_STEP_RESPONSE(SYS, OPTIONS) integrates the linear state
%   equation d/dt x = A x + b*u for a step (or impulse) input and plots the
%   rotor speed deviation delta_omega_r and rotor angle deviation
%   delta_delta versus time. Integration uses the matrix exponential.
%
%   SYS (struct from SMIB_BUILD_STATE_MATRIX): fields A, b, state_names
%   OPTIONS (struct, optional):
%     t_end     - simulation horizon in seconds (default 5)
%     dt        - time step (default 0.005)
%     input     - 'impulse' (default) or 'step' on delta_Tm
%     magnitude - input magnitude (default 0.05 pu)
%     save_path - export PNG if set
%     visible   - 'on' (default) / 'off'
%
%   Reference: Kundur Sec 12.3.1 (time response, eq following 12.82).

if nargin < 2, options = struct(); end
visible   = get_opt(options, 'visible', 'on');
t_end     = get_opt(options, 't_end', 5.0);
dt        = get_opt(options, 'dt', 0.005);
input_t   = get_opt(options, 'input', 'impulse');
mag       = get_opt(options, 'magnitude', 0.05);

A = sys.A;
b = sys.b(:, 1);            % delta_Tm input column
n = size(A, 1);
t = 0:dt:t_end;
nt = numel(t);
x = zeros(n, nt);

switch lower(input_t)
    case 'impulse'
        % Impulse on delta_Tm => initial condition x0 = b*mag
        x0 = b * mag;
        Phi = expm(A * dt);
        x(:, 1) = x0;
        for k = 2:nt
            x(:, k) = Phi * x(:, k-1);
        end
    case 'step'
        % Step on delta_Tm: x(k+1) = Phi x(k) + Gamma*b*mag
        Phi = expm(A * dt);
        if rcond(A) > 1e-12
            Gamma = A \ (Phi - eye(n));
        else
            Gamma = dt * eye(n);    % fallback for singular A
        end
        for k = 2:nt
            x(:, k) = Phi * x(:, k-1) + Gamma * (b * mag);
        end
    otherwise
        error('smib_plot_step_response:badInput', 'input must be impulse or step');
end

dwr = x(1, :);              % delta_omega_r (pu)
ddelta = rad2deg(x(2, :));  % delta_delta (deg)

fig = figure('Name', 'SMIB time response', 'Color', 'w', ...
    'Position', [80 80 980 460], 'Visible', visible);
layout = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax1 = nexttile(layout);
plot(ax1, t, dwr, 'LineWidth', 1.8, 'Color', [0.05 0.36 0.60]);
style_axis(ax1);
xlabel(ax1, 'Time (s)'); ylabel(ax1, '\Delta\omega_r (pu)');
title(ax1, 'Rotor speed deviation', 'FontWeight', 'bold', 'Color', [0 0 0]);
if isprop(ax1, 'Subtitle')
    subtitle(ax1, '\Delta\omega = (1/\omega_s)d\Delta\delta/dt');
end

ax2 = nexttile(layout);
plot(ax2, t, ddelta, 'LineWidth', 1.8, 'Color', [0.83 0.20 0.15]);
style_axis(ax2);
xlabel(ax2, 'Time (s)'); ylabel(ax2, '\Delta\delta (deg)');
title(ax2, 'Rotor angle deviation', 'FontWeight', 'bold', 'Color', [0 0 0]);
if isprop(ax2, 'Subtitle')
    subtitle(ax2, 'peaks occur when \Delta\omega crosses zero');
end

model = '';
if isfield(sys, 'model'); model = sys.model; end
st = sgtitle(layout, sprintf('SMIB %s response to %s \\DeltaT_m = %.3g pu', ...
    model_label(model), input_t, mag), 'FontWeight', 'bold');
st.Color = [0 0 0];

save_if_requested(fig, options);
end

% ------------------------------------------------------------------------
function v = get_opt(o, n, d)
if isstruct(o) && isfield(o, n) && ~isempty(o.(n)); v = o.(n); else; v = d; end
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
