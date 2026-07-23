function generate_two_ibr_switch_report_figures()
%GENERATE_TWO_IBR_SWITCH_REPORT_FIGURES  Figures for the two-IBR AGSI GFL<->GFM
%   mode-switch report (docs/source/figures/two_ibr_switch/).
%
%   Produces:
%     switch_overview.png  - the default 4-panel study figure (AGSI vs ref
%                            lines, frequency, PCC voltage, P/Q).
%     agsi_annotated.png   - the AGSI switching equation with the two reference
%                            lines and annotated phases (how the index drives
%                            the switch).
%
%   Run: pf_init_paths; addpath('scripts/reporting');
%        generate_two_ibr_switch_report_figures
pf_init_paths();
outdir = fullfile('docs','source','figures','two_ibr_switch');
if ~exist(outdir,'dir'); mkdir(outdir); end

% --- Fig 1: full 4-panel overview (baseline AGSI + dwell, as described in the
%     report body; explicit index_mode so it is unaffected by the demo default) -
out = ibr.two_ibr_switch_demo(save_fig=true, visible=false, ...
    index_mode="agsi", T_d_on=0.10, T_d_off=1.00, ...
    fig_path=fullfile(outdir,'switch_overview.png'));

% --- Fig 2: annotated AGSI switching equation -----------------------------
plot_agsi_annotated(out, fullfile(outdir,'agsi_annotated.png'));

% --- Fig 3: AGSI vs AGSI++ comparison (both no dwell) ----------------------
plot_agsipp_compare(fullfile(outdir,'agsi_pp_compare.png'));

fprintf('TWO_IBR_SWITCH_FIGURES_DONE: %s\n', outdir);
end

% =========================================================================
function plot_agsipp_compare(fpath)
% Baseline AGSI vs AGSI++ (both no dwell) on the same 2-IBR scenario.
params=struct(); Vinf=1.0; Zline=0.30i; Pref=0.2; Qref=0.0;
Vpcc = ibr.solve_pcc_infbus_equilibrium(Vinf,Zline,[Pref+1i*Qref,Pref+1i*Qref]);
run1 = @(mode) run_two(mode,Vinf,Zline,Pref,Qref,Vpcc,params);
ob = run1("agsi");     % baseline, no dwell
op = run1("agsi_pp");  % AGSI++,  no dwell

fig = figure('Color','w','Position',[80 80 1000 440],'Visible','off');
tl = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');
title(tl,'AGSI vs AGSI++ (no dwell): filtered RoCoF removes the chattering','Interpreter','tex');
ax1=nexttile(tl); hold(ax1,'on'); grid(ax1,'on');
plot(ax1,ob.tgrid,ob.index1,'-','Color',[0.85 0.33 0.10],'LineWidth',1.4);
yline(ax1,0.65,'k-','LineWidth',1.1,'Label','\Gamma_{on}');
yline(ax1,0.35,'k--','LineWidth',1.0,'Label','\Gamma_{off}');
ylim(ax1,[0 2]); title(ax1,sprintf('Baseline AGSI (%d switches = chatter)',ob.dev1_n_switch));
xlabel(ax1,'time (s)'); ylabel(ax1,'AGSI (clipped @2)');
ax2=nexttile(tl); hold(ax2,'on'); grid(ax2,'on');
plot(ax2,op.tgrid,op.index1,'-','Color',[0.00 0.45 0.74],'LineWidth',1.4);
yline(ax2,0.65,'k-','LineWidth',1.1,'Label','\Gamma_{on}');
yline(ax2,0.35,'k--','LineWidth',1.0,'Label','\Gamma_{off}');
ylim(ax2,[0 2]); title(ax2,sprintf('AGSI++ (%d switches = clean)',op.dev1_n_switch));
xlabel(ax2,'time (s)'); ylabel(ax2,'AGSI++');
exportgraphics(fig,fpath,'Resolution',140); close(fig);
end

function o = run_two(mode,Vinf,Zline,Pref,Qref,Vpcc,params)
d1=ibr.SwitchableIbr6("IBR1",1,1,1,Vinf,params,Pref,Qref,index_mode=mode,T_d_on=0,T_d_off=0);
d2=ibr.SwitchableIbr6("IBR2",1,1,1,Vinf,params,Pref,Qref,index_mode=mode,T_d_on=0,T_d_off=0);
x1=d1.gfl_dev.equilibrium_initialize(Vpcc,Pref,Qref,struct());
x2=d2.gfl_dev.equilibrium_initialize(Vpcc,Pref,Qref,struct());
y=[real(Vpcc);imag(Vpcc)];
o=ibr.two_ibr_infbus_tds(d1,d2,x1,x2,y,Vinf,Zline,T=8,dt=1e-3, ...
   event_time=1.5,recover_time=4.0,step_ramp=0.40,Zline_factor=4.0, ...
   step_dphase_deg=0,step_dV=0,newton_max_iter=80);
end

% =========================================================================
function plot_agsi_annotated(out, fpath)
t = out.tgrid;
te = out.event_time; tr = out.recover_time;
% switch times
tup = NaN; tdn = NaN;
ev = out.switch_events;
if ~isempty(ev)
    iu = find(ev(:,2)==1 & ev(:,4)==1,1); if ~isempty(iu), tup = ev(iu,1); end
    id = find(ev(:,2)==1 & ev(:,4)==0,1); if ~isempty(id), tdn = ev(id,1); end
end

fig = figure('Color','w','Position',[80 80 1000 430],'Visible','off');
ax = axes(fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
% hysteresis band shading
xl = [t(1) t(end)];
patch(ax, [xl(1) xl(2) xl(2) xl(1)], [out.agsi_down out.agsi_down out.agsi_up out.agsi_up], ...
    [0.95 0.95 0.80], 'EdgeColor','none', 'FaceAlpha',0.6, 'HandleVisibility','off');
% AGSI
plot(ax, t, out.index1, '-', 'Color',[0.85 0.33 0.10], 'LineWidth',1.8, 'DisplayName','AGSI');
yline(ax, out.agsi_up,  'k-',  'LineWidth',1.4, 'Label','\Gamma_{on}=0.65','LabelHorizontalAlignment','left','HandleVisibility','off');
yline(ax, out.agsi_down,'k--', 'LineWidth',1.2, 'Label','\Gamma_{off}=0.35','LabelHorizontalAlignment','left','HandleVisibility','off');
% event / recovery / switch markers
xline(ax, te, ':', 'Color',[0.4 0.4 0.4], 'LineWidth',1.1, 'Label','grid weakens','LabelOrientation','horizontal','HandleVisibility','off');
xline(ax, tr, ':', 'Color',[0.4 0.4 0.4], 'LineWidth',1.1, 'Label','grid recovers','LabelOrientation','horizontal','HandleVisibility','off');
if isfinite(tup)
    xline(ax, tup, '-', 'Color',[0.80 0.10 0.10], 'LineWidth',1.8, ...
        'Label',sprintf('GFL\\rightarrowGFM (%.2fs)',tup),'LabelVerticalAlignment','bottom','HandleVisibility','off');
end
if isfinite(tdn)
    xline(ax, tdn, '-', 'Color',[0.10 0.60 0.20], 'LineWidth',1.8, ...
        'Label',sprintf('GFM\\rightarrowGFL (%.2fs)',tdn),'LabelVerticalAlignment','bottom','HandleVisibility','off');
end
ylim(ax,[0 1.0]);
xlabel(ax,'time (s)'); ylabel(ax,'AGSI (dimensionless)');
title(ax,'AGSI switching equation: index vs reference lines (\Gamma_{on}, \Gamma_{off})');
legend(ax,'Location','northeast');
% phase captions
ytxt = 0.92;
text(ax, (t(1)+te)/2, 0.08, 'normal GFL', 'HorizontalAlignment','center','Color',[0.2 0.2 0.2]);
if isfinite(tup)
    text(ax, (te+tup)/2, ytxt, 'weak grid: AGSI rises', 'HorizontalAlignment','center','Color',[0.85 0.33 0.10]);
end
if isfinite(tup) && isfinite(tdn)
    text(ax, (tup+tr)/2, out.agsi_up-0.12, 'GFM holds (in hysteresis band)', 'HorizontalAlignment','center','Color',[0 0.3 0.6]);
    text(ax, (tdn+t(end))/2, 0.08, 'back to GFL', 'HorizontalAlignment','center','Color',[0.10 0.55 0.20]);
end
exportgraphics(fig, fpath, 'Resolution', 140);
close(fig);
end
