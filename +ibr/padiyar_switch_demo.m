function out = padiyar_switch_demo(opts)
%PADIYAR_SWITCH_DEMO  Padiyar two-area, 1 SG (bus 11) + 3 GFL IBRs (buses 1,2,12)
%   with AGSI++ index-driven GFL<->GFM switching on an SG trip AND reclose.
%   Produces SEPARATE figures (one per quantity: AGSI, angle, frequency, dq
%   currents, voltage, power) and a role/forming log. id/iq/P/Q/f/angle shown,
%   and the forming/slack (reference) device is shown on the angle plot + log.
%
%   out = ibr.padiyar_switch_demo(Name=Value): index_mode, sg_trip_time,
%   sg_reclose_time, T, dt, fig_dir, visible, compare.

arguments
    opts.index_mode (1,1) string = "agsi_pp"
    opts.sg_trip_time (1,1) double = 1.0
    opts.sg_reclose_time (1,1) double = 4.0
    opts.fault_on (1,1) double = inf
    opts.fault_clear (1,1) double = inf
    opts.fault_bus (1,1) double = 3
    opts.fault_Zf (1,1) double = 0.5i
    opts.step_on (1,1) double = inf
    opts.step_bus (1,1) double = 13
    opts.step_factor (1,1) double = 0.10
    opts.T (1,1) double = 8.0
    opts.dt (1,1) double = 2e-3
    opts.fig_dir (1,1) string = ""
    opts.visible (1,1) logical = false
    opts.plot (1,1) logical = true      % false => create NO figure and write NO PNG (out.fig_paths={})
    opts.compare (1,1) logical = false
    opts.T_d_on (1,1) double = 0.5     % dwell GFL->GFM (s): filters spurious marginal AGSI crossings
    opts.T_d_off (1,1) double = 1.0    % dwell GFM->GFL (s)
    opts.sg_droop_R (1,1) double = 0.05  % SG primary-governor droop (pu/pu); Inf=off
    opts.gfm_ilim (1,1) double = 1.2     % converter current limit (x rated); Inf=off
    opts.ilim_mode (1,1) string = "clamp"  % current limiter: "clamp" (hard, default) | "vi" (soft virtual-impedance)
    opts.excitation (1,1) string = ""         % "" => per-system default (ieee14->manual, padiyar->avr)
    opts.system (1,1) string = "padiyar"      % "padiyar" (two-area 1SG+3IBR) | "ieee14" (1SG+4IBR)
end

if strcmpi(opts.system,"ieee14"), bld = @ibr.build_ieee14_switch_system; else, bld = @ibr.build_padiyar_switch_system; end
if strlength(opts.excitation)==0
    if strcmpi(opts.system,"ieee14"), opts.excitation = "manual"; else, opts.excitation = "avr"; end
end
sys = bld(index_mode=opts.index_mode, ...
    T_d_on=opts.T_d_on, T_d_off=opts.T_d_off, sg_droop_R=opts.sg_droop_R, gfm_ilim=opts.gfm_ilim, ...
    ilim_mode=opts.ilim_mode, excitation=opts.excitation);
pfssa = ibr.padiyar_switch_pf_sssa(sys);
print_pf_sssa(pfssa);
out = ibr.padiyar_switch_tds(sys, T=opts.T, dt=opts.dt, ...
    sg_trip_time=opts.sg_trip_time, sg_reclose_time=opts.sg_reclose_time, ...
    fault_on=opts.fault_on, fault_clear=opts.fault_clear, fault_bus=opts.fault_bus, ...
    fault_Zf=opts.fault_Zf, step_on=opts.step_on, step_bus=opts.step_bus, step_factor=opts.step_factor);
if out.diverged
    fprintf('** NOTE: requested T=%.2fs NOT reached - simulation DIVERGED and was truncated at t=%.3fs.\n', opts.T, out.tgrid(end));
    fprintf('   The disturbance is too severe for the current-unlimited / governor-less models to ride through.\n');
    fprintf('   Use a milder fault (LARGER Zf), a smaller load step, or an earlier clear time to reach the full T.\n');
end

fprintf('\n%s SWITCH(%s): conv=%d n_switch=[%s] finalmode=[%s] Vmin=%.3f Vend=%.3f\n', ...
    upper(char(opts.system)), opts.index_mode, out.newton_all_converged, ...
    strjoin(string(out.dev_n_switch(:).'),' '), strjoin(string(out.dev_mode(:).'),' '), ...
    min(out.Vmin), out.Vmin(end));
print_role_log(out);
out.pf_summary = pfssa.pf; out.sssa = pfssa;

if opts.compare
    sysb = bld(index_mode="agsi", ...
        T_d_on=opts.T_d_on, T_d_off=opts.T_d_off, sg_droop_R=opts.sg_droop_R, gfm_ilim=opts.gfm_ilim, ...
        ilim_mode=opts.ilim_mode, excitation=opts.excitation);
    ob = ibr.padiyar_switch_tds(sysb, T=opts.T, dt=opts.dt, ...
        sg_trip_time=opts.sg_trip_time, sg_reclose_time=opts.sg_reclose_time, ...
        fault_on=opts.fault_on, fault_clear=opts.fault_clear, fault_bus=opts.fault_bus, ...
        fault_Zf=opts.fault_Zf, step_on=opts.step_on, step_bus=opts.step_bus, step_factor=opts.step_factor);
    fprintf('COMPARE baseline AGSI: n_switch=[%d %d %d] maxAGSI=%.2f | AGSI++ maxAGSI=%.2f\n', ...
        ob.dev_n_switch, max(ob.index(:)), max(out.index(:)));
    out.baseline = ob;
end

% --- separate figures (one per quantity) -----------------------------------
if ~opts.plot
    % Plotting disabled: create no figure, write no PNG (the caller asked for
    % numbers only). Keeps the contract of the returned fields intact.
    out.fig_paths = {}; out.fig_path = '';
    fprintf('PADIYAR_SWITCH figures SKIPPED (plot=false).\n');
    return;
end
t = out.tgrid; tt = opts.sg_trip_time; tr = opts.sg_reclose_time;
cols = [0.85 0.33 0.10; 0.00 0.45 0.74; 0.20 0.60 0.20; 0.49 0.18 0.56; 0.47 0.67 0.19];
nb3 = out.ibr_buses; vis = opts.visible; nib = numel(nb3);
cols = cols(mod(0:nib-1, size(cols,1))+1, :);
if strlength(opts.fig_dir)>0, od = char(opts.fig_dir); else, od = fullfile('output','diagnostics'); end
if ~exist(od,'dir'), mkdir(od); end
fps = {};
if strcmpi(opts.system,"ieee14"), sysname=sprintf('IEEE 14-bus  1-SG + %d-IBR',nib);
else, sysname=sprintf('Padiyar two-area  1-SG + %d-IBR',nib); end
% Figure lettering is matched to the report body text: same typeface (Times New
% Roman, i.e. the reports' serif) at the same 12 pt size, and the figure is sized
% in INCHES so the exported PNG is included at 1:1 scale (no rescaling of the
% lettering). REPORT_FIGURE_STYLE_CONTRACT.
mainfig = figure('Color','w','Units','inches','Position',[1 1 6.4 3.9], ...
    'NumberTitle','off', ...
    'Name',sprintf('%s : GFL<->GFM AGSI++ index switching', sysname), ...
    'Visible', matlab.lang.OnOffSwitchState(vis), ...
    'DefaultAxesFontName','Times New Roman','DefaultAxesFontSize',12, ...
    'DefaultTextFontName','Times New Roman','DefaultTextFontSize',12, ...
    'DefaultLegendFontName','Times New Roman','DefaultLegendFontSize',12);
tabs = uitabgroup(mainfig);

ax=newtab(tabs,'AGSI');
for j=1:nib, plot(ax,t,out.index(:,j),'-','Color',cols(j,:),'LineWidth',1.4,'DisplayName',sprintf('AGSI IBR%d(bus%d)',j,nb3(j))); end
yline(ax,out.agsi_up,'k-','LineWidth',1.1,'Label','\Gamma_{on}','HandleVisibility','off');
yline(ax,out.agsi_down,'k--','LineWidth',1.0,'Label','\Gamma_{off}','HandleVisibility','off');
yl=ylim(ax); ylim(ax,[0 max(yl(2),1.3)]);   % floor at 0, never clip the peaks
fps{end+1}=finfig(ax,'AGSI switching index per IBR vs reference lines','AGSI',od,'agsi',tt,tr,out,cols);

% A discrete mode timeline is deliberately separate from the AGSI plot.  The
% index is a continuous diagnostic, while mode is the supervisor's binary
% state (0=GFL, 1=GFM).  Keeping four panels prevents coincident switches from
% hiding one another and makes per-device, non-coordinated decisions visible.
fps{end+1}=mode_timeline_figure(t,out,nb3,od,tt,tr,cols,vis);

ax=newtab(tabs,'angle');
for j=1:nib, plot(ax,t,wrap(out.ang_ibr(:,j)-out.ref_angle)*180/pi,'-','Color',cols(j,:),'LineWidth',1.4,'DisplayName',sprintf('\\delta IBR%d - \\delta_{ref}',j)); end
plot(ax,t,wrap(out.sg_delta-out.ref_angle)*180/pi,'k-','LineWidth',1.4,'DisplayName','\delta SG - \delta_{ref}');
fps{end+1}=finfig(ax,'Internal angle relative to the forming/slack reference (SG when online, else IBR)','angle (deg)',od,'angle',tt,tr,out,cols);

ax=newtab(tabs,'freq');
for j=1:nib, plot(ax,t,out.f_ibr(:,j),'-','Color',cols(j,:),'LineWidth',1.2,'DisplayName',sprintf('f IBR%d',j)); end
plot(ax,t,out.f_sg,'k-','LineWidth',1.2,'DisplayName','f SG');
fps{end+1}=finfig(ax,'Frequency (PLL / VSG rotor / SG)','f (Hz)',od,'freq',tt,tr,out,cols);

ax=newtab(tabs,'i_d');
for j=1:nib, plot(ax,t,out.id_ibr(:,j),'-','Color',cols(j,:),'LineWidth',1.4,'DisplayName',sprintf('i_d IBR%d(bus%d)',j,nb3(j))); end
plot(ax,t,out.sg_id,'k-','LineWidth',1.3,'DisplayName',sprintf('i_d SG(bus%d)',out.sg_bus));
fps{end+1}=finfig(ax,'d-axis current (IBRs + SG), 100-MVA system base','i_d (pu, system base)',od,'id',tt,tr,out,cols);

ax=newtab(tabs,'i_q');
for j=1:nib, plot(ax,t,out.iq_ibr(:,j),'-','Color',cols(j,:),'LineWidth',1.4,'DisplayName',sprintf('i_q IBR%d(bus%d)',j,nb3(j))); end
plot(ax,t,out.sg_iq,'k-','LineWidth',1.3,'DisplayName',sprintf('i_q SG(bus%d)',out.sg_bus));
fps{end+1}=finfig(ax,'q-axis current (IBRs + SG), 100-MVA system base','i_q (pu, system base)',od,'iq',tt,tr,out,cols);

ax=newtab(tabs,'|V|');
for j=1:nib, plot(ax,t,out.Vbus(:,j),'-','Color',cols(j,:),'LineWidth',1.2,'DisplayName',sprintf('|V| bus%d',nb3(j))); end
plot(ax,t,out.Vmin,'--','Color',[.5 .5 .5],'LineWidth',1.0,'DisplayName','min|V| (network)');
fps{end+1}=finfig(ax,'Bus voltage magnitudes','|V| (pu)',od,'voltage',tt,tr,out,cols);

ax=newtab(tabs,'P');
for j=1:nib, plot(ax,t,out.P_ibr(:,j),'-','Color',cols(j,:),'LineWidth',1.3,'DisplayName',sprintf('P IBR%d(bus%d)',j,nb3(j))); end
plot(ax,t,out.sg_P,'k-','LineWidth',1.3,'DisplayName',sprintf('P SG(bus%d)',out.sg_bus));
fps{end+1}=finfig(ax,'Active power (IBRs + SG)','P (pu, 100-MVA system base)',od,'p',tt,tr,out,cols);

ax=newtab(tabs,'Q');
for j=1:nib, plot(ax,t,out.Q_ibr(:,j),'-','Color',cols(j,:),'LineWidth',1.3,'DisplayName',sprintf('Q IBR%d(bus%d)',j,nb3(j))); end
plot(ax,t,out.sg_Q,'k-','LineWidth',1.3,'DisplayName',sprintf('Q SG(bus%d)',out.sg_bus));
fps{end+1}=finfig(ax,'Reactive power (IBRs + SG)','Q (pu, 100-MVA system base)',od,'q',tt,tr,out,cols);

if ~vis, close(mainfig); end

out.fig_paths = fps; out.fig_path = fps{1};
fprintf('PADIYAR_SWITCH figures saved (%d) in %s:\n', numel(fps), od);
for i=1:numel(fps), fprintf('   %s\n', fps{i}); end
end

% =========================================================================
function print_role_log(out)
fprintf('---- Reference / forming (slack) timeline ----\n');
fprintf('[0, %.3f) s : SG@bus%d = SLACK (angle reference); all %d IBRs = GFL (following)\n', ...
    out.sg_trip_time, out.sg_bus, numel(out.ibr_buses));
ev = out.switch_events;
if ~isempty(ev)
    up = ev(ev(:,1)<=out.sg_trip_time+1e-9 & ev(:,4)==1, :);
    if ~isempty(up)
        s = strjoin(arrayfun(@(r) sprintf('IBR%d(bus%d)',up(r,2),out.ibr_buses(up(r,2))),1:size(up,1),'uni',0),', ');
        fprintf('t=%.3f s : SG TRIPPED -> %s cross AGSI up-line -> GFM (self-forming island, droop-shared)\n', out.sg_trip_time, s);
    end
end
rc = out.ref_code(find(out.tgrid> out.sg_trip_time,1));
if isfinite(out.sg_reclose_time) && out.sg_reclose_time < out.tgrid(end)
    if rc>=1
        fprintf('[%.3f, %.3f) s : ISLAND -- GFM IBRs form the grid; nominal angle reference = IBR%d(bus%d)\n', ...
            out.sg_trip_time, out.sg_reclose_time, rc, out.ibr_buses(rc));
    end
    fprintf('t=%.3f s : SG RECLOSED -> synchronized handback; SG re-takes slack, IBRs revert to scheduled GFL dispatch\n', out.sg_reclose_time);
    gfl_l = find(out.dev_mode=="gfl"); gfm_l = find(out.dev_mode=="GFM");
    sgfl = strjoin(arrayfun(@(j) sprintf('IBR%d(bus%d)',j,out.ibr_buses(j)), gfl_l(:).','uni',0),', ');
    sgfm = strjoin(arrayfun(@(j) sprintf('IBR%d(bus%d)',j,out.ibr_buses(j)), gfm_l(:).','uni',0),', ');
    if isempty(sgfm), sgfm='(none)'; end
    fprintf('[%.3f, %.3f] s : SG@bus%d = SLACK again; GFL: %s ; still GFM (index kept forming): %s\n', ...
        out.sg_reclose_time, out.tgrid(end), out.sg_bus, sgfl, sgfm);
elseif rc>=1
    fprintf('[%.3f, %.3f] s : ISLAND -- GFM IBRs form the grid; nominal reference = IBR%d(bus%d)\n', ...
        out.sg_trip_time, out.tgrid(end), rc, out.ibr_buses(rc));
end
end

function print_pf_sssa(r)
fprintf('==== Power flow (pre-disturbance equilibrium, system 100 MVA base) ====\n');
fprintf('   bus |   Pgen    Qgen |    |V|    ang(deg)\n');
for i=1:size(r.pf,1)
    tag = ''; if r.pf(i,2)==0 && r.pf(i,3)==0, tag=' (load bus)'; end
    fprintf('   %3d | %7.3f %7.3f |  %.4f  %7.2f%s\n', r.pf(i,1), r.pf(i,2), r.pf(i,3), r.pf(i,4), r.pf(i,5), tag);
end
fprintf('   (IBRs at buses 1,2,12 and the SG at bus 11 all inject P; buses 3,13 are loads)\n');
fprintf('==== Small-signal (SSSA): composite modes at the SG-online equilibrium ====\n');
fprintf('   states=%d   unstable eig(Re>0)=%d   least-damped osc: f=%.3f Hz, zeta=%+.4f\n', ...
    size(r.A,1), r.n_unstable, r.min_zeta_freq, r.min_zeta);
M = r.modes;                                  % [sigma freq zeta]
if ~isempty(M)
    [~,o]=sort(M(:,3)); M=M(o,:);             % ascending damping
    fprintf('   lowest-damping oscillatory modes:\n');
    for i=1:min(4,size(M,1))
        fprintf('      f=%6.3f Hz   zeta=%+.4f   sigma=%+.4f 1/s\n', M(i,2), M(i,3), M(i,1));
    end
end
if r.n_unstable>0
    fprintf('   NOTE: %d unstable eigenvalue(s) -> this operating point is small-signal UNSTABLE.\n', r.n_unstable);
elseif r.min_zeta < 0.05
    fprintf('   NOTE: a very lightly-damped mode (zeta<0.05) -> source of the slow post-reclose oscillation.\n');
end
end

function ax=newtab(tabs,name)
tb = uitab(tabs,'Title',name);
ax = axes(tb); hold(ax,'on');
set(ax,'FontName','Times New Roman','FontSize',12);   % match the report body text
end

function fp = finfig(ax,ttl,ylab,od,key,tt,tr,out,cols)
grid(ax,'on'); mark_ev(ax,tt,tr,out,cols);
title(ax,ttl,'Interpreter','tex','FontName','Times New Roman','FontSize',12,'FontWeight','bold');
ylabel(ax,ylab,'FontName','Times New Roman','FontSize',12);
xlabel(ax,'time (s)','FontName','Times New Roman','FontSize',12);
lg = legend(ax,'Location','best'); set(lg,'FontName','Times New Roman','FontSize',11);
fp = fullfile(od, sprintf('padiyar_switch_%s.png', key));
exportgraphics(ax, fp, 'Resolution', 200);
end

function fp = mode_timeline_figure(t,out,buses,od,tt,tr,cols,vis)
%MODE_TIMELINE_FIGURE  Four explicit binary mode traces (0=GFL, 1=GFM).
% Dense multi-panel report figure: Times New Roman 11 pt at a physical width
% of 5.90 in, included by the reports at exactly 5.90 in (1:1 scale).
nib = numel(buses);
fig = figure('Color','w','Units','inches','Position',[1 1 5.90 4.70], ...
    'NumberTitle','off','Name','Per-IBR binary mode timeline', ...
    'Visible',matlab.lang.OnOffSwitchState(vis), ...
    'DefaultAxesFontName','Times New Roman','DefaultAxesFontSize',11, ...
    'DefaultTextFontName','Times New Roman','DefaultTextFontSize',11);
tl = tiledlayout(fig,nib,1,'TileSpacing','compact','Padding','compact');
title(tl,'Per-IBR supervisor mode: 0 = GFL, 1 = GFM', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');
ev = out.switch_events;
for j=1:nib
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    stairs(ax,t,out.mode(:,j),'-','Color',cols(j,:),'LineWidth',1.5);
    ylim(ax,[-0.12 1.12]); yticks(ax,[0 1]); yticklabels(ax,{'GFL (0)','GFM (1)'});
    ylabel(ax,sprintf('IBR%d\nbus %d',j,buses(j)), ...
        'FontName','Times New Roman','FontSize',11);
    xline(ax,tt,':','Color',[.35 .35 .35],'LineWidth',1.0, ...
        'HandleVisibility','off');
    if isfinite(tr) && tr<t(end)
        xline(ax,tr,'--','Color',[.20 .20 .20],'LineWidth',1.0, ...
            'HandleVisibility','off');
    end
    if isfield(out,'fault_on') && isfinite(out.fault_on) && out.fault_on<t(end)
        xline(ax,out.fault_on,':','Color',[.75 .10 .10],'LineWidth',0.9, ...
            'HandleVisibility','off');
        if isfinite(out.fault_clear) && out.fault_clear<t(end)
            xline(ax,out.fault_clear,':','Color',[.75 .10 .10],'LineWidth',0.9, ...
                'HandleVisibility','off');
        end
    end
    jev = ev(ev(:,2)==j,:);
    if ~isempty(jev)
        scatter(ax,jev(:,1),jev(:,4),24,cols(j,:),'filled', ...
            'MarkerEdgeColor','k','LineWidth',0.5);
    end
    if j<nib
        set(ax,'XTickLabel',[]);
    else
        xlabel(ax,'time (s)','FontName','Times New Roman','FontSize',11);
    end
end
fp = fullfile(od,'padiyar_switch_mode.png');
exportgraphics(fig,fp,'Resolution',200);
if ~vis, close(fig); end
end

function a = wrap(x)
a = atan2(sin(x), cos(x));
end

function mark_ev(ax,tt,tr,out,cols)
xline(ax,tt,':','Color',[.4 .4 .4],'LineWidth',1.1,'Label','SG trip','HandleVisibility','off');
if isfinite(tr) && tr<out.tgrid(end)
    xline(ax,tr,':','Color',[.4 .4 .4],'LineWidth',1.1,'Label','SG reclose','HandleVisibility','off');
end
if isfield(out,'fault_on') && isfinite(out.fault_on) && out.fault_on<out.tgrid(end)
    xline(ax,out.fault_on,':','Color',[.80 .10 .10],'LineWidth',1.0,'Label','fault', ...
        'LabelVerticalAlignment','top','HandleVisibility','off');
    if isfinite(out.fault_clear) && out.fault_clear<out.tgrid(end)
        % The clear line sits within ~0.15 s of the fault line, so its label is
        % anchored at the OPPOSITE end of the axis to avoid overprinting.
        xline(ax,out.fault_clear,':','Color',[.80 .10 .10],'LineWidth',1.0,'Label','clear', ...
            'LabelVerticalAlignment','bottom','HandleVisibility','off');
    end
end
if isfield(out,'step_on') && isfinite(out.step_on) && out.step_on<out.tgrid(end)
    xline(ax,out.step_on,':','Color',[.60 .10 .60],'LineWidth',1.0,'Label','load step','HandleVisibility','off');
end
ev=out.switch_events; if isempty(ev), return; end
for r=1:size(ev,1)
    j=ev(r,2); if size(ev,2)>=4 && ev(r,4)==1, ls='-'; else, ls='-.'; end
    xline(ax,ev(r,1),ls,'Color',cols(j,:),'LineWidth',1.0,'Alpha',0.35,'HandleVisibility','off');
end
end
