function [fig,png] = plot_ts_result(r,label,root,case_id,outpath)
%PLOT_TS_RESULT Canonical transient-stability plots (separate figures).
%   [FIG,PNG] = PLOT_TS_RESULT(R,LABEL,ROOT,CASE_ID) plots the TS result R in
%   four separate figures (rotor angle, absolute rotor speed, electrical
%   power, fault-bus voltage). PNG is the rotor-angle figure path; the other
%   paths use suffixes _omega, _pe, and _voltage.
%   [FIG,PNG] = PLOT_TS_RESULT(R,LABEL,ROOT,CASE_ID,OUTPATH) saves to the
%   explicit OUTPATH instead (used by report generators).
%
%   Display convention: plot the stored absolute rotor angle delta_i(t).
%   COI-relative/pairwise and initial-angle-subtracted quantities remain
%   verification metrics in print_ts_checks; they are not used here.
if nargin<5 || isempty(outpath)
    outdir=fullfile(root,'output','figures','ts');
    if ~exist(outdir,'dir'), mkdir(outdir); end
    png=fullfile(outdir,sprintf('%s_%s.png',datestr(now,'yyyymmdd_HHMMSS'),case_id));
else
    png=outpath;
end
t=r.t(:); ng=size(r.delta,2); colors=lines(ng);
if isfield(r,'gen_buses'), gb=r.gen_buses(:); else, gb=(1:ng)'; end
labels=compose('G%d@Bus%d',(1:ng)',gb);
delta_deg=rad2deg(r.delta);
if isfield(r,'omega_is_deviation') && r.omega_is_deviation
    omega_plot=1+r.omega;
else
    omega_plot=r.omega;
end

fig=new_ts_figure(['TS angle - ' label],[70 70 980 620]);
ax=axes(fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,delta_deg(:,k),'LineWidth',1.4,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)');
ylabel(ax,'Rotor angle \delta_i (deg)');
title(ax,sprintf('%s: Rotor Angles',label));
legend(ax,labels,'Location','best');
exportgraphics(fig,png,'Resolution',180);

omega_png=suffixed_path(png,'_omega');
omega_fig=new_ts_figure(['TS omega - ' label],[95 85 980 620]);
ax=axes(omega_fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,omega_plot(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'\omega (pu)');
title(ax,sprintf('%s: Generator Rotor Speeds',label));
legend(ax,labels,'Location','best');
exportgraphics(omega_fig,omega_png,'Resolution',180);

pe_png=suffixed_path(png,'_pe');
pe_fig=new_ts_figure(['TS Pe - ' label],[120 100 980 620]);
ax=axes(pe_fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,r.Pe_MW(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)');
title(ax,sprintf('%s: Electrical Power',label));
legend(ax,labels,'Location','best');
exportgraphics(pe_fig,pe_png,'Resolution',180);

if isfield(r,'bus_ids'), bus_ids=r.bus_ids(:); else, bus_ids=r.pf.external_bus_ids(:); end
fi=find(bus_ids==r.fault_bus,1); if isempty(fi), fi=1; end
voltage_png=suffixed_path(png,'_voltage');
voltage_fig=new_ts_figure(['TS voltage - ' label],[145 115 980 620]);
ax=axes(voltage_fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,t,r.Vbus(:,fi),'k','LineWidth',1.8);
plot(ax,t,min(r.Vbus,[],2),'r--','LineWidth',1.3);
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)');
title(ax,sprintf('%s: Fault-Bus and Minimum Voltage',label));
legend(ax,{sprintf('Bus %g',bus_ids(fi)),'Minimum |V|'},'Location','best');
ylim(ax,[0 1.2]);
exportgraphics(voltage_fig,voltage_png,'Resolution',180);

fprintf('Saved TS angle figure  : %s\n',png);
fprintf('Saved TS omega figure  : %s\n',omega_png);
fprintf('Saved TS Pe figure     : %s\n',pe_png);
fprintf('Saved TS voltage figure: %s\n',voltage_png);
end

function path_out = suffixed_path(path_in,suffix)
[folder,name,ext]=fileparts(path_in);
if isempty(ext), ext='.png'; end
path_out=fullfile(folder,[name suffix ext]);
end

function fig = new_ts_figure(name,position)
% Dock interactive figures into one MATLAB window as separate tabs.
if usejava('desktop')
    fig=figure('Name',name,'Color','w','WindowStyle','docked');
else
    fig=figure('Name',name,'Color','w','Position',position);
end
end

function mark_fault(ax,r)
xline(ax,r.t_fault,'--','Fault on','Color',[0.75 0.1 0.1], ...
    'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
xline(ax,r.t_clear,'--','Fault cleared','Color',[0.75 0.1 0.1], ...
    'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
end
