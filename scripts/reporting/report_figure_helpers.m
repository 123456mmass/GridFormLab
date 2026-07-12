function report_figure_helpers(action, varargin)
%REPORT_FIGURE_HELPERS  Shared figure exporters with caption metadata.
%   All figures are exported at >=200 dpi (default 250) with a documented
%   style map (report_style_map). No smoothing; no clipping; fault/clear
%   lines marked. Every caption carries case/model/scenario/data source/
%   generating command/fresh-saved/metric metadata.
%
%   Actions: pf_voltage, pf_angle, sssa_complex, ts_coi_angle, ts_speed,
%   ts_pe, fault_bus_voltage, fixed_adaptive_overlay, adaptive_dt_history.

switch lower(action)
case 'pf_voltage'
    plot_pf_voltage(varargin{:});
case 'pf_angle'
    plot_pf_angle(varargin{:});
case 'sssa_complex'
    plot_sssa_complex(varargin{:});
case 'ts_coi_angle'
    plot_ts_coi_angle(varargin{:});
case 'ts_speed'
    plot_ts_speed(varargin{:});
case 'ts_pe'
    plot_ts_pe(varargin{:});
case 'fault_bus_voltage'
    plot_fault_bus_voltage(varargin{:});
case 'fixed_adaptive_overlay'
    plot_fixed_adaptive_overlay(varargin{:});
case 'adaptive_dt_history'
    plot_adaptive_dt_history(varargin{:});
otherwise
    error('report_figure_helpers:unknownAction','Unknown action: %s',action);
end
end

function sm = sm()
sm = report_style_map();
end

function f = newfig(w, h)
f = figure('Visible','off','Color',sm().fig_color,'Position',[100 100 w h], ...
    'DefaultAxesFontSize',sm().font_size,'DefaultAxesFontName',sm().font_name);
end

function export(f, path)
exportgraphics(f, path, 'Resolution', sm().dpi);
close(f);
end

function mark_events(ax, t_fault, t_clear)
if ~isempty(t_fault)
    xline(ax, t_fault, '--', 'Color', sm().fault_on.color, 'LineWidth', sm().fault_on.line_width, ...
        'LabelOrientation','horizontal','HandleVisibility','off');
end
if ~isempty(t_clear)
    xline(ax, t_clear, '--', 'Color', sm().fault_clear.color, 'LineWidth', sm().fault_clear.line_width, ...
        'LabelOrientation','horizontal','HandleVisibility','off');
end
end

function plot_pf_voltage(bus_ids, vm_ours, vm_psat, vm_pgaz, path, caption_meta)
f = newfig(900, 450);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
x = 1:numel(bus_ids);
if ~isempty(vm_ours), plot(ax, x, vm_ours, sm().ours.line_style, 'Color', sm().ours.color, 'LineWidth', sm().ours.line_width, 'Marker', sm().ours.marker, 'MarkerFaceColor', sm().ours.color); end
if ~isempty(vm_psat), plot(ax, x, vm_psat, sm().psat.line_style, 'Color', sm().psat.color, 'LineWidth', sm().psat.line_width, 'Marker', sm().psat.marker); end
if ~isempty(vm_pgaz), plot(ax, x, vm_pgaz, sm().pgaz.line_style, 'Color', sm().pgaz.color, 'LineWidth', sm().pgaz.line_width, 'Marker', sm().pgaz.marker); end
xticks(x); xticklabels(string(bus_ids)); xtickangle(30);
xlabel('Bus ID'); ylabel('Voltage magnitude (pu)'); title('PF bus voltage magnitudes');
legend({sm().ours.display, sm().psat.display, sm().pgaz.display}, 'Location','best');
export(f, path);
write_caption(path, caption_meta);
end

function plot_pf_angle(bus_ids, va_ours, va_psat, va_pgaz, path, caption_meta)
f = newfig(900, 450);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
x = 1:numel(bus_ids);
if ~isempty(va_ours), plot(ax, x, va_ours, sm().ours.line_style, 'Color', sm().ours.color, 'LineWidth', sm().ours.line_width, 'Marker', sm().ours.marker, 'MarkerFaceColor', sm().ours.color); end
if ~isempty(va_psat), plot(ax, x, va_psat, sm().psat.line_style, 'Color', sm().psat.color, 'LineWidth', sm().psat.line_width, 'Marker', sm().psat.marker); end
if ~isempty(va_pgaz), plot(ax, x, va_pgaz, sm().pgaz.line_style, 'Color', sm().pgaz.color, 'LineWidth', sm().pgaz.line_width, 'Marker', sm().pgaz.marker); end
xticks(x); xticklabels(string(bus_ids)); xtickangle(30);
xlabel('Bus ID'); ylabel('Voltage angle (deg)'); title('PF bus voltage angles');
legend({sm().ours.display, sm().psat.display, sm().pgaz.display}, 'Location','best');
export(f, path);
write_caption(path, caption_meta);
end

function plot_sssa_complex(eigs_ours, eigs_ref, ref_label, path, caption_meta)
f = newfig(700, 600);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
xline(ax, 0, sm().imag_axis.line_style, 'Color', sm().imag_axis.color, 'LineWidth', sm().imag_axis.line_width);
if ~isempty(eigs_ref)
    scatter(ax, real(eigs_ref), imag(eigs_ref), 70, 'o', 'MarkerEdgeColor', sm().book.color, 'LineWidth', 1.4);
end
if ~isempty(eigs_ours)
    scatter(ax, real(eigs_ours), imag(eigs_ours), 46, 'filled', 'MarkerFaceColor', sm().ours.color);
end
axis(ax,'equal'); xlabel('Real part (1/s)'); ylabel('Imaginary part (rad/s)');
title('SSSA complex-plane eigenvalues');
legend({ref_label, 'Computed (Ours)'}, 'Location','best');
export(f, path);
write_caption(path, caption_meta);
end

function plot_ts_coi_angle(t, delta_ours, delta_psat, delta_pgaz, gen_labels, t_fault, t_clear, path, caption_meta)
f = newfig(900, 500);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
colors = sm().generators;
for k = 1:size(delta_ours,2)
    c = colors(mod(k-1,size(colors,1))+1,:);
    plot(ax, t, delta_ours(:,k), '-', 'Color', c, 'LineWidth', 1.4);
end
if ~isempty(delta_psat)
    for k = 1:size(delta_psat,2)
        c = colors(mod(k-1,size(colors,1))+1,:);
        plot(ax, t, delta_psat(:,k), '--', 'Color', c, 'LineWidth', 1.0);
    end
end
mark_events(ax, t_fault, t_clear);
xlabel('Time (s)'); ylabel('COI-relative angle (deg)'); title('TS COI-relative rotor angles');
export(f, path);
write_caption(path, caption_meta);
end

function plot_ts_speed(t, w_ours, w_psat, t_fault, t_clear, path, caption_meta)
f = newfig(900, 450);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
colors = sm().generators;
for k = 1:size(w_ours,2)
    c = colors(mod(k-1,size(colors,1))+1,:);
    plot(ax, t, w_ours(:,k)-1, '-', 'Color', c, 'LineWidth', 1.3);
end
if ~isempty(w_psat)
    for k = 1:size(w_psat,2)
        c = colors(mod(k-1,size(colors,1))+1,:);
        plot(ax, t, w_psat(:,k)-1, '--', 'Color', c, 'LineWidth', 1.0);
    end
end
mark_events(ax, t_fault, t_clear);
xlabel('Time (s)'); ylabel('Speed deviation (pu)'); title('TS speed deviations');
export(f, path);
write_caption(path, caption_meta);
end

function plot_ts_pe(t, pe_ours, pe_psat, t_fault, t_clear, path, caption_meta)
f = newfig(900, 450);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
colors = sm().generators;
for k = 1:size(pe_ours,2)
    c = colors(mod(k-1,size(colors,1))+1,:);
    plot(ax, t, pe_ours(:,k), '-', 'Color', c, 'LineWidth', 1.3);
end
if ~isempty(pe_psat)
    for k = 1:size(pe_psat,2)
        c = colors(mod(k-1,size(colors,1))+1,:);
        plot(ax, t, pe_psat(:,k), '--', 'Color', c, 'LineWidth', 1.0);
    end
end
mark_events(ax, t_fault, t_clear);
xlabel('Time (s)'); ylabel('Electrical power (MW)'); title('TS electrical power');
export(f, path);
write_caption(path, caption_meta);
end

function plot_fault_bus_voltage(t, v_ours, v_psat, t_fault, t_clear, path, caption_meta)
f = newfig(900, 450);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax, t, v_ours, sm().ours.line_style, 'Color', sm().ours.color, 'LineWidth', 1.6);
if ~isempty(v_psat)
    plot(ax, t, v_psat, sm().psat.line_style, 'Color', sm().psat.color, 'LineWidth', 1.4);
end
mark_events(ax, t_fault, t_clear);
ylim(ax, [0 1.2]);
xlabel('Time (s)'); ylabel('Fault-bus voltage (pu)'); title('Fault-bus voltage');
legend({sm().ours.display, sm().psat.display}, 'Location','best');
export(f, path);
write_caption(path, caption_meta);
end

function plot_fixed_adaptive_overlay(t, delta_fixed, delta_adaptive, t_fault, t_clear, path, caption_meta)
f = newfig(900, 600);
tl = tiledlayout(f, 2, 1, 'Padding','compact','TileSpacing','compact');
ax1 = nexttile(tl); hold(ax1,'on'); grid(ax1,'on'); box(ax1,'on');
plot(ax1, t, delta_fixed, sm().fixed.line_style, 'Color', sm().fixed.color, 'LineWidth', 1.5);
plot(ax1, t, delta_adaptive, sm().adaptive.line_style, 'Color', sm().adaptive.color, 'LineWidth', 1.5);
mark_events(ax1, t_fault, t_clear);
xlabel('Time (s)'); ylabel('COI angle (deg)'); title('Fixed vs adaptive overlay');
legend({sm().fixed.display, sm().adaptive.display}, 'Location','best');
ax2 = nexttile(tl); hold(ax2,'on'); grid(ax2,'on'); box(ax2,'on');
diff = delta_fixed - delta_adaptive;
plot(ax2, t, diff, '-', 'Color', [0.5 0 0.5], 'LineWidth', 1.3);
mark_events(ax2, t_fault, t_clear);
xlabel('Time (s)'); ylabel('Difference (deg)'); title('Fixed $-$ adaptive');
export(f, path);
write_caption(path, caption_meta);
end

function plot_adaptive_dt_history(t, dt_history, t_fault, t_clear, path, caption_meta)
f = newfig(900, 400);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
stairs(ax, t(2:end), dt_history, '-', 'Color', sm().ours.color, 'LineWidth', 1.4);
mark_events(ax, t_fault, t_clear);
xlabel('Time (s)'); ylabel('Step size $h$ (s)'); title('Adaptive step-size history');
export(f, path);
write_caption(path, caption_meta);
end

function write_caption(fig_path, meta)
% Write a sidecar .txt caption with the required metadata fields.
cap_path = [fig_path(1:end-4) '_caption.txt'];
fid = fopen(cap_path,'w'); z = onCleanup(@()fclose(fid)); %#ok<NASGU>
fns = fieldnames(meta);
for i = 1:numel(fns)
    v = meta.(fns{i});
    if isnumeric(v), v = mat2str(v(:).'); end
    fprintf(fid, '%s: %s\n', fns{i}, v);
end
end
