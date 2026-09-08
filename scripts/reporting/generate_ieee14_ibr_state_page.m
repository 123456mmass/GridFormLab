function out = generate_ieee14_ibr_state_page(opts)
%GENERATE_IEEE14_IBR_STATE_PAGE  IBR state response, 2x2, from the stored run.
%
%   out = generate_ieee14_ibr_state_page()
%   out = generate_ieee14_ibr_state_page(scenarios="sg_fault_cycle160")
%
% The page the 2026-09-08 review asked for: four converter STATES that show the
% physical/controller transition across a GFL->GFM->GFL cycle, drawn from the
% stored trajectory of the delivered 160 s arm. Pure cache reader: nothing is
% simulated, re-solved, smoothed, decimated or padded.
%
% WHICH CONVERTER, AND WHY. The page follows IBR_1 (code name IBR2, bus 2), the
% converter that takes the island angle reference at the SG trip and holds it
% until the hand-back. Its GFM interval is 20.00 s to 116.24 s, so all four
% panels show the full cycle: GFL, the switch into GFM, the fault ridden
% through in GFM, and the return to GFL.
%
% WHICH FOUR STATES, AND WHY. The 17-state layout is
%   [i_d i_q V_dc | gfl: d_PLL xi_PLL xi_P xi_Q xi_Id xi_Iq |
%    gfm: d_VSG omega_VSG E xi_Vd xi_Vq xi_Id xi_Iq | I_dc]
% (+ibr/eecon49_dual_mode_model.m header). The four chosen are the ones that
% carry the transition a viewer needs to see:
%   (a) i_d, i_q   -- the physical AC port current, CONTINUOUS across both
%                     switches (the transfer map preserves it; the page shows
%                     that rather than asserting it);
%   (b) V_dc, I_dc -- the shared DC plant, which keeps evolving in both modes
%                     and reacts to the fault;
%   (c) omega_VSG  -- the GFM frequency coordinate: held at its anchor while
%                     GFL is active, integrated while GFM is active, held again
%                     after the hand-back. The hold/integrate/hold pattern IS
%                     the mode-switching mechanism made visible;
%   (d) E          -- the GFM voltage amplitude state, same hold/integrate/hold
%                     pattern on the voltage side.
% Controller integrator states (xi_*) are not shown: they are re-initialised at
% each transfer by design, so their traces are discontinuous BY CONSTRUCTION and
% would invite a question the mechanism already answers.
%
% HELD STATES ARE DRAWN HELD. omega_VSG and E are constant outside the GFM
% interval because the inactive branch is frozen, not integrated
% (case_data.inactive_state_rule, policy 'frozen'). The page draws them as they
% are stored; the GFM interval is marked by the mode strip above each panel so
% the held stretches read as held, not as flat data.
%
% Lettering follows the standing contract: Helvetica through the 'tex'
% interpreter, no box, ticks outward, dashed major and minor grid, and a .fig
% beside every PNG.
%
% Classification: presentation only. No value computed here feeds PF, SSSA, TS,
% a selector, a controller or an acceptance decision.

arguments
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_scenario_suite')
    opts.out_dir (1,1) string = fullfile('docs','source','figures', ...
        'ieee14_scenario_suite')
    opts.scenarios (1,:) string = "sg_fault_cycle160"
    % 2x2 on one slide: the canvas is the deck's text width, tall enough that
    % each panel keeps about 1.05 in of data height under its mode strip.
    opts.width_in (1,1) double {mustBePositive} = 4.65
    opts.height_in (1,1) double {mustBePositive} = 2.90
    opts.font_size (1,1) double {mustBePositive} = 10
    opts.font_name (1,1) string = "Helvetica"
    opts.dpi (1,1) double {mustBePositive} = 300
    opts.save_fig (1,1) logical = true
end

pf_init_paths();
cdir = char(opts.cache_dir);
odir = char(opts.out_dir);
if ~isfolder(odir), mkdir(odir); end

out = struct();
out.schema = 'ieee14_ibr_state_page/1.0';
out.classification = 'PRESENTATION_ONLY';
out.cache_dir = cdir;
out.out_dir = odir;
out.generated_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
out.pages = struct([]);

for k = 1:numel(opts.scenarios)
    id = char(opts.scenarios(k));
    C = read_cache(cdir,id);
    page = draw_page(C,odir,opts);
    if isempty(out.pages), out.pages = page; else, out.pages(end+1) = page; end
    fprintf(['[%s] IBR state page: %d samples | %s GFM %.3f..%.3f s | ' ...
        'i_d jump at switch %.2e | omega_VSG held outside GFM: %s\n'], ...
        id,page.n_samples,page.device_code,page.gfm_interval(1), ...
        page.gfm_interval(2),page.id_step_at_switch, ...
        mat2str(page.omega_held_outside_gfm));
end
end

% ==========================================================================
function C = read_cache(cdir,id)
%READ_CACHE  One scenario cache; the state trajectory and the mode history.
f = fullfile(cdir,[id '.mat']);
if ~isfile(f)
    error('generate_ieee14_ibr_state_page:cacheMissing', ...
        ['No cache at %s. Run run_ieee14_scenario_suite(scenarios="%s") ' ...
         'first; this generator never simulates.'],f,id);
end
S = load(f);
for fld = {'result','arm','opt_signature'}
    if ~isfield(S,fld{1})
        error('generate_ieee14_ibr_state_page:cacheIncomplete', ...
            'Cache %s lacks the "%s" variable.',f,fld{1});
    end
end
C = struct('id',id,'file',f,'r',S.result,'arm',S.arm,'sig',S.opt_signature);
end

% ==========================================================================
function page = draw_page(C,odir,opts)
%DRAW_PAGE  Four panels, two by two, each under its own GFM-mode strip.
r = C.r;
t = r.t(:);
nt = numel(t);
fs = opts.font_size;
FN = char(opts.font_name);

% --- locate IBR2 (deck name IBR_1) inside the 74-state vector -------------
% The composite layout is SG1 (6 states) then the four 17-state IBRs in device
% order, verified against the stored state names rather than assumed.
devs = r.equilibrium.devices;
ids = cellstr(string({devs.device_id}));
target = find(strcmp(ids,'IBR2'),1);
if isempty(target)
    error('generate_ieee14_ibr_state_page:deviceMissing', ...
        'The run carries no device named IBR2.');
end
names = devs(target).state_names;
if numel(names) ~= 17
    error('generate_ieee14_ibr_state_page:stateCount', ...
        'IBR2 declares %d states, not 17.',numel(names));
end
need = {'i_d','i_q','V_dc','gfm_omega_VSG','gfm_E','I_dc'};
col = zeros(1,numel(need));
base = sum(cellfun(@numel,{devs(1:target-1).state_names}));
for q = 1:numel(need)
    j = find(strcmp(names,need{q}),1);
    if isempty(j)
        error('generate_ieee14_ibr_state_page:stateMissing', ...
            'IBR2 carries no state named %s.',need{q});
    end
    col(q) = base + j;
end
x = r.x_traj;
% The cache stores x_traj as [n_states x n_samples]; work sample-major.
if size(x,1) == nt && size(x,2) >= max(col)
    % already [samples x states]
elseif size(x,2) == nt && size(x,1) >= max(col)
    x = x.';
else
    error('generate_ieee14_ibr_state_page:trajectoryShape', ...
        'x_traj is %s for %d samples and a column index up to %d.', ...
        mat2str(size(x)),nt,max(col));
end
i_d  = x(:,col(1));  i_q = x(:,col(2));
V_dc = x(:,col(3));  wsg = x(:,col(4));
E    = x(:,col(5));  Idc = x(:,col(6));

% --- the mode of THIS converter, per accepted sample ----------------------
% device_modes_history is stored [n_devices x n_samples] (cell of strings).
mh = r.device_modes_history;
if ~iscell(mh)
    error('generate_ieee14_ibr_state_page:modeHistoryType', ...
        'device_modes_history is %s, not a cell array.',class(mh));
end
if size(mh,1) == numel(ids) && size(mh,2) == nt
    mcol = mh(target,:);
elseif size(mh,2) == numel(ids) && size(mh,1) == nt
    mcol = mh(:,target).';
else
    error('generate_ieee14_ibr_state_page:modeHistoryShape', ...
        'device_modes_history is %s; expected %d devices by %d samples.', ...
        mat2str(size(mh)),numel(ids),nt);
end
gfm = strcmpi(mcol,'gfm');
gfm = logical(gfm(:));
if numel(gfm) ~= nt
    error('generate_ieee14_ibr_state_page:modeLength', ...
        'Mode history has %d samples for %d trajectory samples.', ...
        numel(gfm),nt);
end
iv = true_intervals(gfm,t);
if isempty(iv)
    error('generate_ieee14_ibr_state_page:noGfmInterval', ...
        'IBR2 was never grid-forming on this arm; the page has no transition to show.');
end
gfm_interval = [iv(1,1) iv(end,2)];

% --- the continuity the page exists to show --------------------------------
% The largest one-step change of i_d within +/-2 samples of the switch instant
% is reported, not asserted small: the transfer map preserves the current, so
% the number belongs in provenance where a reader can check it.
k_sw = find(gfm & ~[false;gfm(1:end-1)],1);
if isempty(k_sw), k_sw = 1; end
win = max(1,k_sw-2):min(nt,k_sw+2);
id_step = max(abs(diff(i_d(win))));
% omega_VSG held outside the GFM interval: max variation over the held stretches.
held = ~gfm;
w_held = wsg(held);
omega_held = isempty(w_held) || (max(w_held)-min(w_held) < 1e-9);

% --- canvas: 2x2, each panel under its own mode strip ----------------------
W = opts.width_in; H = opts.height_in;
LEFT = 0.52; RIGHT = 0.05; GAPX = 0.46;
BOT = 0.46; TOP = 0.10; GAPY = 0.52;
STRIPH = 0.10; STRIPGAP = 0.03;
COLW = (W - LEFT - RIGHT - GAPX)/2;
ROWH = (H - BOT - TOP - GAPY - 2*(STRIPH+STRIPGAP))/2;
if ROWH <= 0.30
    error('generate_ieee14_ibr_state_page:canvasTooShort', ...
        'The canvas leaves %.2f in per panel; raise height_in.',ROWH);
end
f1 = pf_page_figure(W,H,fs,opts.font_name);
xr = [0 t(end)];
col_blue = [0.00 0.16 0.70];

panels = { ...
    '{\iti_d}, {\iti_q} [p.u.]',        {i_d,i_q}, {'{\iti_d}','{\iti_q}'}, '(a)'; ...
    '{\itV_{dc}}, {\itI_{dc}} [p.u.]',  {V_dc,Idc}, {'{\itV_{dc}}','{\itI_{dc}}'}, '(b)'; ...
    '\omega_{VSG} [p.u.]',              {wsg},      {'\omega_{VSG}'}, '(c)'; ...
    '{\itE} [p.u.]',                    {E},        {'{\itE}'}, '(d)'};
pos = [LEFT,               BOT+ROWH+GAPY+STRIPH+STRIPGAP; ...
       LEFT+COLW+GAPX,     BOT+ROWH+GAPY+STRIPH+STRIPGAP; ...
       LEFT,               BOT; ...
       LEFT+COLW+GAPX,     BOT];

for p = 1:4
    x0 = pos(p,1); y0 = pos(p,2);
    ax = axes_in(f1,[x0 y0 COLW ROWH],W,H); hold(ax,'on');
    traces = panels{p,2};
    names_p = panels{p,3};
    for q = 1:numel(traces)
        plot(ax,t,traces{q},'Color',col_blue*(1-0.45*(q-1))+[0 0 0], ...
            'LineWidth',1.0,'HandleVisibility','off');
    end
    yl = panel_window(ax,cell2mat(cellfun(@(c)c(:),traces, ...
        'UniformOutput',false)),0.10);
    xlim(ax,xr);
    % event rules AFTER the window is fixed, so they span the panel exactly
    for ev = [20 60 60.15 100]
        xline(ax,ev,':','Color',[0.45 0.45 0.45],'LineWidth',0.6, ...
            'HandleVisibility','off');
    end
    % label each trace inline at its right end, so no legend box is needed
    for q = 1:numel(traces)
        yv = traces{q}(end);
        text(ax,xr(2),min(max(yv,yl(1)+0.04*(yl(2)-yl(1))), ...
            yl(2)-0.04*(yl(2)-yl(1))),[' ' names_p{q}], ...
            'FontName',FN,'FontSize',fs-2, ...
            'Interpreter','tex','HorizontalAlignment','left', ...
            'VerticalAlignment','middle','Clipping','off');
    end
    finish_panel(ax,fs,FN,panels{p,1},'{\itt} [s]',panels{p,4});
    % mode strip above the panel: one lane, one bar for the GFM interval
    mode_strip_single(f1,[x0 y0+ROWH+STRIPGAP COLW STRIPH],W,H,t,gfm, ...
        col_blue,xr);
    page_range{p} = yl; %#ok<AGROW>
end

png = fullfile(odir,sprintf('%s_ibr_states.png',C.id));
pf_page_export(f1,png,opts.dpi,opts.save_fig);
if opts.save_fig
    figf = fullfile(odir,sprintf('%s_ibr_states.fig',C.id));
else
    figf = '';
end

page = struct();
page.id = C.id;
page.cache = C.file;
page.png = png;
page.fig = figf;
page.n_samples = nt;
page.device_code = 'IBR2';
page.device_deck = 'IBR_1';
page.state_columns = col;
page.gfm_interval = gfm_interval;
page.id_step_at_switch = id_step;
page.omega_held_outside_gfm = omega_held;
page.panel_windows = page_range;
end

% ==========================================================================
function ax = axes_in(f,rect_in,W,H)
%AXES_IN  One axes at an explicit rectangle given in INCHES on the canvas.
ax = axes(f,'Units','normalized', ...
    'Position',[rect_in(1)/W rect_in(2)/H rect_in(3)/W rect_in(4)/H]);
end

% ==========================================================================
function mode_strip_single(f,rect_in,W,H,t,gfm,col,xr)
%MODE_STRIP_SINGLE  One lane: a bar over the interval this converter was GFM.
ax = axes_in(f,rect_in,W,H); hold(ax,'on');
ylim(ax,[0.5 1.5]);
iv = true_intervals(gfm,t);
for j = 1:size(iv,1)
    patch(ax,'XData',[iv(j,1) iv(j,2) iv(j,2) iv(j,1)], ...
        'YData',[0.72 0.72 1.28 1.28], ...
        'FaceColor',col,'FaceAlpha',1,'EdgeColor','none', ...
        'HandleVisibility','off','Clipping','on');
end
xlim(ax,xr);
set(ax,'Box','off','XTick',[],'YTick',[],'XColor','none','YColor','none', ...
    'Color','none','Layer','top');
% a short label at the left of the strip
text(ax,0,1.0,'{\itGFM}','Units','normalized','FontName','Helvetica', ...
    'FontSize',7,'Interpreter','tex','HorizontalAlignment','right', ...
    'VerticalAlignment','middle','Color',[0.15 0.15 0.15]);
end

% ==========================================================================
function iv = true_intervals(mask,t)
%TRUE_INTERVALS  Contiguous [t_start t_end] runs of a logical mask.
mask = logical(mask(:));
iv = zeros(0,2);
if ~any(mask), return; end
dm = diff([false; mask; false]);
a = find(dm == 1);
b = find(dm == -1) - 1;
for j = 1:numel(a)
    t0 = t(a(j)); t1 = t(b(j));
    if t1 <= t0
        nx = min(b(j)+1,numel(t));
        if nx > b(j), t1 = t(nx); else, t1 = t0 + eps(t0); end
    end
    iv(end+1,:) = [t0 t1]; %#ok<AGROW>
end
end

% ==========================================================================
function yl = panel_window(ax,Y,headroom)
%PANEL_WINDOW  Y limits from the data, with headroom.
yl = ylim(ax);
y = Y(isfinite(Y));
if isempty(y), return; end
lo = min(y); hi = max(y);
if hi - lo < 1e-9
    pad = max(0.05,abs(hi)*0.05);
    lo = lo - pad; hi = hi + pad;
else
    pad = headroom*(hi-lo);
    lo = lo - pad; hi = hi + pad;
end
yl = [lo hi];
ylim(ax,yl);
end

% ==========================================================================
function finish_panel(ax,fs,FN,ylab,xlab,tag)
%FINISH_PANEL  No box, ticks outward, dashed major and minor grid, deck font.
set(ax,'Box','off','TickDir','out','Layer','bottom', ...
    'XMinorGrid','on','YMinorGrid','on','MinorGridLineStyle','--', ...
    'MinorGridColor',[0.65 0.65 0.65],'GridLineStyle','--', ...
    'GridColor',[0.85 0.85 0.85],'TickLabelInterpreter','tex', ...
    'FontName',FN,'FontSize',fs);
grid(ax,'on');
ylabel(ax,ylab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
if ~isempty(xlab)
    xlabel(ax,xlab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
else
    set(ax,'XTickLabel',[]);
end
text(ax,0.5,-0.42,tag,'Units','normalized','Interpreter','tex', ...
    'HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontName',FN,'FontSize',fs,'Clipping','off');
end
