function render_ne39_5sg5ibr_fault_load_figures(only)
% Optional: render_ne39_5sg5ibr_fault_load_figures('electrical') renders
% only the eight-panel electrical figure; no argument renders all figures.
%RENDER_NE39_5SG5IBR_FAULT_LOAD_FIGURES Render the NE39 5SG+5IBR report plots.
% Presentation only: every series is read unchanged from the report CSV files
% exported by generate_ne39_5sg5ibr_fault_load_report_data.  Pages follow the
% delivered NE39 160s report idiom: Times (matching the xelatex body), LaTeX
% interpreter, dashed grid, no axis box, vector PDF via exportgraphics, and
% the ONE shared legend lives at the top of each page with no box.  The event
% marks are drawn at the actual applied times (fault 60-60.15 s, load step
% 100 s); there is no SG breaker state strip because no SG breaker event
% exists in this chronology.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
data_dir = fullfile(root,'docs','source','figures','ne39_5sg5ibr_fault_load');
% Report figures match the xelatex body font (newtx = Times).
font_name = 'Times New Roman';
colors = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.9290 0.6940 0.1250; ...
          0.4940 0.1840 0.5560; 0.4660 0.6740 0.1880];
old = struct('axes',get(groot,'defaultAxesFontName'), ...
             'text',get(groot,'defaultTextFontName'), ...
             'legend',get(groot,'defaultLegendFontName'), ...
             'ti',get(groot,'defaultTextInterpreter'), ...
             'ai',get(groot,'defaultAxesTickLabelInterpreter'), ...
             'li',get(groot,'defaultLegendInterpreter'), ...
             'gl',get(groot,'defaultAxesGridLineStyle'), ...
             'bx',get(groot,'defaultAxesBox'));
cleanup = onCleanup(@() restore_fonts(old)); %#ok<NASGU>
set(groot,'defaultTextInterpreter','latex', ...
    'defaultAxesTickLabelInterpreter','latex', ...
    'defaultLegendInterpreter','latex', ...
    'defaultLegendFontSize',9,'defaultAxesFontSize',9,'defaultTextFontSize',9, ...
    'defaultAxesGridLineStyle','--','defaultAxesBox','off', ...
    'defaultAxesFontName',font_name,'defaultTextFontName',font_name, ...
    'defaultLegendFontName',font_name);

if nargin >= 1 && strcmpi(char(only),'electrical')
    render_electrical_panels(data_dir,colors);
    return;
end

render_pf(data_dir,colors);
render_envelope(data_dir,colors);
render_ts_families(data_dir,colors);
render_dq_pages(data_dir,colors);
render_sg_frequency(data_dir,colors);
render_mode_pq(data_dir,colors);
render_electrical_panels(data_dir,colors);
end

function render_mode_pq(data_dir,c)
% Per-device mode strip, P/Q power panels over the full 160-s chronology, in
% the delivered report idiom: mode strip + SG rotor-frequency panel on top,
% (a) active power and (b) reactive power below, pu on the system base, raw
% accepted samples.  No SG breaker strip: no SG breaker event exists.
M = read_report_csv(data_dir,'mode_level_timeline.csv');
P = read_report_csv(data_dir,'ts_device_power.csv');
S = read_report_csv(data_dir,'ts_sg_frequency.csv');
marks = read_report_csv(data_dir,'event_marks.csv');
ids = {'SG31','SG32','SG35','SG38','SG39','IBR30','IBR33','IBR34','IBR36','IBR37'};
ibr = ids(6:end);

f = report_figure([40 20 1150 1050]);
tiledlayout(f,4,1,'TileSpacing','compact','Padding','compact');
% Strip 1: GFM/GFL mode of each IBR (2 = GFM, 1 = GFL, 0 = open).  Static by
% design here (no mode-change event), which is itself the point of the study.
% The one shared legend lives on this first tile, at the top, no box.
ax1 = nexttile; hold on;
for k = 1:numel(ibr)
    plot(M.time_s,M.([ibr{k} '_level']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1,'DisplayName',ibr{k});
end
set(gca,'YTick',[0 1 2],'YTickLabel',{'open','GFL','GFM'});
draw_event_marks(marks);
grid on; ylabel('mode');
title('Grid-forming / grid-following mode (static by design)');
lg = legend(ax1,'Orientation','horizontal','Location','northoutside', ...
    'NumColumns',5,'Box','off','FontSize',9); %#ok<NASGU>
xlim([0 160]); ylim([-0.2 2.2]);
% Strip 2: the five SG rotor speeds (absolute pu, 1.0 at nominal).
nexttile; hold on;
for k = 1:5
    plot(S.time_s,S.([ids{k} '_omega_pu']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.2,'HandleVisibility','off');
end
yline(1,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('\omega_{SG} (pu)');
title('Five synchronous machines stay the reference (rotor speed)');
xlim([0 160]); ylim([0.98 1.02]);
% (a) active power, pu system base.
nexttile; hold on;
for k = 1:numel(ids)
    plot(P.time_s,P.([ids{k} '_P_MW'])/100,'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.0,'HandleVisibility','off');
end
draw_event_marks(marks);
grid on; ylabel('P [pu]');
title('(a) Per-device active power');
xlim([0 160]);
% (b) reactive power, pu system base.
nexttile; hold on;
for k = 1:numel(ids)
    plot(P.time_s,P.([ids{k} '_Q_MVAr'])/100,'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.0,'HandleVisibility','off');
end
draw_event_marks(marks);
grid on; ylabel('Q [pu]'); xlabel('t [s]');
title('(b) Per-device reactive power');
xlim([0 160]);
export_report(f,data_dir,'matlab_5sg5ibr_mode_pq.pdf');
end

function render_electrical_panels(data_dir,c)
% Eight-panel electrical response in the delivered report idiom:
% (a) P, (b) Q, (c) i_d, (d) i_q, (e) device/COI frequency,
% (f) device voltage magnitude, (g) network maximum voltage,
% (h) network minimum voltage -- all pu, raw accepted samples, full window.
P = read_report_csv(data_dir,'ts_device_power.csv');
D = read_report_csv(data_dir,'ts_device_dq_currents.csv');
F = read_report_csv(data_dir,'ts_device_frequency.csv');
C = read_report_csv(data_dir,'ts_coi_frequency.csv');
V = read_report_csv(data_dir,'ts_bus_voltages_devices.csv');
E = read_report_csv(data_dir,'ts_bus_vmin_vmax.csv');
marks = read_report_csv(data_dir,'event_marks.csv');
ids = {'SG31','SG32','SG35','SG38','SG39','IBR30','IBR33','IBR34','IBR36','IBR37'};
ibr = ids(6:end);

f = report_figure([30 20 900 1150]);
tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
% One shared legend row above panel (a), no box; every data line hides its
% handle so no per-panel legend boxes appear.
ax_a = nexttile; hold on;
for k = 1:5
    plot(P.time_s,P.([ids{k} '_P_MW'])/100,'k-','LineWidth',1.0, ...
        'DisplayName',ids{k});
end
for k = 1:numel(ibr)
    plot(P.time_s,P.([ibr{k} '_P_MW'])/100,'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8,'DisplayName',ibr{k});
end
plot(nan,nan,'k-','LineWidth',1.5,'DisplayName','COI');
draw_event_marks(marks);
grid on; ylabel('P [pu]'); title('(a) Active power');
lgd = legend(ax_a,'Orientation','horizontal','Location','northoutside', ...
    'NumColumns',6,'FontSize',9,'Box','off'); %#ok<NASGU>
xlim([0 160]);
nexttile; hold on;
for k = 1:5
    plot(P.time_s,P.([ids{k} '_Q_MVAr'])/100,'k-','LineWidth',1.0, ...
        'HandleVisibility','off');
end
for k = 1:numel(ibr)
    plot(P.time_s,P.([ibr{k} '_Q_MVAr'])/100,'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8,'HandleVisibility','off');
end
draw_event_marks(marks);
grid on; ylabel('Q [pu]'); title('(b) Reactive power');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ibr)
    plot(D.time_s,D.([ibr{k} '_id_pu']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8,'HandleVisibility','off');
end
draw_event_marks(marks);
grid on; ylabel('i_d [pu]'); title('(c) d-axis current');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ibr)
    plot(D.time_s,D.([ibr{k} '_iq_pu']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8,'HandleVisibility','off');
end
draw_event_marks(marks);
grid on; ylabel('i_q [pu]'); title('(d) q-axis current');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ibr)
    plot(F.time_s,F.([ibr{k} '_f_Hz']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',0.8,'HandleVisibility','off');
end
plot(C.time_s,C.coi_frequency_Hz,'k-','LineWidth',1.5,'HandleVisibility','off');
yline(60,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('f [Hz]'); title('(e) Device / COI frequency');
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ids)
    plot(V.time_s,V.([ids{k} '_V_pu']),'Color',c(mod(k-1,5)+1,:)*0.5, ...
        'LineWidth',0.6,'HandleVisibility','off');
end
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('$|V|$ [pu]'); xlabel('t [s]');
title('(f) Device terminal voltage');
xlim([0 160]);
nexttile; hold on;
plot(E.time_s,E.v_max_pu,'Color',c(1,:),'LineWidth',1.1);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('$|V|$ [pu]'); xlabel('t [s]');
title('(g) Network maximum voltage');
xlim([0 160]);
nexttile; hold on;
plot(E.time_s,E.v_min_pu,'Color',c(2,:),'LineWidth',1.1);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; ylabel('$|V|$ [pu]'); xlabel('t [s]');
title('(h) Network minimum voltage');
xlim([0 160]);
export_report(f,data_dir,'matlab_5sg5ibr_electrical.pdf');
end

function render_pf(data_dir,c)
T = read_report_csv(data_dir,'normal_pf_bus.csv');
f = report_figure([120 120 1100 480]);
tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
nexttile; bar(T.bus_id,T.V_pu,0.72,'FaceColor',c(1,:),'EdgeColor','none');
xlabel('Bus ID'); ylabel('$|V|$ (pu)'); title('Solved bus-voltage magnitude'); grid on;
nexttile; bar(T.bus_id,T.angle_deg,0.72,'FaceColor',c(2,:),'EdgeColor','none');
xlabel('Bus ID'); ylabel('Angle (deg)'); title('Solved bus-voltage angle'); grid on;
export_report(f,data_dir,'matlab_5sg5ibr_pf.pdf');
end

function render_envelope(data_dir,c)
T = read_report_csv(data_dir,'ts_bus_vmin_vmax.csv');
marks = read_report_csv(data_dir,'event_marks.csv');
f = report_figure([100 100 1120 500]);
hold on;
fill_between(ax_from(f),T.time_s,T.v_min_pu,T.v_max_pu,c(1,:),0.12);
plot(T.time_s,T.v_max_pu,'Color',c(1,:),'LineWidth',1.2);
plot(T.time_s,T.v_min_pu,'Color',c(2,:),'LineWidth',1.2);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('$|V|$ (pu)');
title('Bus-voltage envelope over the 160-s chronology (actual run)');
xlim([0 160]); ylim([0.90 1.14]);
legend({'envelope','$\max_k |V_k|$','$\min_k |V_k$'},'Location','south east');
export_report(f,data_dir,'matlab_5sg5ibr_envelope.pdf');

% Fault-window detail.
f = report_figure([140 140 900 500]);
hold on;
plot(T.time_s,T.v_max_pu,'Color',c(1,:),'LineWidth',1.2);
plot(T.time_s,T.v_min_pu,'Color',c(2,:),'LineWidth',1.2);
yline(1.0,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('$|V|$ (pu)');
title('Voltage envelope, fault-window detail');
xlim([59.4 60.8]); ylim([0.90 1.14]);
export_report(f,data_dir,'matlab_5sg5ibr_envelope_fault.pdf');
end

function render_ts_families(data_dir,c)
F = read_report_csv(data_dir,'ts_device_frequency.csv');
C = read_report_csv(data_dir,'ts_coi_frequency.csv');
P = read_report_csv(data_dir,'ts_device_power.csv');
I = read_report_csv(data_dir,'ts_device_current.csv');
M = read_report_csv(data_dir,'mode_level_timeline.csv');
S = read_report_csv(data_dir,'ts_sg_frequency.csv');
marks = read_report_csv(data_dir,'event_marks.csv');
ids = {'SG31','SG32','SG35','SG38','SG39','IBR30','IBR33','IBR34','IBR36','IBR37'};
ibr_ids = ids(6:end);

f = report_figure([40 30 1250 900]);
tiledlayout(f,3,2,'TileSpacing','compact','Padding','compact');
% (a) COI frequency with per-device frequency detail.
nexttile; hold on;
for k = 1:numel(ibr_ids)
    plot(F.time_s,F.([ibr_ids{k} '_f_Hz']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',0.9,'DisplayName',ibr_ids{k});
end
plot(C.time_s,C.coi_frequency_Hz,'k-','LineWidth',1.6,'DisplayName','COI');
grid on; xlabel('Time (s)'); ylabel('f (Hz)');
title('Device and COI frequency');
legend('Location','best','NumColumns',2);
xlim([0 160]);
% (b) Device active power.
nexttile; hold on;
for k = 1:numel(ids)
    plot(P.time_s,P.([ids{k} '_P_MW']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1,'DisplayName',ids{k});
end
grid on; xlabel('Time (s)'); ylabel('P (MW)');
title('Device active power (MW)');
legend('Location','best','NumColumns',2);
xlim([0 160]);
% (c) Device reactive power.
nexttile; hold on;
for k = 1:numel(ids)
    plot(P.time_s,P.([ids{k} '_Q_MVAr']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1,'DisplayName',ids{k});
end
grid on; xlabel('Time (s)'); ylabel('Q (MVAr)');
title('Device reactive power (MVAr)');
legend('Location','best','NumColumns',2);
xlim([0 160]);
% (d) Device current magnitude.
nexttile; hold on;
for k = 1:numel(ids)
    plot(I.time_s,I.([ids{k} '_I_pu']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1,'DisplayName',ids{k});
end
grid on; xlabel('Time (s)'); ylabel('|I| (pu, system base)');
title('Device current magnitude');
legend('Location','best','NumColumns',2);
xlim([0 160]);
% (e) The five SG rotor frequencies through fault and step.
nexttile; hold on;
for k = 1:5
    plot(S.time_s,S.([ids{k} '_f_Hz']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.3,'DisplayName',ids{k});
end
yline(60,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('f (Hz)');
title('Five SG rotor frequencies ($f_0\cdot\omega$) through fault and step');
legend('Location','best');
xlim([0 160]);
% (f) Device mode level (staggered across the whole chronology).
nexttile; hold on;
for k = 1:numel(ids)
    plot(M.time_s,M.([ids{k} '_level']) + 0.12*(k-1)/numel(ids), ...
        'Color',c(mod(k-1,5)+1,:),'LineWidth',1.0,'DisplayName',ids{k});
end
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('VF level (staggered)');
title('Device mode level (0 open / 1 GFL / 2 VF)');
legend('Location','best','NumColumns',2);
xlim([0 160]); ylim([-0.3 2.7]);
sgtitle('NE39 5SG+5IBR fault + load-step chronology (actual run)','FontWeight','bold');
export_report(f,data_dir,'matlab_5sg5ibr_ts_pages.pdf');
end

function render_dq_pages(data_dir,c)
% Converter dq-frame currents (i_d, i_q of the EECON49 superset, device base).
% The states are read unchanged from the stored x_traj export; both frames
% follow the same split-page idiom (id on page one, iq on page two).
D = read_report_csv(data_dir,'ts_device_dq_currents.csv');
marks = read_report_csv(data_dir,'event_marks.csv');
ids = {'IBR30','IBR33','IBR34','IBR36','IBR37'};
for page = 1:2
    f = report_figure([60 60 1150 760]);
    tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
    for k = 1:numel(ids)
        nexttile; hold on;
        if page==1
            plot(D.time_s,D.([ids{k} '_id_pu']),'Color',c(mod(k-1,5)+1,:),'LineWidth',0.9);
            ylabel('i_d (pu dev)');
            title(sprintf('%s i_d',ids{k}));
        else
            plot(D.time_s,D.([ids{k} '_iq_pu']),'Color',c(mod(k-1,5)+1,:),'LineWidth',0.9);
            ylabel('i_q (pu dev)');
            title(sprintf('%s i_q',ids{k}));
        end
        grid on; xlabel('Time (s)');
        draw_event_marks(marks);
        xlim([0 160]);
    end
    % The 6th tile is unused; keep the layout rectangular without an axe.
    nexttile; axis off;
    if page==1
        sgtitle('Converter d-axis current states (device base, actual run)','FontWeight','bold');
        export_report(f,data_dir,'matlab_5sg5ibr_dq_id.pdf');
    else
        sgtitle('Converter q-axis current states (device base, actual run)','FontWeight','bold');
        export_report(f,data_dir,'matlab_5sg5ibr_dq_iq.pdf');
    end
end
end

function render_sg_frequency(data_dir,c)
% All five SG rotor frequencies from each plant's own omega state (x_traj
% slot 2 of the two-state block), read unchanged from the export.  Absolute pu
% speed, 1.0 at nominal; f_Hz = f0*omega.
S = read_report_csv(data_dir,'ts_sg_frequency.csv');
marks = read_report_csv(data_dir,'event_marks.csv');
ids = {'SG31','SG32','SG35','SG38','SG39'};
f = report_figure([100 100 1120 460]);
tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
for k = 1:numel(ids)
    plot(S.time_s,S.([ids{k} '_f_Hz']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1,'DisplayName',ids{k});
end
yline(60,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('f (Hz)');
title('SG rotor frequencies ($f_0\cdot\omega$)');
legend('Location','best','NumColumns',2);
xlim([0 160]);
nexttile; hold on;
for k = 1:numel(ids)
    plot(S.time_s,S.([ids{k} '_omega_pu']),'Color',c(mod(k-1,5)+1,:), ...
        'LineWidth',1.1,'HandleVisibility','off');
end
yline(1,':','Color',[.45 .45 .45],'HandleVisibility','off');
draw_event_marks(marks);
grid on; xlabel('Time (s)'); ylabel('\omega (pu)');
title('Absolute rotor speed (1.0 at nominal)');
xlim([0 160]);
sgtitle('Five two-state classical SG plants through fault and step','FontWeight','bold');
export_report(f,data_dir,'matlab_5sg5ibr_sg_frequency.pdf');
end

function draw_event_marks(marks)
for k = 1:height(marks)
    if marks.applied(k)
        xline(marks.t_s(k),':','Color',[.55 .55 .55],'HandleVisibility','off', ...
            'LineWidth',0.8);
    end
end
end

function ax = ax_from(f)
ax = gca(f);
end

function fill_between(ax,x,y1,y2,c,alpha)
pl = fill([x; flipud(x)],[y1; flipud(y2)],c, ...
    'FaceAlpha',alpha,'EdgeColor','none','DisplayName','envelope');
set(get(pl,'Parent'),'NextPlot','add'); %#ok<NASGU>
uistack(pl,'bottom');
end

function T = read_report_csv(data_dir,name)
T = readtable(fullfile(data_dir,name),'VariableNamingRule','preserve');
end

function f = report_figure(position)
f = figure('Visible','off','Color','w','Position',position,'PaperPositionMode','auto');
end

function export_report(f,data_dir,name)
drawnow;
exportgraphics(f,fullfile(data_dir,name),'ContentType','vector','BackgroundColor','white');
close(f);
end

function restore_fonts(old)
set(groot,'defaultAxesFontName',old.axes,'defaultTextFontName',old.text, ...
    'defaultLegendFontName',old.legend, ...
    'defaultTextInterpreter',old.ti, ...
    'defaultAxesTickLabelInterpreter',old.ai, ...
    'defaultLegendInterpreter',old.li, ...
    'defaultAxesGridLineStyle',old.gl, ...
    'defaultAxesBox',old.bx);
end
