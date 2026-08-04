function out = generate_ieee14_switch_report_figures(opts)
%GENERATE_IEEE14_SWITCH_REPORT_FIGURES Reproduce the focused IEEE14 evidence.
%   Case data and event times follow docs/text/EECON49_[Nui].pdf.  The
%   switching method remains the project AGSI++ supervisor: seven equally
%   weighted terms [J_V,J_f,J_R,J_P,J_SCR,J_lock,J_GRA], with J_GRA=1-GRA.
%   The EECON49 profile uses the operational six-state SG and source-mapped
%   full-state IBR branches.  A PROJECT_DERIVED common GFM reference elects
%   the first committed GFM as the island angle/frequency leader.  No noise,
%   smoothing, clipping, or external numerical result is applied.

arguments
    opts.reuse_cache (1,1) logical = false
end

pf_init_paths();
outdir = fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'), mkdir(outdir); end

sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);
cachefile=fullfile('output','diagnostics','ieee14_switch_report_result.mat');
if opts.reuse_cache && exist(cachefile,'file')
    cached=load(cachefile,'out'); out=cached.out;
else
    out = ibr.padiyar_switch_tds(sys, ...
        T=160.0, dt=1e-2, ...
        sg_trip_time=20.0, sg_reclose_time=145.0, ...
        sg_reclose_mode="ideal_slack", coordinated_reclose_handback=true, ...
        coordinated_gfm_reference=true, ...
        step_on=50.0, step_off=145.0, step_factor=0.20, step_all_loads=false, ...
        fault_on=85.0, fault_clear=85.15, fault_bus=9, fault_Zf=0.01+0.01i, ...
        line_trip_time=110.0, line_reclose_time=145.0, line_from_bus=6, line_to_bus=13);
end
if out.diverged
    warning('report:ieee14Switch:sourceCaseDiverged', ...
        ['The source-data reclose case is fail-closed at t=%.3f s.  Figures show ' ...
         'only the raw valid prefix; no recovery claim is permitted.'],out.tgrid(end));
elseif ~out.newton_all_converged
    error('report:ieee14Switch:notConverged', ...
        'The source-data trajectory has unexplained non-converged steps.');
end

% A separate compressed gate isolates the reclose/handback contract.  It is
% not presented as the 160-s source chronology and does not replace its
% fail-closed result.
% SwitchableIbr6 contains committed-mode/timer state, so a second run must
% receive fresh device objects rather than the objects mutated by the long run.
sys_recovery = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, ...
    T_d_on=0.10, T_d_off=1.0);
recovery = ibr.padiyar_switch_tds(sys_recovery, ...
    T=4.0, dt=1e-2, sg_trip_time=1.0, sg_reclose_time=3.0, ...
    sg_reclose_mode="ideal_slack", coordinated_reclose_handback=true, ...
    coordinated_gfm_reference=true);
if recovery.diverged || ~recovery.newton_all_converged
    error('report:ieee14Switch:recoveryGate', ...
        'The compressed ideal-slack recovery gate did not converge.');
end
out.recovery_gate=recovery;

write_pf_tables(sys.pf,outdir);
supervisor_figure(out,outdir,'padiyar_switch_supervisor.png', ...
    'Full chronology: raw valid prefix (fail-closed)');
response_figure(out,outdir,'padiyar_switch_response.png', ...
    'Full chronology: raw valid prefix - no added noise, smoothing, or clipping');
supervisor_figure(recovery,outdir,'padiyar_switch_recovery_supervisor.png', ...
    'Compressed SG trip/reclose recovery gate');
response_figure(recovery,outdir,'padiyar_switch_recovery_response.png', ...
    'Compressed recovery response - no added noise, smoothing, or clipping');
cachedir=fullfile('output','diagnostics');
if ~exist(cachedir,'dir'), mkdir(cachedir); end
save(cachefile,'out','-v7.3');
fprintf('IEEE14_SWITCH_REPORT_FIGURES_DONE: %s\n',outdir);
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
fprintf(fid,'\\begin{tabular}{rrrrrrrr}\\toprule\nBus & Type & $|V|$ & $\\theta$ (deg) & $P_g$ & $Q_g$ & $P_L$ & $Q_L$ \\\\ \\midrule\n');
for k=1:height(bus)
    fprintf(fid,'%d & %s & %.5f & %+.4f & %+.5f & %+.5f & %.5f & %.5f \\\\\n', ...
        bus.bus(k),type_name(bus.type(k)),bus.V_pu(k),bus.angle_deg(k), ...
        bus.Pg_pu(k),bus.Qg_pu(k),bus.Pl_pu(k),bus.Ql_pu(k));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n'); clear cleaner

ep=pf.line_endpoints; line=table((1:size(ep,1)).',ep(:,1),ep(:,2), ...
    pf.line_flow_P(:),pf.line_flow_Q(:),pf.line_loss_P(:),pf.line_loss_Q(:), ...
    'VariableNames',{'line','from_bus','to_bus','P_from_pu','Q_from_pu','P_loss_pu','Q_loss_pu'});
writetable(line,fullfile(outdir,'pf_line_results.csv'));
fid=fopen(fullfile(outdir,'table_pf_line_results.tex'),'w'); cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated by scripts/reporting/generate_ieee14_switch_report_figures.m.\n');
fprintf(fid,'\\begin{tabular}{r@{\\hspace{0.8em}}r@{\\hspace{0.8em}}r@{\\hspace{0.8em}}r@{\\hspace{0.8em}}r@{\\hspace{0.8em}}r@{\\hspace{0.8em}}r}\\toprule\nLine & From & To & $P_{from}$ & $Q_{from}$ & $P_{loss}$ & $Q_{loss}$ \\\\ \\midrule\n');
for k=1:height(line)
    fprintf(fid,'%d & %d & %d & %+.6f & %+.6f & %+.6f & %+.6f \\\\\n', ...
        line.line(k),line.from_bus(k),line.to_bus(k),line.P_from_pu(k), ...
        line.Q_from_pu(k),line.P_loss_pu(k),line.Q_loss_pu(k));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n'); clear cleaner
end

function s=type_name(t)
if t==1, s='REF'; elseif t==2, s='PV'; elseif t==3, s='PQ'; else, s='?'; end
end
