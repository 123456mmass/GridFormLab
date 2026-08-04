function out = generate_ieee14_switch_report_figures(opts)
%GENERATE_IEEE14_SWITCH_REPORT_FIGURES Reproduce publishable IEEE14 evidence.
%   Case data and event times follow docs/text/EECON49_[Nui].pdf.  The
%   switching method remains the project AGSI++ supervisor: seven equally
%   weighted terms [J_V,J_f,J_R,J_P,J_SCR,J_lock,J_GRA], with J_GRA=1-GRA.
%   The EECON49 profile uses the operational six-state SG and source-mapped
%   full-state IBR branches.  The exact 160-s event contract is attempted with
%   the deterministic coordinated-reference route (no BO).  If the model exits
%   its validity domain, figures are explicitly diagnostic and stop at the last
%   accepted point.  Continuous presentation traces receive a seeded synthetic
%   measurement overlay; the saved raw trajectory and all decisions are intact.

arguments
    opts.reuse_cache (1,1) logical = false
end

pf_init_paths();
outdir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'), mkdir(outdir); end

sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);
write_pf_tables(sys.pf,outdir);
cachefile=fullfile('output','diagnostics','ieee14_switch_160_exact.mat');
if opts.reuse_cache && exist(cachefile,'file')
    cached=load(cachefile,'o'); out=cached.o;
else
    out=ibr.padiyar_switch_tds(sys,T=160,dt=1e-2, ...
        sg_trip_time=20,sg_reclose_time=145,sg_reclose_mode="ideal_slack", ...
        coordinated_reclose_handback=true,coordinated_gfm_reference=true, ...
        step_on=50,step_off=145,step_factor=0.20,step_all_loads=true, ...
        fault_on=85,fault_clear=85.15,fault_bus=9,fault_Zf=0.01+0.01i, ...
        line_trip_time=110,line_reclose_time=145,line_from_bus=6,line_to_bus=13);
    cachedir=fileparts(cachefile); if ~exist(cachedir,'dir'), mkdir(cachedir); end
    o=out; save(cachefile,'o','-v7.3');
end
out.pf=sys.pf;
out.event_contract=sys.switching_event_contract;
out.requested_horizon_s=160;
out.bo_controller_added=false;
out.presentation_noise=struct('kind','seeded synthetic measurement overlay', ...
    'seed_base',4901,'affects_solver_or_switching',false);
if out.diverged || ~out.newton_all_converged || out.tgrid(end)<160
    out.dynamic_status='DIAGNOSTIC_PREFIX_ONLY_FAIL_CLOSED';
    figure_title=sprintf('Diagnostic raw prefix to %.3f s (requested 160 s; fail-closed)',out.tgrid(end));
else
    out.dynamic_status='FULL_160_S_GATE_PASSED';
    figure_title='Full 160-s chronology';
end
supervisor_figure(out,outdir,'ieee14_switch_160_supervisor.png',figure_title);
electrical_figure(out,outdir,'ieee14_switch_160_electrical.png',figure_title);
fprintf('IEEE14_SWITCH_REPORT_FIGURES_DONE: %s [%s]\n',outdir,out.dynamic_status);
end

function supervisor_figure(o,outdir,filename,figure_title)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 6.35], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',10);
tl=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
title(tl,figure_title, ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');

ax=nexttile(tl,[1 2]); hold(ax,'on');
for j=1:numel(buses)
    plot(ax,t,o.index(:,j),'Color',c(j,:),'LineWidth',1.0, ...
        'DisplayName',sprintf('IBR%d (bus %d)',j,buses(j)));
end
yline(ax,o.agsi_up,'k-','\Gamma_{on}','LineWidth',1.0,'HandleVisibility','off');
yline(ax,o.agsi_down,'k--','\Gamma_{off}','LineWidth',1.0,'HandleVisibility','off');
ylabel(ax,'AGSI++ [-]'); event_lines(ax,o,true); grid(ax,'on'); box(ax,'on');
legend(ax,'Location','northoutside','NumColumns',4);

ax=nexttile(tl); stairs(ax,t,o.GRA(:,1),'k-','LineWidth',1.3); grid(ax,'on'); box(ax,'on');
ylim(ax,[-0.1 1.1]); yticks(ax,[0 1]); yticklabels(ax,{'missing','available'});
ylabel(ax,'GRA'); event_lines(ax,o,false);

ax=nexttile(tl); stairs(ax,t,o.ref_code,'Color',[.35 .15 .55],'LineWidth',1.3); grid(ax,'on'); box(ax,'on');
ylim(ax,[-1.2 4.2]); yticks(ax,-1:4); yticklabels(ax,{'none','SG','IBR1','IBR2','IBR3','IBR4'});
ylabel(ax,'plot reference'); event_lines(ax,o,false);

for j=1:numel(buses)
    ax=nexttile(tl); stairs(ax,t,o.mode(:,j),'Color',c(j,:),'LineWidth',1.4); grid(ax,'on'); box(ax,'on');
    ylim(ax,[-0.1 1.1]); yticks(ax,[0 1]); yticklabels(ax,{'GFL','GFM'});
    ylabel(ax,sprintf('IBR%d bus %d',j,buses(j))); event_lines(ax,o,false);
    if j>2, xlabel(ax,'time (s)'); end
end
exportgraphics(f,fullfile(outdir,filename),'Resolution',220);
close(f);
end

function response_figure(o,outdir,filename,figure_title)
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 5.15], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',9);
tl=tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');
title(tl,figure_title, ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
h=panel(nexttile(tl),t,o.P_ibr,c,buses,'P (pu)','(a) Active power');
panel(nexttile(tl),t,o.Q_ibr,c,buses,'Q (pu)','(b) Reactive power');
panel(nexttile(tl),t,o.Vbus,c,buses,'|V| (pu)','(c) PCC voltage');
panel(nexttile(tl),t,o.f_ibr,c,buses,'f (Hz)','(d) PLL / virtual-rotor frequency');
for ax=findall(f,'Type','axes').'
    event_lines(ax,o,false); xlabel(ax,'time (s)');
end
lg=legend(h, ...
    arrayfun(@(j)sprintf('IBR%d bus %d',j,buses(j)),1:numel(buses),'UniformOutput',false), ...
    'Orientation','horizontal','NumColumns',4);
lg.Layout.Tile='south';
set(lg,'FontName','Times New Roman','FontSize',9);
exportgraphics(f,fullfile(outdir,filename),'Resolution',220);
close(f);
end

function electrical_figure(o,outdir,filename,figure_title) %#ok<INUSD>
t=o.tgrid; buses=o.ibr_buses; c=lines(numel(buses));
f=figure('Color','w','Units','inches','Position',[1 1 5.90 7.60], ...
    'Visible','off','DefaultAxesFontName','Times New Roman', ...
    'DefaultAxesFontSize',11,'DefaultTextFontName','Times New Roman', ...
    'DefaultTextFontSize',11,'DefaultLegendFontName','Times New Roman', ...
    'DefaultLegendFontSize',9);
tl=tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');
title(tl,'Diagnostic electrical prefix -- seeded display-only measurement overlay', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
ax=nexttile(tl); h=panel_noise(ax,t,o.P_ibr,c,'P (pu)','(a) Active power',1e-3,4901);
hsg=sg_overlay(ax,t,o.sg_P,1e-3,4911);
ax=nexttile(tl); panel_noise(ax,t,o.Q_ibr,c,'Q (pu)','(b) Reactive power',1e-3,4902);
sg_overlay(ax,t,o.sg_Q,1e-3,4912);
ax=nexttile(tl); panel_noise(ax,t,o.id_ibr,c,'i_d (pu)','(c) d-axis current',1e-3,4903);
sg_overlay(ax,t,o.sg_id,1e-3,4913);
ax=nexttile(tl); panel_noise(ax,t,o.iq_ibr,c,'i_q (pu)','(d) q-axis current',1e-3,4904);
sg_overlay(ax,t,o.sg_iq,1e-3,4914);
ax=nexttile(tl); panel_noise(ax,t,o.f_ibr,c,'f (Hz)','(e) PLL / virtual-rotor frequency',2e-3,4905);
sg_overlay(ax,t,o.f_sg,2e-3,4915);
ax=nexttile(tl); panel_noise(ax,t,o.ang_ibr*180/pi,c,'angle (deg)','(f) device angle',2e-2,4906);
sg_overlay(ax,t,o.sg_delta*180/pi,2e-2,4916);
panel_noise(nexttile(tl),t,o.Vbus,c,'|V| (pu)','(g) PCC voltage',5e-4,4907);
panel_noise(nexttile(tl),t,o.Vmin,[.15 .15 .15],'min |V| (pu)','(h) Network minimum voltage',5e-4,4908);
for ax=findall(f,'Type','axes').'
    event_lines(ax,o,false); xlabel(ax,'time (s)');
end
names=arrayfun(@(j)sprintf('IBR%d bus %d',j,buses(j)), ...
    1:numel(buses),'UniformOutput',false);
lg=legend([h hsg],[names {sprintf('SG bus %d',o.sg_bus)}], ...
    'Orientation','horizontal','NumColumns',5);
lg.Layout.Tile='south'; set(lg,'FontName','Times New Roman','FontSize',9);
exportgraphics(f,fullfile(outdir,filename),'Resolution',220); close(f);
end

function h=panel_noise(ax,t,y,c,ylab,ttl,sigma,seed)
stream=RandStream('mt19937ar','Seed',seed);
ydisplay=y+sigma*randn(stream,size(y));
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for j=1:size(y,2), h(j)=plot(ax,t,ydisplay(:,j),'Color',c(j,:),'LineWidth',0.75); end %#ok<AGROW>
ylabel(ax,ylab); title(ax,ttl,'FontSize',11,'FontWeight','bold');
end

function h=sg_overlay(ax,t,y,sigma,seed)
stream=RandStream('mt19937ar','Seed',seed);
ydisplay=y+sigma*randn(stream,size(y));
h=plot(ax,t,ydisplay,'k--','LineWidth',1.0);
end

function h=panel(ax,t,y,c,buses,ylab,ttl)
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for j=1:numel(buses), h(j)=plot(ax,t,y(:,j),'Color',c(j,:),'LineWidth',0.85); end %#ok<AGROW>
ylabel(ax,ylab); title(ax,ttl,'FontSize',11,'FontWeight','bold');
end

function event_lines(ax,o,show_labels)
if nargin<3, show_labels=false; end
if show_labels
    labels={'SG trip','load +20%','fault','clear','line 6-13 trip','restore'};
else
    labels=repmat({''},1,6);
end
xline(ax,o.sg_trip_time,':',labels{1},'Color',[.15 .15 .15],'LineWidth',0.8, ...
    'LabelVerticalAlignment','bottom','HandleVisibility','off');
xline(ax,o.step_on,':',labels{2},'Color',[.55 .15 .55],'LineWidth',0.8, ...
    'LabelVerticalAlignment','top','HandleVisibility','off');
xline(ax,o.fault_on,':',labels{3},'Color',[.75 .10 .10],'LineWidth',0.8, ...
    'LabelVerticalAlignment','top','HandleVisibility','off');
xline(ax,o.fault_clear,':',labels{4},'Color',[.75 .10 .10],'LineWidth',0.8, ...
    'LabelVerticalAlignment','bottom','HandleVisibility','off');
xline(ax,o.line_trip_time,':',labels{5},'Color',[.80 .45 .05],'LineWidth',0.8, ...
    'LabelVerticalAlignment','top','HandleVisibility','off');
xline(ax,o.sg_reclose_time,':',labels{6},'Color',[.10 .35 .65],'LineWidth',0.8, ...
    'LabelVerticalAlignment','bottom','HandleVisibility','off');
if isfield(o,'requested_horizon_s') && o.tgrid(end)<o.requested_horizon_s
    xline(ax,o.tgrid(end),'r-','validity exit','LineWidth',1.0, ...
        'LabelVerticalAlignment','middle','HandleVisibility','off');
end
xlim(ax,[o.tgrid(1) o.tgrid(end)]);
end

function write_pf_tables(pf,outdir)
bus=table(pf.external_bus_ids(:),pf.bus_type(:),pf.bus_voltage(:), ...
    pf.bus_angle_deg(:),pf.P_generation(:),pf.Q_generation(:), ...
    pf.P_load(:),pf.Q_load(:),'VariableNames', ...
    {'bus','type','V_pu','angle_deg','Pg_pu','Qg_pu','Pl_pu','Ql_pu'});
writetable(bus,fullfile(outdir,'pf_bus_results.csv'));
fid=fopen(fullfile(outdir,'table_pf_bus_results.tex'),'w'); cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated by scripts/reporting/generate_ieee14_switch_report_figures.m.\n');
fprintf(fid,'\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}rlrrrrrr@{}}\\toprule\nBus & Type & $|V|$ & $\\theta$ (deg) & $P_g$ & $Q_g$ & $P_L$ & $Q_L$ \\\\ \\midrule\n');
for k=1:height(bus)
    v=[bus.V_pu(k),bus.angle_deg(k),bus.Pg_pu(k),bus.Qg_pu(k),bus.Pl_pu(k),bus.Ql_pu(k)];
    v(abs(v)<0.5e-5)=0; % suppress signed zero at the published precision
    fprintf(fid,'%d & %s & %.5f & %.4f & %.5f & %.5f & %.5f & %.5f \\\\\n', ...
        bus.bus(k),type_name(bus.type(k)),v(1),v(2),v(3),v(4),v(5),v(6));
end
fprintf(fid,'\\bottomrule\\end{tabular*}\n'); clear cleaner

ep=pf.line_endpoints; line=table((1:size(ep,1)).',ep(:,1),ep(:,2), ...
    pf.line_flow_P(:),pf.line_flow_Q(:),pf.line_loss_P(:),pf.line_loss_Q(:), ...
    'VariableNames',{'line','from_bus','to_bus','P_from_pu','Q_from_pu','P_loss_pu','Q_loss_pu'});
writetable(line,fullfile(outdir,'pf_line_results.csv'));
fid=fopen(fullfile(outdir,'table_pf_line_results.tex'),'w'); cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated by scripts/reporting/generate_ieee14_switch_report_figures.m.\n');
fprintf(fid,'\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}rrrrrrr@{}}\\toprule\nLine & From & To & $P_{from}$ & $Q_{from}$ & $P_{loss}$ & $Q_{loss}$ \\\\ \\midrule\n');
for k=1:height(line)
    v=[line.P_from_pu(k),line.Q_from_pu(k),line.P_loss_pu(k),line.Q_loss_pu(k)];
    v(abs(v)<0.5e-6)=0; % suppress signed zero at the published precision
    fprintf(fid,'%d & %d & %d & %.6f & %.6f & %.6f & %.6f \\\\\n', ...
        line.line(k),line.from_bus(k),line.to_bus(k),v(1),v(2),v(3),v(4));
end
fprintf(fid,'\\bottomrule\\end{tabular*}\n'); clear cleaner
end

function s=type_name(t)
if t==1, s='REF'; elseif t==2, s='PV'; elseif t==3, s='PQ'; else, s='?'; end
end
