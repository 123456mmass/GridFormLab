function res = run_case14_ts_demo()
%RUN_CASE14_TS_DEMO Run and plot TS for imported MATPOWER6 case14.

pf_init_paths;
opt = struct('t_end',15.0,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal','corrector_iter',1,'verbose',true);
res = stability.case14_ts_classical(opt);

outdir = fullfile(pwd,'docs','source','figures','case14_ts');
if ~exist(outdir,'dir'), mkdir(outdir); end

labels = compose('G%d@Bus%d', (1:numel(res.gen_buses)).', res.gen_buses(:));
colors = lines(numel(res.gen_buses));
f = figure('Name','MATPOWER6 case14 TS','Color','w','Position',[80 80 1300 850]);
tl = tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');

fault_on=res.t_fault; fault_off=res.t_clear;
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
% PSAT/PGAz variables such as delta_Syn_1 are machine rotor angles.  To make
% the plot comparable, show each absolute rotor-angle deviation from its own
% pre-fault initial value, not delta_i-delta_1.
delta_abs_dev = rad2deg(res.delta - res.delta(1,:));
for k=1:numel(res.gen_buses)
    plot(ax,res.t,delta_abs_dev(:,k),'LineWidth',1.5,'Color',colors(k,:));
end
mark_fault(ax,fault_on,fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'\Delta\delta_i = \delta_i-\delta_i(0) (deg)');
title(ax,'Absolute rotor-angle deviations (PSAT delta\_Syn style)');
legend(ax, labels, 'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
omega_dev = res.omega - 1;
for k=1:numel(res.gen_buses), plot(ax,res.t,omega_dev(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,fault_on,fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'\Delta\omega (pu)'); title(ax,'Generator speed deviations');
legend(ax, labels, 'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:numel(res.gen_buses), plot(ax,res.t,res.Pe_MW(:,k),'LineWidth',1.3,'Color',colors(k,:)); end
mark_fault(ax,fault_on,fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)'); title(ax,'Electrical power (classical air-gap)');
legend(ax, labels, 'Location','best');

ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,res.t,res.Vbus(:,res.fault_bus),'k','LineWidth',2.0);
plot(ax,res.t,min(res.Vbus,[],2),'r--','LineWidth',1.5);
mark_fault(ax,fault_on,fault_off);
xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)'); title(ax,'Fault-bus and minimum bus voltage'); ylim(ax,[0 1.2]);
legend(ax,{sprintf('Bus %d',res.fault_bus),'min |V|'},'Location','best');

sgtitle(tl,sprintf('MATPOWER6 case14 TS: bus %d fault, Z_f = %.3g%+.3gj pu, %s, dt=%.4f s', ...
    res.fault_bus, real(res.Zf), imag(res.Zf), res.method, res.dt),'FontWeight','bold');
exportgraphics(f, fullfile(outdir,'case14_ts_fault_bus4.png'), 'Resolution', 200);
fprintf('Saved TS figure: %s\n', fullfile(outdir,'case14_ts_fault_bus4.png'));
end

function mark_fault(ax,t1,t2)
xline(ax,t1,'--','Fault on','Color',[0.75 0.1 0.1],'LineWidth',1.1,'LabelOrientation','horizontal');
xline(ax,t2,'--','Fault cleared','Color',[0.75 0.1 0.1],'LineWidth',1.1,'LabelOrientation','horizontal');
end
