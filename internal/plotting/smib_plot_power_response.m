function fig = smib_plot_power_response(sys, options)
%SMIB_PLOT_POWER_RESPONSE Electrical power deviation after a small disturbance.
%   FIG = SMIB_PLOT_POWER_RESPONSE(SYS, OPTIONS) integrates the linear state
%   equation d/dt x = A x + b*u for a small torque disturbance and plots the
%   electrical power deviation delta_Pe versus time. For the classical model
%   the incremental air-gap power is, to first order,
%
%       delta_Pe ~= K_S * delta_delta            (synchronizing torque law)
%
%   so the electrical power oscillation tracks the rotor-angle swing. A
%   decaying delta_Pe confirms that the machine settles back to steady power
%   transfer with the infinite bus; a growing delta_Pe signals instability.
%
%   SYS (struct from SMIB_BUILD_STATE_MATRIX): fields A, b, state_names, Ks
%   OPTIONS (struct, optional):
%     t_end     - simulation horizon in seconds (default 5)
%     dt        - time step (default 0.005)
%     input     - 'impulse' (default) or 'step' on delta_Tm
%     magnitude - input magnitude (default 0.05 pu)
%     Ks        - synchronizing coefficient (defaults to sys.Ks)
%     save_path - export PNG if set
%     visible   - 'on' (default) / 'off'
%
%   Reference: Kundur Sec 12.3.1 (power-angle and synchronizing torque).

if nargin < 2, options = struct(); end
visible   = get_opt(options, 'visible', 'on');
t_end     = get_opt(options, 't_end', 5.0);
dt        = get_opt(options, 'dt', 0.005);
input_t   = get_opt(options, 'input', 'impulse');
mag       = get_opt(options, 'magnitude', 0.05);

A = sys.A;
b = sys.b(:, 1);            % delta_Tm input column
n = size(A, 1);

Ks = get_opt(options, 'Ks', NaN);
if isnan(Ks)
    if isfield(sys, 'Ks') && ~isempty(sys.Ks)
        Ks = sys.Ks;
    elseif isfield(sys, 'K1') && ~isempty(sys.K1)
        Ks = sys.K1;       % constant-flux synchronizing coefficient
    else
        Ks = 1.0;
    end
end

t = 0:dt:t_end;
nt = numel(t);
x = zeros(n, nt);

switch lower(input_t)
    case 'impulse'
        x0 = b * mag;
        Phi = expm(A * dt);
        x(:, 1) = x0;
        for k = 2:nt
            x(:, k) = Phi * x(:, k-1);
        end
    case 'step'
        Phi = expm(A * dt);
        if rcond(A) > 1e-12
            Gamma = A \ (Phi - eye(n));
        else
            Gamma = dt * eye(n);
        end
        for k = 2:nt
            x(:, k) = Phi * x(:, k-1) + Gamma * (b * mag);
        end
    otherwise
        error('smib_plot_power_response:badInput', 'input must be impulse or step');
end

ddelta = x(2, :);           % delta_delta (rad)
dPe = Ks * ddelta;          % delta_Pe ~= Ks * delta_delta (pu)

fig = figure('Name', 'SMIB power response', 'Color', 'w', ...
    'Position', [80 80 760 460], 'Visible', visible);
ax = axes(fig); hold(ax, 'on');

plot(ax, t, dPe, 'LineWidth', 1.8, 'Color', [0.18 0.49 0.20]);
yline(ax, 0, '-', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.8, ...
    'HandleVisibility', 'off');

style_axis(ax);
xlabel(ax, 'Time (s)');
ylabel(ax, '\Delta P_e  (pu)');
model = '';
if isfield(sys, 'model'); model = sys.model; end
title(ax, 'Electrical power deviation  \DeltaP_e \approx K_S \Delta\delta', ...
    'FontWeight', 'bold', 'Color', [0 0 0]);
st = subtitle(ax, sprintf('SMIB %s model, K_S = %.3f, %s \\DeltaT_m = %.3g pu', ...
    model_label(model), Ks, input_t, mag));
st.Color = [0 0 0];
hold(ax, 'off');

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
