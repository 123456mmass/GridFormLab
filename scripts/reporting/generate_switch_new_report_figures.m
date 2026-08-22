function out = generate_switch_new_report_figures(opts)
%GENERATE_SWITCH_NEW_REPORT_FIGURES  Figures for report_ieee14_switch_en_new.
%   Renders the presentation figures of the new standalone English report
%   directly from an ACCEPTED production trajectory. No signal is smoothed,
%   filtered, decimated, offset, re-sampled or augmented with synthetic
%   noise: every plotted sample is a raw accepted value taken from the
%   stored result struct.
%
%   Default source is the preserved 200-s accepted trajectory
%   `output/diagnostics/engine_release_200s_preserved.mat`, selected because
%   the user requested the established 200-s curves for this report while the
%   250-s horizon run is still in progress. Pass `result_file` to point at a
%   different accepted result.
%
%   Figures produced in docs/source/figures/switch_ieee14_new/
%     mode_switch_PQ.png        GFM-active bars + per-IBR P and Q
%     state_switch_dimension.png active-state dimension and accepted residual
%
%   Presentation contract: Times New Roman, 12 pt (11 pt for the dense
%   multi-panel tile), figure sized in inches and included at 1:1 scale.

arguments
    opts.result_file (1,1) string = fullfile('output','diagnostics', ...
        'engine_release_200s_preserved.mat')
    opts.t_max (1,1) double = 200
end

pf_init_paths();

outdir = fullfile('docs','source','figures','switch_ieee14_new');
if ~exist(outdir,'dir'), mkdir(outdir); end

src = char(opts.result_file);
if ~exist(src,'file')
    error('generate_switch_new_report_figures:missingResult', ...
        'Accepted trajectory %s does not exist.', src);
end
S = load(src,'r'); r = S.r;

if ~isfield(r,'converged') || ~r.converged
    error('generate_switch_new_report_figures:unacceptedTrajectory', ...
        'Refusing to plot a trajectory that is not an accepted converged run.');
end

t = r.t(:);
nt = numel(t);

% ---- device identification ---------------------------------------------
devs   = r.equilibrium.devices;
ndev   = numel(devs);
didx   = 2:ndev;                       % device 1 is the SG
nibr   = numel(didx);
if nibr ~= 4
    error('generate_switch_new_report_figures:deviceCount', ...
        'Expected four IBR devices, found %d.', nibr);
end
ibr_buses = r.device_bus_ids(didx);

modes = string(r.device_modes_history(didx,:)).';   % nt x nibr
isgfm = strcmpi(modes,"gfm");

% ---- reference owner per accepted sample --------------------------------
% Reference ownership is a SEPARATE contract from mode: several IBRs can be
% GFM at once, but only ONE device owns the island angle reference at a time.
% Read it straight from the accepted hybrid-state history exactly as the
% production report adapter does: ref_code = 0 for the SG, j=1..4 for IBRj,
% and -1 when no owner is published. No inference from "first GFM".
sgonline_all = logical(r.device_online_history(1,:)).';
ref_code = -ones(nt,1);
for k = 1:nt
    hs = struct();
    if isfield(r,'event_context_history') && numel(r.event_context_history)>=k && ...
            isstruct(r.event_context_history{k}) && ...
            isfield(r.event_context_history{k},'hybrid_state')
        hs = r.event_context_history{k}.hybrid_state;
    end
    if isfield(hs,'reference_owner_indices') && ~isempty(hs.reference_owner_indices)
        owner = hs.reference_owner_indices(1);
        if owner == 1
            ref_code(k) = 0;                     % SG (global device index 1)
        elseif any(owner == didx)
            ref_code(k) = find(didx == owner,1); % IBR1..IBR4
        end
    elseif sgonline_all(k)
        ref_code(k) = 0;                         % SG online, SG owns reference
    end
end

P = r.device_P_pu(didx,:).';           % nt x nibr
Q = r.device_Q_pu(didx,:).';

% ---- presentation window ------------------------------------------------
% Window selection is a display range only. No sample inside the window is
% altered, and no sample is decimated: every accepted point is drawn.
tmax = min(opts.t_max, t(end));
w    = t <= tmax + 1e-9;

% ---- fixed per-IBR style (frozen, matches the report legend) ------------
col = { [0.00 0.24 0.75], ...   % IBR1 blue
        [0.85 0.11 0.11], ...   % IBR2 red (dashed)
        [0.85 0.11 0.11], ...   % IBR3 red (solid)
        [0.00 0.00 0.00] };     % IBR4 black
lst = {'-','--','-','-'};
lwd = [1.1 1.1 1.1 1.1];
lbl = arrayfun(@(b) sprintf('IBR_%d (bus %d)', find(ibr_buses==b,1), b), ...
        ibr_buses, 'UniformOutput', false);
for j = 1:nibr
    lbl{j} = sprintf('IBR_%d (bus %d)', j, ibr_buses(j));
end

FS   = 12;                              % report body size
FNAME= 'Times New Roman';

%% ======================= FIGURE 1: ref + modes + P + Q ==================
% A4 with 1-in margins gives a 6.268-in text width; the figure is authored at
% 6.20 in and included at 1:1 so the in-figure lettering keeps its 12-pt size.
figW = 6.20; figH = 8.40;
f1 = figure('Units','inches','Position',[1 1 figW figH], ...
            'Color','w','PaperUnits','inches', ...
            'PaperSize',[figW figH],'PaperPosition',[0 0 figW figH]);

x0 = 0.90/figW;  aw = 5.05/figW;

% ---- (top of page) GFL/GFM mode, all four IBRs overlaid on ONE axis -----
% Step traces (GFL=0, GFM=1) drawn with the SAME fixed per-IBR colour/style
% as panels (a),(b). Exactly overlapping 0/1 levels, NO display offset: where
% several IBRs share a level their traces coincide, which is the honest
% picture of a synchronous mode switch.
axM = axes('Parent',f1,'Units','normalized', ...
    'Position',[x0, 7.00/figH, aw, 0.80/figH]); hold(axM,'on');
for j = 1:nibr
    stairs(axM,t(w),double(isgfm(w,j)),lst{j},'Color',col{j},'LineWidth',lwd(j));
end
set(axM,'XLim',[0 tmax],'YLim',[-0.25 1.25], ...
    'YTick',[0 1],'YTickLabel',{'GFL','GFM'}, ...
    'FontName',FNAME,'FontSize',FS,'Box','on','XTickLabel',[], ...
    'TickDir','out','Layer','top','GridAlpha',0.15); grid(axM,'on');
title(axM,'Grid-forming / grid-following mode', ...
    'FontName',FNAME,'FontSize',FS,'FontWeight','normal');

% ---- reference owner ----------------------------------------------------
% Shows WHO holds the island angle reference at each instant. This is the
% answer to "which device is the reference": it is NOT read from the mode
% traces above (all four can be GFM at once) but from the accepted
% reference-owner history. SG owns it while online (0-20 s and after reclose);
% a single IBR owns it while the SG breaker is open.
axR = axes('Parent',f1,'Units','normalized', ...
    'Position',[x0, 5.65/figH, aw, 0.85/figH]); hold(axR,'on');
refcol = [0.35 0.15 0.55];
stairs(axR,t(w),ref_code(w),'-','Color',refcol,'LineWidth',1.6);
% Label each contiguous ownership segment with the owner name.
rc = ref_code(w); tt = t(w);
d  = [true; diff(rc)~=0];
seg_start = find(d);
seg_end   = [seg_start(2:end)-1; numel(rc)];
for s = 1:numel(seg_start)
    val = rc(seg_start(s));
    if val < 0, continue; end
    tm = mean([tt(seg_start(s)) tt(seg_end(s))]);
    if val == 0, nm = 'SG'; else, nm = sprintf('IBR_%d',val); end
    if tt(seg_end(s))-tt(seg_start(s)) < 0.03*tmax, continue; end   % skip slivers
    text(axR,tm,val+0.34,nm,'HorizontalAlignment','center', ...
        'FontName',FNAME,'FontSize',FS-3,'Color',refcol);
end
set(axR,'XLim',[0 tmax],'YLim',[-0.6 nibr+0.6], ...
    'YTick',0:nibr,'YTickLabel',[{'SG'} compose('IBR_%d',1:nibr)], ...
    'FontName',FNAME,'FontSize',FS-2,'Box','on','XTickLabel',[], ...
    'TickDir','out','Layer','top');
title(axR,'Reference owner (island angle reference)', ...
    'FontName',FNAME,'FontSize',FS-1,'FontWeight','normal');

% ---- (a) active power ---------------------------------------------------
axA = axes('Parent',f1,'Units','normalized', ...
    'Position',[x0, 3.00/figH, aw, 2.45/figH]); hold(axA,'on');
for j = 1:nibr
    plot(axA,t(w),P(w,j),lst{j},'Color',col{j},'LineWidth',lwd(j));
end
grid(axA,'on'); box(axA,'on');
set(axA,'XLim',[0 tmax],'FontName',FNAME,'FontSize',FS, ...
    'GridAlpha',0.15,'TickDir','out');
ylabel(axA,'P_i [p.u.]','FontName',FNAME,'FontSize',FS);
text(axA,0.012,0.93,'(a)','Units','normalized', ...
    'FontName',FNAME,'FontSize',FS);

% ---- (b) reactive power -------------------------------------------------
axB = axes('Parent',f1,'Units','normalized', ...
    'Position',[x0, 0.45/figH, aw, 2.35/figH]); hold(axB,'on');
for j = 1:nibr
    plot(axB,t(w),Q(w,j),lst{j},'Color',col{j},'LineWidth',lwd(j));
end
grid(axB,'on'); box(axB,'on');
set(axB,'XLim',[0 tmax],'FontName',FNAME,'FontSize',FS, ...
    'GridAlpha',0.15,'TickDir','out');
xlabel(axB,'t [s]','FontName',FNAME,'FontSize',FS);
ylabel(axB,'Q_i [p.u.]','FontName',FNAME,'FontSize',FS);
text(axB,0.012,0.93,'(b)','Units','normalized', ...
    'FontName',FNAME,'FontSize',FS);

% Legend at the very top of the page, above the mode strip: the same fixed
% per-IBR colour/style contract as panels (a),(b).
lg = legend(axA,lbl,'Orientation','horizontal','Box','off', ...
    'FontName',FNAME,'FontSize',FS-2);
lg.Units='normalized';
lg.Position=[x0, 8.06/figH, aw, 0.20/figH];

print(f1,fullfile(outdir,'mode_switch_PQ.png'),'-dpng','-r300');
close(f1);

%% ============ FIGURE 2: active-state dimension and residual ============
% n_x(t) is the dimension of the ACTIVE differential state set actually
% integrated by the composite DAE at each accepted step. It is NOT hard-coded
% here: each device's own runtime map `dynamic_state_indices_for_context` is
% evaluated against a reconstructed event context, and the source-defined
% frozen indices are removed, exactly as stability.ts_dynamic_state_indices
% does at run time. Any divergence between this figure and the integrator is
% therefore impossible by construction, and a device that cannot report its
% map fails closed instead of silently falling back to a literal count.
sgonline = logical(r.device_online_history(1,:)).';
online_hist = logical(r.device_online_history);          % ndev x nt
modes_all   = string(r.device_modes_history);            % ndev x nt

nper = zeros(nt,ndev);
for k = 1:ndev
    dev = devs(k);
    if ~isfield(dev,'dynamic_state_indices_for_context') || ...
            ~isa(dev.dynamic_state_indices_for_context,'function_handle')
        error('generate_switch_new_report_figures:noRuntimeStateMap', ...
            ['Device %s does not expose dynamic_state_indices_for_context; ' ...
             'refusing to guess its active-state count.'], dev.device_id);
    end
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    frozen = [];
    if isfield(dev,'frozen_state_indices'), frozen = dev.frozen_state_indices(:)'; end
    for i = 1:nt
        ec = struct('hybrid_state', struct( ...
            'device_online', struct(key, online_hist(k,i)), ...
            'device_modes',  struct(key, char(modes_all(k,i)))));
        loc = dev.dynamic_state_indices_for_context(ec);
        loc = loc(:)';
        if ~isempty(frozen), loc = setdiff(loc,frozen,'stable'); end
        nper(i,k) = numel(loc);
    end
end
nact = sum(nper,2);

% One accepted-residual entry is appended per ACCEPTED STEP, so entry j is the
% residual of the step that ends at t(j+1). Align it that way rather than at
% t(j), which would shift the whole trace one sample early.
resid = NaN(nt,1);
v = [];
if isfield(r,'accepted_residual_per_step') && ~isempty(r.accepted_residual_per_step)
    v = r.accepted_residual_per_step(:);
elseif isfield(r,'residual_per_step')
    v = r.residual_per_step(:);
end
if ~isempty(v)
    m = min(nt-1,numel(v));
    resid(2:m+1) = v(1:m);
end

t_trip = NaN;
if isfield(r,'sched') && isfield(r.sched,'sg_trip'), t_trip = r.sched.sg_trip; end

FS2  = 11;                              % dense multi-panel tile
figW2 = 6.20; figH2 = 4.60;
f2 = figure('Units','inches','Position',[1 1 figW2 figH2], ...
            'Color','w','PaperUnits','inches', ...
            'PaperSize',[figW2 figH2],'PaperPosition',[0 0 figW2 figH2]);
x02 = 0.95/figW2; aw2 = 5.00/figW2;

axC = axes('Parent',f2,'Units','normalized', ...
    'Position',[x02, 2.60/figH2, aw2, 1.75/figH2]); hold(axC,'on');
stairs(axC,t(w),nact(w),'-','Color',[0 0.24 0.75],'LineWidth',1.3);
if isfinite(t_trip) && t_trip <= tmax
    xline(axC,t_trip,'--','Color',[0.55 0.55 0.55],'LineWidth',0.9, ...
        'HandleVisibility','off');
end
grid(axC,'on'); box(axC,'on');
set(axC,'XLim',[0 tmax],'FontName',FNAME,'FontSize',FS2, ...
    'GridAlpha',0.15,'TickDir','out','XTickLabel',[]);
ylabel(axC,'n_x(t)','FontName',FNAME,'FontSize',FS2);
text(axC,0.012,0.90,'(a)','Units','normalized', ...
    'FontName',FNAME,'FontSize',FS2);

axD = axes('Parent',f2,'Units','normalized', ...
    'Position',[x02, 0.62/figH2, aw2, 1.75/figH2]); hold(axD,'on');
ok = isfinite(resid) & resid > 0 & w;
semilogy(axD,t(ok),resid(ok),'.','Color',[0.85 0.11 0.11],'MarkerSize',4);
if isfinite(t_trip) && t_trip <= tmax
    xline(axD,t_trip,'--','Color',[0.55 0.55 0.55],'LineWidth',0.9);
end
grid(axD,'on'); box(axD,'on');
set(axD,'XLim',[0 tmax],'YScale','log','FontName',FNAME,'FontSize',FS2, ...
    'GridAlpha',0.15,'TickDir','out');
xlabel(axD,'t [s]','FontName',FNAME,'FontSize',FS2);
ylabel(axD,'||R||_\infty','FontName',FNAME,'FontSize',FS2);
text(axD,0.012,0.90,'(b)','Units','normalized', ...
    'FontName',FNAME,'FontSize',FS2);

print(f2,fullfile(outdir,'state_switch_dimension.png'),'-dpng','-r300');
close(f2);

%% ============ FIGURE 3: eight-panel electrical response ================
% Same fixed per-IBR legend/style as FIGURE 1 (IBR1 blue, IBR2 red dashed,
% IBR3 red, IBR4 black; SG black dashed), authored at 6.20 in and printed 1:1.
% Every trace is a raw accepted sample reconstructed from the stored trajectory
% by each device's own reconstruct() callback -- no smoothing, no synthetic
% ripple. i_d/i_q use the SAME network-current-in-device-frame convention as the
% production report generator (Idq = device_current .* exp(-1i*angle_dev)).
elec = reconstruct_electrical(r, t, didx, ibr_buses);
render_electrical_panels(elec, t, w, tmax, col, lst, lwd, lbl, FNAME, outdir);

%% ---------------------------- provenance -------------------------------
out = struct();
out.source_file      = src;
out.t_end            = t(end);
out.t_plot_max       = tmax;
out.samples_plotted  = sum(w);
out.samples_total    = nt;
out.ibr_buses        = ibr_buses(:).';
out.nx_before_trip   = nact(1);
k_after              = find(~sgonline,1);
if isempty(k_after), out.nx_after_trip = NaN;
else,                out.nx_after_trip = nact(k_after); end
out.device_ids       = string({devs.device_id});
out.nx_per_device_before_trip = nper(1,:);
if isempty(k_after), out.nx_per_device_after_trip = nan(1,ndev);
else,                out.nx_per_device_after_trip = nper(k_after,:); end
out.figures = {fullfile(outdir,'mode_switch_PQ.png'), ...
               fullfile(outdir,'state_switch_dimension.png'), ...
               fullfile(outdir,'mode_switch_electrical.png')};
end

% -------------------------------------------------------------------------
function seg = segments(mask, tt)
%SEGMENTS  Contiguous [t_start t_end] intervals where mask is true.
mask = logical(mask(:)); tt = tt(:);
seg = zeros(0,2);
if ~any(mask), return; end
d = diff([false; mask; false]);
i0 = find(d==1); i1 = find(d==-1)-1;
for k = 1:numel(i0)
    a = tt(i0(k));
    if i1(k) < numel(tt), b = tt(min(i1(k)+1,numel(tt))); else, b = tt(end); end
    seg(end+1,:) = [a b]; %#ok<AGROW>
end
end

% -------------------------------------------------------------------------
function e = reconstruct_electrical(r, t, didx, ibr_buses)
%RECONSTRUCT_ELECTRICAL  Rebuild the eight-panel signals from the stored
%   accepted trajectory using each device's own reconstruct() callback. This
%   MIRRORS the production report adapter (generate_ieee14_switch_report_figures
%   / adapt_production_result) exactly, so the panels are numerically identical
%   to the production electrical figure. Nothing is smoothed or synthesised.
nt   = numel(t);
nibr = numel(didx);
devs = r.equilibrium.devices;
xoff = [0 cumsum([devs.nx])];
uoff = [0 cumsum([devs.nu])];

% Complex bus voltages and IBR bus positions.
V = complex(r.y_traj(1:2:end,:), r.y_traj(2:2:end,:));
buspos = zeros(1,nibr);
for j = 1:nibr
    buspos(j) = find(r.bus_ids==ibr_buses(j),1);
end
Vibr   = V(buspos,:).';
busang = unwrap(angle(Vibr),[],1);

modes     = string(r.device_modes_history(didx,:)).';
angle_ibr = busang;
f_ibr     = angle_frequency_local(t,busang,60);
for j = 1:nibr
    d  = devs(didx(j));
    xr = r.x_traj(xoff(didx(j))+(1:d.nx),:).';
    ui = uoff(didx(j))+(1:d.nu);
    for k = 1:nt
        rec = d.reconstruct(t(k),xr(k,:).',r.y_traj(:,k), ...
            r.u_history(ui,k),r.event_context_history{k});
        if isfield(rec,'gfm')
            angle_ibr(k,j) = rec.gfm.delta_VSM;
            f_ibr(k,j)     = 60*(1+rec.gfm.omega_m);
        elseif isfield(rec,'gfl')
            angle_ibr(k,j) = rec.gfl.delta_PLL;
            f_ibr(k,j)     = rec.gfl.f_hz;
        end
    end
end

Iibr = r.device_currents(didx,:).';
Idq  = Iibr.*exp(-1i*angle_ibr);

% SG reconstruction (device 1).
sg       = devs(1);
sg_delta = r.x_traj(1,:).';
sg_omega = r.x_traj(2,:).';
sg_id    = zeros(nt,1); sg_iq = zeros(nt,1);
for k = 1:nt
    rec = sg.reconstruct(t(k),r.x_traj(1:sg.nx,k),r.y_traj(:,k), ...
        r.u_history(uoff(1)+(1:sg.nu),k),r.event_context_history{k});
    sg_id(k) = rec.Id; sg_iq(k) = rec.Iq;
end
sgbp = find(r.bus_ids==r.device_bus_ids(1),1);

e = struct();
e.P     = r.device_P_pu(didx,:).';
e.Q     = r.device_Q_pu(didx,:).';
e.id    = real(Idq);
e.iq    = imag(Idq);
e.f     = f_ibr;
e.ang   = angle_ibr - busang;                % device-to-PCC, unwrapped
e.Vbus  = abs(Vibr);
e.Vmin  = min(abs(V),[],1).';
e.sg_P  = r.device_P_pu(1,:).';
e.sg_Q  = r.device_Q_pu(1,:).';
e.id    = real(Idq);
e.iq    = imag(Idq);
e.f     = f_ibr;
e.ang   = wrap_pi_local(angle_ibr - busang);  % device-to-PCC, wrapped to (-pi,pi]
e.sg_id = sg_id;
e.sg_iq = sg_iq;
e.sg_f  = 60*(1+sg_omega);
e.sg_ang = wrap_pi_local(sg_delta - unwrap(angle(V(sgbp,:))).');
e.modes  = modes;
e.sg_bus = r.device_bus_ids(1);
end

% -------------------------------------------------------------------------
function render_electrical_panels(e, t, w, tmax, col, lst, lwd, lbl, FNAME, outdir)
%RENDER_ELECTRICAL_PANELS  Eight-panel (a-h) electrical figure in the frozen
%   per-IBR style of FIGURE 1. SG is a black dashed overlay where physical.
FS = 11;                                     % dense multi-panel tile
figW = 6.20; figH = 8.30;
f = figure('Units','inches','Position',[1 1 figW figH], ...
    'Color','w','PaperUnits','inches', ...
    'PaperSize',[figW figH],'PaperPosition',[0 0 figW figH]);

nibr = size(e.P,2);
% Tiled 4x2 layout with the legend in a dedicated NORTH tile, exactly like the
% production electrical figure: the legend sits at the very top of the page and
% tiledlayout keeps the panel grid aligned beneath it.
tl = tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');

deg = 180/pi;
panels = { ...
   e.P,   e.sg_P,        'P_i [p.u.]',      '(a) Active power'; ...
   e.Q,   e.sg_Q,        'Q_i [p.u.]',      '(b) Reactive power'; ...
   e.id,  e.sg_id,       'i_{d,i} [p.u.]',  '(c) d-axis current'; ...
   e.iq,  e.sg_iq,       'i_{q,i} [p.u.]',  '(d) q-axis current'; ...
   e.f,   e.sg_f,        'f_i [Hz]',        '(e) PCC / virtual-rotor frequency'; ...
   e.ang*deg, e.sg_ang*deg,'\theta_i [deg]','(f) device-to-PCC angle'; ...
   e.Vbus, [],           '|V_i| [p.u.]',    '(g) PCC voltage'; ...
   e.Vmin, [],           'min |V| [p.u.]',  '(h) network minimum voltage'};

hleg = gobjects(1,nibr); hsg = [];
for p = 1:8
    ax = nexttile(tl); hold(ax,'on');
    Y = panels{p,1}; Ysg = panels{p,2};
    if size(Y,2)==1
        plot(ax,t(w),Y(w,1),'-','Color',[0.15 0.15 0.15],'LineWidth',0.9);
    else
        for j = 1:nibr
            hh = plot(ax,t(w),Y(w,j),lst{j},'Color',col{j},'LineWidth',lwd(j));
            if p==1, hleg(j) = hh; end
        end
    end
    if ~isempty(Ysg)
        hs = plot(ax,t(w),Ysg(w),'k--','LineWidth',0.75);
        if p==1, hsg = hs; end
    end
    grid(ax,'on'); box(ax,'on');
    set(ax,'XLim',[0 tmax],'FontName',FNAME,'FontSize',FS, ...
        'GridAlpha',0.15,'TickDir','out');
    ylabel(ax,panels{p,3},'FontName',FNAME,'FontSize',FS);
    title(ax,panels{p,4},'FontName',FNAME,'FontSize',FS,'FontWeight','bold');
    if ceil(p/2)==4, xlabel(ax,'t [s]','FontName',FNAME,'FontSize',FS); end
end

leg_entries = lbl;
leg_handles = hleg;
if ~isempty(hsg)
    leg_handles = [hleg hsg];
    leg_entries = [lbl, {sprintf('SG (bus %d)', e.sg_bus)}];
end
% Attach the legend to the tiled layout, not to a panel, so it sits at the
% very top of the figure instead of between panel rows.
lg = legend(leg_handles, leg_entries,'Orientation','horizontal', ...
    'Box','off','NumColumns',5);
lg.Layout.Tile = 'north';
set(lg,'FontName',FNAME,'FontSize',FS-2);

print(f,fullfile(outdir,'mode_switch_electrical.png'),'-dpng','-r300');
close(f);
end

% -------------------------------------------------------------------------
function f = angle_frequency_local(t,ang,f0)
%ANGLE_FREQUENCY_LOCAL  Instantaneous frequency from an unwrapped bus angle,
%   f = f0 + (1/2pi) d(ang)/dt, by central difference. Presentation only.
t = t(:); nt = numel(t);
f = f0*ones(size(ang));
if nt < 2, return; end
for j = 1:size(ang,2)
    dth = gradient(ang(:,j), t);
    f(:,j) = f0 + dth/(2*pi);
end
end

% -------------------------------------------------------------------------
function a = wrap_pi_local(a)
a = mod(a+pi, 2*pi) - pi;
end
