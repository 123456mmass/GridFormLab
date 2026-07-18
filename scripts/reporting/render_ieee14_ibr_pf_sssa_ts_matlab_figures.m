function render_ieee14_ibr_pf_sssa_ts_matlab_figures()
%RENDER_IEEE14_IBR_PF_SSSA_TS_MATLAB_FIGURES Render report plots in MATLAB.
% Presentation only: every series is read unchanged from the report CSV files.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
data_dir = fullfile(root,'docs','source','figures','ieee14_ibr_pf_sssa_ts');
font_name = 'TH Sarabun PSK';
colors = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.9290 0.6940 0.1250; ...
          0.4940 0.1840 0.5560; 0.4660 0.6740 0.1880];
old = struct('axes',get(groot,'defaultAxesFontName'), ...
             'text',get(groot,'defaultTextFontName'), ...
             'legend',get(groot,'defaultLegendFontName'));
cleanup = onCleanup(@() restore_fonts(old));
set(groot,'defaultAxesFontName',font_name,'defaultTextFontName',font_name, ...
    'defaultLegendFontName',font_name,'defaultAxesFontSize',12, ...
    'defaultTextFontSize',12,'defaultLegendFontSize',10);

render_pf(data_dir,colors);
render_sssa(data_dir,colors);
render_pf_compare(data_dir,colors);
render_ts(data_dir,'fault_only_ts.csv','matlab_fault_only_ts.pdf',colors, ...
    'Fault-only time-domain simulation',true);
render_ts(data_dir,'sg_cycle_ts.csv','matlab_sg_cycle_ts.pdf',colors, ...
    'SG trip and return-request time-domain simulation',false);
end

function render_pf(data_dir,c)
T = read_report_csv(data_dir,'normal_pf_bus.csv');
f = report_figure([120 120 1100 480]);
tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
nexttile; bar(T.bus_id,T.V_pu,0.72,'FaceColor',c(1,:),'EdgeColor','none');
xlabel('Bus ID'); ylabel('|V| (pu)'); title('Solved bus-voltage magnitude'); grid on;
nexttile; bar(T.bus_id,T.angle_deg,0.72,'FaceColor',c(2,:),'EdgeColor','none');
xlabel('Bus ID'); ylabel('Angle (deg)'); title('Solved bus-voltage angle'); grid on;
export_report(f,data_dir,'matlab_normal_pf.pdf');

C = read_report_csv(data_dir,'normal_pf_convergence.csv');
f = report_figure([160 160 820 480]);
plot(C.iteration,C.max_mismatch_pu,'-o','Color',c(1,:),'LineWidth',1.5, ...
    'MarkerFaceColor',c(1,:));
xlabel('Iteration'); ylabel('Maximum mismatch (pu)');
title('Newton-Raphson convergence (linear vertical scale)'); grid on;
export_report(f,data_dir,'matlab_normal_pf_convergence.pdf');
end

function render_sssa(data_dir,c)
T = read_report_csv(data_dir,'normal_sssa_eigenvalues.csv');
f = report_figure([100 100 1120 470]);
tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
nexttile; scatter(T.real_1_per_s,T.imag_1_per_s,30,c(1,:),'filled'); hold on;
xline(0,'--r','Stability boundary','LabelVerticalAlignment','bottom');
xlabel('Real(\lambda) (1/s)'); ylabel('Imag(\lambda) (1/s)');
title('All 48 active-state eigenvalues'); grid on;
nexttile; scatter(T.real_1_per_s,T.imag_1_per_s,30,c(1,:),'filled'); hold on;
xline(0,'--r'); xlim([-400 20]); ylim([-25 25]);
xlabel('Real(\lambda) (1/s)'); ylabel('Imag(\lambda) (1/s)');
title('Low/medium-frequency detail'); grid on;
export_report(f,data_dir,'matlab_normal_sssa.pdf');
end

function render_pf_compare(data_dir,c)
T = read_report_csv(data_dir,'sg_trip_pf_compare.csv');
labels = cellstr(string(T.device_id));
f = report_figure([80 60 1000 850]);
tiledlayout(f,3,1,'TileSpacing','compact','Padding','compact');
nexttile; grouped_bar([T.P_pre_MW T.P_trip_MW T.P_return_MW],labels,c);
ylabel('P (MW)'); title('Active-power injection'); legend('Pre-trip','SG tripped','SG returned','Location','best');
nexttile; grouped_bar([T.Q_pre_MVAr T.Q_trip_MVAr T.Q_return_MVAr],labels,c);
ylabel('Q (MVAr)'); title('Reactive-power injection');
nexttile; grouped_bar([T.V_pre_pu T.V_trip_pu T.V_return_pu],labels,c);
ylabel('|V| (pu)'); xlabel('Indexed device'); title('Terminal-bus voltage');
export_report(f,data_dir,'matlab_sg_trip_pf_compare.pdf');
end

function grouped_bar(Y,labels,c)
b = bar(Y,'grouped');
color_index = [1 2 5];
for k=1:3, b(k).FaceColor=c(color_index(k),:); b(k).EdgeColor='none'; end
set(gca,'XTick',1:numel(labels),'XTickLabel',labels); grid on;
end

function render_ts(data_dir,csv_name,pdf_name,c,heading,include_fault_bus)
T = read_report_csv(data_dir,csv_name);
ids = {'SG1','IBR2','IBR3','IBR6','IBR8'};
f = report_figure([40 30 1250 820]);
tiledlayout(f,3,2,'TileSpacing','compact','Padding','compact');
plot_family(T,ids,'_angle_deg','Angle (deg)','Device angle',c);
plot_family(T,ids,'_frequency_Hz','Frequency (Hz)','Online-device frequency',c);
plot_family(T,ids,'_P_MW','P (MW)','Device active power',c);
plot_family(T,ids,'_Q_MVAr','Q (MVAr)','Device reactive power',c);
plot_family(T,ids,'_V_pu','|V| (pu)','Device terminal voltage',c);
if include_fault_bus
    nexttile; plot(T.time_s,T.fault_bus4_V_pu,'k','LineWidth',1.4); grid on;
    xlabel('Time (s)'); ylabel('|V_4| (pu)'); title('Fault-bus voltage');
else
    plot_family(T,ids,'_I_pu','|I| (pu)','Device current magnitude',c);
end
sgtitle(heading,'FontWeight','bold');
export_report(f,data_dir,pdf_name);
end

function plot_family(T,ids,suffix,ylabel_text,title_text,c)
nexttile; hold on;
for k=1:numel(ids)
    name = [ids{k} suffix];
    plot(T.time_s,T.(name),'Color',c(k,:),'LineWidth',1.25,'DisplayName',ids{k});
end
grid on; xlabel('Time (s)'); ylabel(ylabel_text); title(title_text);
if strcmp(suffix,'_frequency_Hz'), legend('Location','best'); end
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
    'defaultLegendFontName',old.legend);
end
