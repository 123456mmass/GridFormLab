function [fig,png] = plot_ts_result(r,label,root,case_id,outpath)
%PLOT_TS_RESULT Canonical 2x2 transient-stability plot (single configuration).
%   [FIG,PNG] = PLOT_TS_RESULT(R,LABEL,ROOT,CASE_ID) plots the TS result R in
%   the established 2x2 format (rotor angle, speed, electrical power,
%   fault-bus voltage) and saves to output/figures/ts/<timestamp>_<case>.png.
%   [FIG,PNG] = PLOT_TS_RESULT(R,LABEL,ROOT,CASE_ID,OUTPATH) saves to the
%   explicit OUTPATH instead (used by report generators).
%
%   Convention: rotor angle is delta_i(t)-delta_i(0) (PSAT delta_Syn style).
%   COI-relative/pairwise quantities remain verification metrics in
%   print_ts_checks; they are intentionally not used for this plot.
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
delta_deg=rad2deg(r.delta-r.delta(1,:));
if isfield(r,'omega_is_deviation') && r.omega_is_deviation
    wd=r.omega;
else
    wd=r.omega-1;
end

fig=figure('Name',['TS - ' label],'Color','w','Position',[70 70 1300 820]);
tl=tiledlayout(fig,2,2,'Padding','compact','TileSpacing','compact');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,delta_deg(:,k),'LineWidth',1.4,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)');
ylabel(ax,'\Delta\delta_i = \delta_i-\delta_i(0) (deg)');
title(ax,'Absolute rotor-angle deviations (PSAT delta\_Syn style)');
legend(ax,labels,'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,wd(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'Delta omega (pu)');
title(ax,'Generator speed deviations'); legend(ax,labels,'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,r.Pe_MW(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)');
title(ax,'Electrical power (classical air-gap)');
legend(ax,labels,'Location','best');

if isfield(r,'bus_ids'), bus_ids=r.bus_ids(:); else, bus_ids=r.pf.external_bus_ids(:); end
fi=find(bus_ids==r.fault_bus,1); if isempty(fi), fi=1; end
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,t,r.Vbus(:,fi),'k','LineWidth',1.8);
plot(ax,t,min(r.Vbus,[],2),'r--','LineWidth',1.3);
mark_fault(ax,r); xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)');
title(ax,'Fault-bus and minimum voltage');
legend(ax,{sprintf('Bus %g',bus_ids(fi)),'Minimum |V|'},'Location','best');
ylim(ax,[0 1.2]);

sgtitle(tl,sprintf(['%s: bus %g fault, Z_f = %.3g%+.3gj pu, ' ...
    '%s, dt=%.4f s'],label,r.fault_bus,real(r.Zf),imag(r.Zf), ...
    r.method,r.dt),'FontWeight','bold');
exportgraphics(fig,png,'Resolution',180);
fprintf('Saved TS figure: %s\n',png);
end

function mark_fault(ax,r)
xline(ax,r.t_fault,'--','Fault on','Color',[0.75 0.1 0.1], ...
    'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
xline(ax,r.t_clear,'--','Fault cleared','Color',[0.75 0.1 0.1], ...
    'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
end
