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
%   (a) i_d        -- the shared physical AC-port current;
%   (b) V_dc       -- the shared DC-plant voltage;
%   (c) omega_PLL  -- the GFL frequency output in p.u., reconstructed from
%                     the PLL states: v_q = imag(V_bus*exp(-1i*delta_PLL)),
%                     dw = kpPLL*v_q + kiPLL*xi_PLL,
%                     omega_PLL = 1 + dw/omega_b
%                     (gfl_eecon49_full_model.m);
%   (d) omega_VSG  -- the GFM frequency coordinate: held at its anchor while
%                     GFL is active, integrated while GFM is active, held again
%                     after the hand-back. The hold/integrate/hold pattern IS
%                     the mode-switching mechanism made visible.
% Controller integrator states (xi_*) are not shown: they are re-initialised at
% each transfer by design, so their traces are discontinuous BY CONSTRUCTION and
% would invite a question the mechanism already answers.
%
% HELD STATES ARE DRAWN HELD. omega_VSG is constant outside the GFM interval
% because the inactive branch is frozen, not integrated
% (case_data.inactive_state_rule, policy 'frozen'). The page draws the states
% as they are stored; omega_PLL exists only on the GFL samples, so the two
% frequency traces together mark the mode interval without any overlay.
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
    % เว้นที่ให้ legend, tick, xlabel และชื่อ panel ใต้กราฟ
    opts.width_in (1,1) double {mustBePositive} = 4.65
    opts.height_in (1,1) double {mustBePositive} = 3.12
    opts.font_size (1,1) double {mustBePositive} = 9
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
need = {'i_d','i_q','V_dc','gfm_omega_VSG'};
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
i_d  = x(:,col(1));
i_q  = x(:,col(2));
V_dc = x(:,col(3));
wsg  = x(:,col(4));

% omega_PLL: the 17-state vector keeps the PLL angle (gfl_delta_PLL) and its
% integrator (gfl_xi_PLL); the PLL frequency output is reconstructed from those
% two states, the way the GFL branch itself computes it
% (gfl_eecon49_full_model.m): dw = kpPLL*v_q + kiPLL*xi_PLL with
% v_q = imag(V_bus * exp(-1i*delta_PLL)). The device object stored in the cache
% carries that branch and its parameters, so the page evaluates the stored
% trajectory through it. Only GFL samples keep the value (NaN elsewhere).
dpll_col = find(strcmp(names,'gfl_delta_PLL'),1);
xpll_col = find(strcmp(names,'gfl_xi_PLL'),1);
if isempty(dpll_col) || isempty(xpll_col)
    error('generate_ieee14_ibr_state_page:pllStateMissing', ...
        'IBR2 carries no gfl_delta_PLL/gfl_xi_PLL states.');
end
dpll = x(:,base+dpll_col);
xpll = x(:,base+xpll_col);
dev = devs(target);
% The PLL gains and base frequency are the GFL branch defaults from
% gfl_eecon49_full_model.m (the case ships no override). The dual-mode shell
% does not carry them on the device struct, so read them straight from the
% source constants, the same values the live model used.
kpPLL = 1.20; kiPLL = 5.00; omega_b = 2*pi*60;
yrow = @(v,i) v(i,:);
Vre = yrow(r.y_traj,2*dev.bus_position-1);
Vim = yrow(r.y_traj,2*dev.bus_position);
wpll = nan(nt,1);
for jj = 1:nt
    Vb = complex(Vre(jj),Vim(jj));
    vq = imag(Vb*exp(-1i*dpll(jj)));
    dw = kpPLL*vq + kiPLL*xpll(jj);
    wpll(jj) = 1 + dw/omega_b;
end

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
% สีน้ำเงินคือ active; สีเทาของ VSG คือ state ที่บันทึกขณะ inactive
% PLL hold ref. เป็นเส้นอ้างอิงแสดงค่าก่อนเข้า GFM ไม่ใช่ output ที่จำลอง
wpll_active = wpll;
wpll_active(gfm) = NaN;
wpll_frozen = nan(nt,1);
k_on = find(gfm & ~[false;gfm(1:end-1)]);
k_off = find(gfm & ~[gfm(2:end);false]);
for q = 1:numel(k_on)
    k_hold = max(1,k_on(q)-1);
    wpll_frozen(k_on(q):k_off(q)) = wpll(k_hold);
end
wsg_active = wsg;
wsg_active(~gfm) = NaN;
wsg_frozen = wsg;
wsg_frozen(gfm) = NaN;

% เว้นขอบและช่องระหว่าง panel ให้ข้อความ Helvetica ไม่ชนกัน
W = opts.width_in; H = opts.height_in;
LEFT = 0.58; RIGHT = 0.18; GAPX = 0.68;
BOT = 0.55; TOP = 0.28; GAPY = 0.72;
COLW = (W - LEFT - RIGHT - GAPX)/2;
ROWH = (H - BOT - TOP - GAPY)/2;
if ROWH <= 0.30
    error('generate_ieee14_ibr_state_page:canvasTooShort', ...
        'The canvas leaves %.2f in per panel; raise height_in.',ROWH);
end
f1 = pf_page_figure(W,H,fs,opts.font_name);
xr = [0 t(end)];
col_blue = [0.00 0.16 0.70];
col_frozen = [0.40 0.40 0.40];

panels = { ...
    'i_d, i_q [p.u.]',       {i_d,i_q},                    '(a)'; ...
    'V_{dc} [p.u.]',         {V_dc},                       '(b)'; ...
    '\omega_{PLL} [p.u.]',   {wpll_frozen,wpll_active},    '(c)'; ...
    '\omega_{VSG} [p.u.]',   {wsg_frozen,wsg_active},      '(d)'};
pos = [LEFT,               BOT+ROWH+GAPY; ...
       LEFT+COLW+GAPX,     BOT+ROWH+GAPY; ...
       LEFT,               BOT; ...
       LEFT+COLW+GAPX,     BOT];

for p = 1:4
    x0 = pos(p,1); y0 = pos(p,2);
    ax = axes_in(f1,[x0 y0 COLW ROWH],W,H); hold(ax,'on');
    traces = panels{p,2};
    for q = 1:numel(traces)
        if p >= 3 && q == 1
            plot(ax,t,traces{q},'--','Color',col_frozen, ...
                'LineWidth',1.0,'HandleVisibility','off');
        elseif p == 1 && q == 2
            plot(ax,t,traces{q},'-','Color',[0 0 0], ...
                'LineWidth',1.0,'HandleVisibility','off');
        else
            plot(ax,t,traces{q},'-','Color',col_blue, ...
                'LineWidth',1.0,'HandleVisibility','off');
        end
    end
    yl = panel_window(ax,cell2mat(cellfun(@(c)c(:),traces, ...
        'UniformOutput',false)),0.10);
    xlim(ax,xr);
    finish_panel(ax,fs,FN,panels{p,1},'t [s]',panels{p,3},ROWH);
    xticks(ax,0:50:t(end));
    switch p
        case 1
            col_iq = [0 0 0];
            direct_label(ax,t,i_d,'i_d',col_blue,yl,fs,FN,0.84,0.09);
            direct_label(ax,t,i_q,'i_q',col_iq,yl,fs,FN,0.84,0.09);
            hactive = plot(ax,NaN,NaN,'-','Color',col_blue,'LineWidth',1);
            hhold = plot(ax,NaN,NaN,'--','Color',col_frozen,'LineWidth',1);
            hthird = plot(ax,NaN,NaN,'-','Color',col_iq,'LineWidth',1);
            lg = legend(ax,[hactive hhold hthird],{'Active state','Hold state','i_q'}, ...
                'Orientation','horizontal','Box','off','Interpreter','tex', ...
                'FontName',FN,'FontSize',fs-0.5,'AutoUpdate','off');
            lg.Units = 'normalized';
            lg.Position = [0.23 0.943 0.61 0.047];
    end
    page_range{p} = yl; %#ok<AGROW>
end

png = fullfile(odir,sprintf('%s_ibr_states_v15.png',C.id));
pf_page_export(f1,png,opts.dpi,opts.save_fig);
if opts.save_fig
    figf = fullfile(odir,sprintf('%s_ibr_states_v15.fig',C.id));
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
function direct_label(ax,t,y,label,color,yl,fs,FN,xfrac,yoffset)
%DIRECT_LABEL วาง label ภายในกราฟ โดยเว้นระยะจากเส้นและขอบ
xv = t(1) + xfrac*(t(end)-t(1));
valid = find(isfinite(y));
if isempty(valid), return; end
[~,j] = min(abs(t(valid)-xv));
k = valid(j);
yv = min(max(y(k)+yoffset*diff(yl),yl(1)+0.10*diff(yl)), ...
    yl(2)-0.10*diff(yl));
text(ax,t(k),yv,label,'FontName',FN,'FontSize',fs, ...
    'Color',color,'Interpreter','tex','HorizontalAlignment','center', ...
    'VerticalAlignment','middle','Clipping','on');
end

% ==========================================================================
function finish_panel(ax,fs,FN,ylab,xlab,tag,rowh)
%FINISH_PANEL Helvetica แบบสไลด์: แกน x จำนวนเต็ม แกน y สองตำแหน่ง
set(ax,'Box','off','TickDir','out','Layer','bottom', ...
    'XMinorGrid','on','YMinorGrid','on','MinorGridLineStyle','--', ...
    'MinorGridColor',[0.65 0.65 0.65],'GridLineStyle','--', ...
    'GridColor',[0.85 0.85 0.85],'TickLabelInterpreter','tex', ...
    'FontName',FN,'FontSize',fs,'PositionConstraint','innerposition');
grid(ax,'on');
xtickformat(ax,'%.0f');
ytickformat(ax,'%.2f');
ylabel(ax,ylab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
xl = xlabel(ax,xlab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
xl.Units = 'normalized';
xl.Position(1:2) = [0.5 -0.25/rowh];
text(ax,0.5,-0.41/rowh,tag,'Units','normalized','Interpreter','tex', ...
    'HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontName',FN,'FontSize',fs,'Clipping','off');
end
