% Render the three NE39 report figures for the C++-edition report from the
% exported C++ run CSVs.  Layout/style is a 1:1 clone of
% scripts/reporting/render_ne39_160s_reclose_matlab_figures.m (same idiom,
% same sizes, same colors, same titles), only the data source and the two
% disclosed content adaptations differ:
%   (e) SG31 rotor frequency stands alone (the C++ record exports no IBR
%       frequency or COI series), and the two supervisory strips are
%       reconstructed from the C++ event log + guard record (the record
%       carries no per-sample mode column).
data_dir = fullfile('D:','4-year-project','GridFormLab','docs','source', ...
                    'figures','ne39_160s_reclose_cpp');
font_name = 'Times New Roman';
colors = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.9290 0.6940 0.1250; ...
          0.4940 0.1840 0.5560; 0.4660 0.6740 0.1880];
set(groot,'defaultTextInterpreter','latex', ...
    'defaultAxesTickLabelInterpreter','latex', ...
    'defaultLegendInterpreter','latex', ...
    'defaultLegendFontSize',9,'defaultAxesFontSize',9,'defaultTextFontSize',9, ...
    'defaultAxesGridLineStyle','--','defaultAxesBox','off', ...
    'defaultAxesFontName',font_name,'defaultTextFontName',font_name, ...
    'defaultLegendFontName',font_name);

% applied physical instants of the C++ event log + guard commit
mark_t = [20.0, 60.0, 60.15, 100.499];

render_pf(data_dir, colors);
render_mode_pq(data_dir, colors, mark_t);
render_electrical_panels(data_dir, colors, mark_t);
disp('cpp figures done');

function render_pf(data_dir, c)
T = read_report_csv(data_dir, 'normal_pf_bus.csv');
f = report_figure([120 120 1100 480]);
tiledlayout(f, 1, 2, 'TileSpacing','compact','Padding','compact');
nexttile; bar(T.bus_id, T.V_pu, 0.72, 'FaceColor', c(1,:), 'EdgeColor','none');
xlabel('Bus ID'); ylabel('$|V|$ (pu)'); title('Solved bus-voltage magnitude'); grid on;
nexttile; bar(T.bus_id, T.angle_deg, 0.72, 'FaceColor', c(2,:), 'EdgeColor','none');
xlabel('Bus ID'); ylabel('Angle (deg)'); title('Solved bus-voltage angle'); grid on;
export_report(f, data_dir, 'cpp_normal_pf.pdf');
end

function render_mode_pq(data_dir, c, mark_t)
M = read_report_csv(data_dir, 'mode_level_timeline.csv');
P = read_report_csv(data_dir, 'ts_device_power.csv');
ids = {'SG31','IBR30','IBR32','IBR33','IBR34','IBR35','IBR36','IBR37','IBR38','IBR39'};
ibr = ids(2:end);

f = report_figure([40 20 1150 1050]);
tiledlayout(f, 4, 1, 'TileSpacing','compact','Padding','compact');
ax1 = nexttile; hold on;
for k = 1:numel(ibr)
    plot(M.time_s, M.([ibr{k} '_level']), 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1, 'DisplayName', ibr{k});
end
set(gca,'YTick',[0 1 2],'YTickLabel',{'open','GFL','GFM'});
draw_event_marks(mark_t);
grid on; ylabel('mode');
title('Grid-forming / grid-following mode');
legend(ax1,'Orientation','horizontal','Location','northoutside', ...
    'NumColumns',5,'Box','off','FontSize',9);
xlim([0 160]); ylim([-0.2 2.2]);
nexttile; hold on;
plot(M.time_s, M.SG31_level, 'Color', c(1,:), 'LineWidth',1.3, 'HandleVisibility','off');
set(gca,'YTick',[0 2],'YTickLabel',{'offline','SG'});
draw_event_marks(mark_t);
grid on; ylabel('SG31');
title('SG31 breaker state (online / offline)');
xlim([0 160]); ylim([-0.3 2.3]);
nexttile; hold on;
for k = 1:numel(ids)
    plot(P.time_s, P.([ids{k} '_P_MW'])/100, 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',1.0, 'HandleVisibility','off');
end
draw_event_marks(mark_t);
grid on; ylabel('P [pu]');
title('(a) Per-device active power');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ids)
    plot(P.time_s, P.([ids{k} '_Q_MVAr'])/100, 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',1.0, 'HandleVisibility','off');
end
draw_event_marks(mark_t);
grid on; ylabel('Q [pu]'); xlabel('t [s]');
title('(b) Per-device reactive power');
xlim([0 160]);
export_report(f, data_dir, 'cpp_normal_mode_pq.pdf');
end

function render_electrical_panels(data_dir, c, mark_t)
P = read_report_csv(data_dir, 'ts_device_power.csv');
D = read_report_csv(data_dir, 'ts_device_dq_currents.csv');
S = read_report_csv(data_dir, 'ts_sg_frequency.csv');
V = read_report_csv(data_dir, 'ts_bus_voltages_devices.csv');
E = read_report_csv(data_dir, 'ts_bus_vmin_vmax.csv');
ids = {'SG31','IBR30','IBR32','IBR33','IBR34','IBR35','IBR36','IBR37','IBR38','IBR39'};
ibr = ids(2:end);

f = report_figure([30 20 900 1150]);
tiledlayout(f, 4, 2, 'TileSpacing','compact','Padding','compact');
ax_a = nexttile; hold on;
plot(P.time_s, P.SG31_P_MW/100, 'k-', 'LineWidth',1.1, 'DisplayName','SG31');
for k = 1:numel(ibr)
    plot(P.time_s, P.([ibr{k} '_P_MW'])/100, 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8, 'DisplayName', ibr{k});
end
draw_event_marks(mark_t);
grid on; ylabel('P [pu]'); title('(a) Active power');
legend(ax_a,'Orientation','horizontal','Location','northoutside', ...
    'NumColumns',6,'FontSize',9,'Box','off');
xlim([0 160]);
nexttile; hold on;
plot(P.time_s, P.SG31_Q_MVAr/100, 'k-', 'LineWidth',1.1, 'HandleVisibility','off');
for k = 1:numel(ibr)
    plot(P.time_s, P.([ibr{k} '_Q_MVAr'])/100, 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8, 'HandleVisibility','off');
end
draw_event_marks(mark_t);
grid on; ylabel('Q [pu]'); title('(b) Reactive power');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ibr)
    plot(D.time_s, D.([ibr{k} '_id_pu']), 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8, 'HandleVisibility','off');
end
draw_event_marks(mark_t);
grid on; ylabel('i_d [pu]'); title('(c) d-axis current');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ibr)
    plot(D.time_s, D.([ibr{k} '_iq_pu']), 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8, 'HandleVisibility','off');
end
draw_event_marks(mark_t);
grid on; ylabel('i_q [pu]'); title('(d) q-axis current');
xlim([0 160]);
nexttile; hold on;
plot(S.time_s, S.f_Hz, 'k-', 'LineWidth',1.5, 'HandleVisibility','off');
yline(60,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(mark_t);
grid on; ylabel('f [Hz]'); title('(e) SG31 rotor frequency');
xlim([0 160]);
nexttile; hold on;
plot(V.time_s, V.SG31_V_pu, 'k-', 'LineWidth',1.2, 'HandleVisibility','off');
for k = 1:numel(ibr)
    plot(V.time_s, V.([ibr{k} '_V_pu']), 'Color', c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8, 'HandleVisibility','off');
end
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(mark_t);
grid on; ylabel('$|V|$ [pu]'); xlabel('t [s]');
title('(f) Device terminal voltage');
xlim([0 160]);
nexttile; hold on;
plot(E.time_s, E.v_max_pu, 'Color', c(1,:), 'LineWidth',1.1);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(mark_t);
grid on; ylabel('$|V|$ [pu]'); xlabel('t [s]');
title('(g) Network maximum voltage');
xlim([0 160]);
nexttile; hold on;
plot(E.time_s, E.v_min_pu, 'Color', c(2,:), 'LineWidth',1.1);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(mark_t);
grid on; ylabel('$|V|$ [pu]'); xlabel('t [s]');
title('(h) Network minimum voltage');
xlim([0 160]);
export_report(f, data_dir, 'cpp_normal_electrical.pdf');
end

function draw_event_marks(mark_t)
for k = 1:numel(mark_t)
    xline(mark_t(k), ':', 'Color',[.55 .55 .55], 'HandleVisibility','off', ...
        'LineWidth',0.8);
end
end

function T = read_report_csv(data_dir, name)
T = readtable(fullfile(data_dir, name), 'VariableNamingRule','preserve');
end

function f = report_figure(position)
f = figure('Visible','off','Color','w','Position',position,'PaperPositionMode','auto');
end

function export_report(f, data_dir, name)
drawnow;
exportgraphics(f, fullfile(data_dir, name), 'ContentType','vector','BackgroundColor','white');
close(f);
end
