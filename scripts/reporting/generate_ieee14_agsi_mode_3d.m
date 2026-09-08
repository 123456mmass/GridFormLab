function out = generate_ieee14_agsi_mode_3d(opts)
%GENERATE_IEEE14_AGSI_MODE_3D  Two 3-D pages per scenario: the index, and the mode.
%
%   out = generate_ieee14_agsi_mode_3d()
%   out = generate_ieee14_agsi_mode_3d(scenarios="sg_fault_cycle160")
%
% The layout is the owner's reference pair: one waterfall of the switching index
% per converter against time with the two decision planes floating in it, and one
% block page of the mode m_i(t) per converter. Both are drawn in three dimensions
% with the converter axis running left and time running right, which is what makes
% four converters legible on one page without four stacked panels.
%
% Pure cache reader over the artifacts run_ieee14_scenario_suite wrote. Nothing is
% simulated, re-solved, smoothed, decimated, interpolated or padded: every plotted
% sample is a raw accepted value from the stored trajectory.
%
% SYMBOLS. The reference figures letter the index AGSI_i and its thresholds
% AGSI_up / AGSI_down. These pages letter them S_i, Gamma_on and Gamma_off,
% because that is what the deck defines on its switching-decision page and what
% the code calls them (ts_simulate_ibr_hybrid.m:2973 forms S; the thresholds are
% the run options severity_gamma_on/off). The FORM is the reference's; the names
% are the ones the rest of the deck and the kernel already use, so no symbol
% appears on a slide without a definition behind it.
%
% WHAT IS PLOTTED, and from where:
%   S_i(t) = min(1, max(0, 0.5*J_V + 0.5*J_f))   ieee14_switch_decision_signals
%   m_i(t) = 1 where the device mode is 'gfm', 0 otherwise, masked to NaN wherever
%            the device is OFFLINE. The mask matters: device_modes_history holds
%            'tripped' for a converter that is out of service and a bare
%            strcmpi(...,'gfm') test reads that as 0, which on this axis is the
%            GFL level -- a departed converter would be drawn as one that is
%            following the grid.
%
% CONVERTER LABELS. The pages letter the four converters IBR_1..IBR_4 in the
% deck's own order, which is bus order 2, 3, 6, 8. The code names them by their
% bus (IBR2, IBR3, IBR6, IBR8), so the mapping is written into provenance.txt
% rather than left for a reader to guess.
%
% Lettering follows the standing contract: Helvetica through the 'tex'
% interpreter, ticks outward, dashed grid, and a .fig written beside every PNG
% (pf_page_export's fourth argument must be true -- it defaults false).
%
% Classification: presentation only. No value computed here feeds PF, SSSA, TS, a
% selector, a controller or an acceptance decision.

arguments
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_scenario_suite')
    opts.out_dir (1,1) string = fullfile('docs','source','figures', ...
        'ieee14_scenario_suite')
    opts.scenarios (1,:) string = "sg_fault_cycle160"
    opts.width_in (1,1) double {mustBePositive} = 4.20
    % ONE height for BOTH pages. They were briefly given different heights to let
    % the shorter mode page reclaim slide space, and that produced a visible
    % artifact: MATLAB rotates 3-D tick labels from the axis's PROJECTED slope, so
    % the shorter canvas tipped the time labels to near-vertical while the index
    % page kept them flat. Two pages of one run then carried different lettering.
    % Equal canvases mean one projection and one label orientation.
    %
    % The height is what lets the pair share a slide: at 1.38 in each, both fit at
    % 0.86 of the text width, so 10 pt lettering arrives at about 9 pt -- the
    % deck's own body size.
    opts.height_in (1,1) double {mustBePositive} = 1.38
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
out.schema = 'ieee14_agsi_mode_3d/1.0';
out.classification = 'PRESENTATION_ONLY';
out.cache_dir = cdir;
out.out_dir = odir;
out.generated_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
out.style = struct('width_in',opts.width_in,'height_in',opts.height_in, ...
    'font_size',opts.font_size,'font_name',char(opts.font_name), ...
    'interpreter','tex','view','3-D waterfall / block', ...
    'grid','dashed');
out.pages = struct([]);

for k = 1:numel(opts.scenarios)
    id = char(opts.scenarios(k));
    C = read_cache(cdir,id);
    page = draw_pages(C,odir,opts);
    if isempty(out.pages), out.pages = page; else, out.pages(end+1) = page; end
    fprintf(['[%s] %d samples | horizon %.6f of %.6f s | S in [%.4f, %.4f] | ' ...
        '%d GFM interval(s) | %d mode sample(s) masked offline\n'], ...
        id,page.n_samples,page.t_last,page.t_end_requested, ...
        page.S_min,page.S_max,page.n_gfm_intervals,page.n_mode_masked);
end

write_provenance(odir,out);
end

% ==========================================================================
function C = read_cache(cdir,id)
%READ_CACHE  One scenario cache plus the thresholds the run actually used.
%   The thresholds come from the stored option signature, never from a default
%   here: severity_gamma_on/off are top-level run options and are NOT republished
%   in result.metadata, so the signature saved beside the trajectory is the only
%   record of what the supervisor compared S against. A page annotated with a
%   threshold pair the run did not use looks explained when it is not.
f = fullfile(cdir,[id '.mat']);
if ~isfile(f)
    error('generate_ieee14_agsi_mode_3d:cacheMissing', ...
        ['No cache at %s. Run run_ieee14_scenario_suite(scenarios="%s") ' ...
         'first; this generator never simulates.'],f,id);
end
S = load(f);
for fld = {'result','arm','opt_signature'}
    if ~isfield(S,fld{1})
        error('generate_ieee14_agsi_mode_3d:cacheIncomplete', ...
            'Cache %s lacks the "%s" variable.',f,fld{1});
    end
end
C = struct('id',id,'file',f,'r',S.result,'arm',S.arm,'sig',S.opt_signature);
C.gamma_on  = sig_num(C.sig,'severity_gamma_on');
C.gamma_off = sig_num(C.sig,'severity_gamma_off');
C.t_end_requested = sig_num(C.sig,'t_end');
if ~isfinite(C.gamma_on) || ~isfinite(C.gamma_off)
    error('generate_ieee14_agsi_mode_3d:thresholdsUnrecorded', ...
        ['Cache %s records no severity_gamma_on/off. The decision planes ' ...
         'cannot be drawn at thresholds that are not in the artifact.'],f);
end
if ~isfinite(C.t_end_requested)
    C.t_end_requested = num_or(C.r.sched,'t_end',NaN);
end
if ~isfinite(C.t_end_requested)
    error('generate_ieee14_agsi_mode_3d:horizonUnrecorded', ...
        'Cache %s records no requested horizon.',f);
end
end

% ==========================================================================
function page = draw_pages(C,odir,opts)
%DRAW_PAGES  The index waterfall and the mode block page for one scenario.
r = C.r;
d = ieee14_switch_decision_signals(r, ...
    gamma_on=C.gamma_on,gamma_off=C.gamma_off);

t   = d.t(:);
nt  = numel(t);
nd  = numel(d.device_ids);
fs  = opts.font_size;
FN  = char(opts.font_name);

% Deck labels in the deck's own order, which is bus order. The code's own names
% travel with the page into provenance.txt so the mapping is never inferred.
%
% The tick carries the INDEX only and the axis is named IBR_i, as the reference
% figure names it. Spelling "IBR_4 IBR_3 IBR_2 IBR_1" on the ticks was tried and
% abandoned: MATLAB rotates 3-D tick labels along the projected axis, so four
% eight-character labels arrive stacked on top of one another at slide size. One
% digit per tick under a named axis says the same thing and stays legible.
deck_labels = arrayfun(@(q)sprintf('%d',q),1:nd,'UniformOutput',false);
deck_labels_full = arrayfun(@(q)sprintf('IBR_%d',q),1:nd,'UniformOutput',false);

% The x axis spans the REQUESTED horizon, not the last accepted sample: on a
% truncated run, cropping to the data would draw a refusal as a finished run.
xr = [0 C.t_end_requested];

% The time ticks are set EXPLICITLY, identically on both pages. MATLAB chooses
% them from the axis's physical size, and the mode page's shorter canvas made it
% pick a coarser set than the index page -- two pages of one run would then carry
% different time gradations and could not be read against each other.
xt = time_ticks(xr);

S = d.S;                                % nt x nd, already min/max saturated
mode01 = double(d.mode_gfm);
online = logical(d.online);
mode01(~online) = NaN;                  % see the header: a tripped unit is NOT GFL
n_mode_masked = sum(~online(:));

% ---------------- PAGE 1: the index, as a waterfall ----------------------
f1 = pf_page_figure(opts.width_in,opts.height_in,fs,opts.font_name);
ax1 = axes(f1); hold(ax1,'on'); %#ok<LAXES>

% The two decision planes FIRST, so the traces draw over them. Each is one
% translucent patch spanning the whole converter axis and the whole horizon: the
% thresholds are system-wide constants, and drawing them per converter would
% suggest four different bands.
%
% COLOURS AND EDGES follow the deck's own switching-decision schematic: Gamma_on
% red, Gamma_off green, both as DASHED rules with the name at the right-hand end.
% That schematic is what the reader has already seen defining the two thresholds,
% so the measured page repeats its visual vocabulary rather than inventing a
% second one.
PLANE_ON  = [0.78 0.14 0.14];
PLANE_OFF = [0.11 0.47 0.20];
for pl = [struct('y',C.gamma_on,'c',PLANE_ON), struct('y',C.gamma_off,'c',PLANE_OFF)]
    patch(ax1,'XData',[xr(1) xr(2) xr(2) xr(1)], ...
        'YData',[0.5 0.5 nd+0.5 nd+0.5], ...
        'ZData',pl.y*ones(1,4),'FaceColor',pl.c,'FaceAlpha',0.11, ...
        'EdgeColor','none','HandleVisibility','off');
    % The rule itself, dashed, along the FRONT and BACK edges of the plane so the
    % level is readable at both ends of the converter axis.
    for yy = [0.5 nd+0.5]
        plot3(ax1,xr,[yy yy],pl.y*[1 1],'--','Color',pl.c, ...
            'LineWidth',0.8,'HandleVisibility','off');
    end
end

% One filled ribbon per converter, at its own y. The fill is what makes four
% overlapping traces readable in this projection; the dark upper edge is the
% signal itself and is drawn last so it is never hidden by a neighbour's fill.
col = converter_colours(nd);
for q = 1:nd
    y = q;
    s = S(:,q);
    ok = isfinite(s);
    if ~any(ok), continue; end
    tt = t(ok); ss = s(ok);
    % Closed skirt: down to zero at both ends so the ribbon has a floor.
    fill3(ax1,[tt(1); tt; tt(end)],y*ones(numel(tt)+2,1), ...
        [0; ss; 0],col(q,:),'FaceAlpha',0.32,'EdgeColor','none', ...
        'HandleVisibility','off');
    % The upper edge is the signal. Drawn in the converter's OWN colour, not a
    % darkened one: IBR_4 is black, and 0.35*black is the same black, so a
    % darkened edge would make the four traces disagree with the legend.
    plot3(ax1,tt,y*ones(size(tt)),ss,'Color',col(q,:), ...
        'LineWidth',0.9,'HandleVisibility','off');
end

view(ax1,[-37 26]);
xlim(ax1,xr); ylim(ax1,[0.5 nd+0.5]); zlim(ax1,[0 1.15]);
set(ax1,'YTick',1:nd,'YTickLabel',deck_labels,'TickLabelInterpreter','tex');
set(ax1,'ZTick',[0 0.5 1]);
set(ax1,'XTick',xt);
finish_3d(ax1,fs,FN,'{\itt} [s]','{\itIBR_i}','{\itS_i}', ...
    opts.height_in,opts.width_in,1.00);
% The two planes named where they float, at the right end of the front rule, in
% the deck schematic's own lettering: Gamma_on above its rule, Gamma_off below,
% so neither name sits on the other's plane.
plane_label(ax1,xr,C.gamma_on ,'{\it\Gamma}_{on}' ,PLANE_ON ,FN,fs-2,'bottom');
plane_label(ax1,xr,C.gamma_off,'{\it\Gamma}_{off}',PLANE_OFF,FN,fs-2,'top');

% ---------------- PAGE 2: the mode, as blocks ----------------------------
% Same canvas as page 1: see the height_in argument.
f2 = pf_page_figure(opts.width_in,opts.height_in,fs,opts.font_name);
ax2 = axes(f2); hold(ax2,'on'); %#ok<LAXES>

% The GFM ceiling, drawn once as a faint plane so the blocks have something to
% reach: it is the m = 1 level, not a threshold. Grey rather than blue, since blue
% is IBR_1's own colour on these pages.
patch(ax2,'XData',[xr(1) xr(2) xr(2) xr(1)], ...
    'YData',[0.5 0.5 nd+0.5 nd+0.5],'ZData',ones(1,4), ...
    'FaceColor',[0.55 0.55 0.55],'FaceAlpha',0.10,'EdgeColor','none', ...
    'HandleVisibility','off');
% Dashed rules at the two mode levels along the front edge, matching the deck
% schematic's own dashed vocabulary.
for zz = [0 1]
    plot3(ax2,xr,[0.5 0.5],zz*[1 1],'--','Color',[0.55 0.55 0.55], ...
        'LineWidth',0.7,'HandleVisibility','off');
end

% One solid slab per CONTIGUOUS GFM interval. Slabs rather than a stair trace
% because that is the reference layout, and because an interval of a few hundred
% milliseconds is invisible as a line but visible as a slab of finite width.
n_gfm_intervals = 0;
for q = 1:nd
    ivs = true_intervals(mode01(:,q) == 1, t);
    for j = 1:size(ivs,1)
        draw_slab(ax2,ivs(j,1),ivs(j,2),q,col(q,:));
        n_gfm_intervals = n_gfm_intervals + 1;
    end
end

view(ax2,[-37 26]);
xlim(ax2,xr); ylim(ax2,[0.5 nd+0.5]); zlim(ax2,[0 1.20]);
set(ax2,'YTick',1:nd,'YTickLabel',deck_labels,'TickLabelInterpreter','tex');
set(ax2,'ZTick',[0 1],'ZTickLabel',{'GFL (0)','GFM (1)'});
set(ax2,'XTick',xt);
% The converter axis is NAMED here, since its ticks now carry only the index.
finish_3d(ax2,fs,FN,'{\itt} [s]','{\itIBR_i}','{\itm_i}({\itt})', ...
    opts.height_in,opts.width_in,1.00);
% ---------------- export ------------------------------------------------
SHEETS = {'agsi3d',f1,'switching index per converter, with the two decision planes'; ...
          'mode3d', f2,'GFL/GFM mode per converter'};
pngs = cell(1,size(SHEETS,1));
figs = cell(1,size(SHEETS,1));
for s = 1:size(SHEETS,1)
    pngs{s} = fullfile(odir,sprintf('%s_%s.png',C.id,SHEETS{s,1}));
    pf_page_export(SHEETS{s,2},pngs{s},opts.dpi,opts.save_fig);
    if opts.save_fig
        figs{s} = fullfile(odir,sprintf('%s_%s.fig',C.id,SHEETS{s,1}));
    else
        figs{s} = '';
    end
end

page = struct();
page.id = C.id;
page.cache = C.file;
page.pngs = {pngs};
page.figs = {figs};
page.sheet_ids = {SHEETS(:,1).'};
page.sheet_subjects = {SHEETS(:,3).'};
page.device_ids_code = {d.device_ids(:).'};
page.device_labels_deck = {deck_labels_full};
page.n_samples = nt;
page.t_last = t(end);
page.t_end_requested = C.t_end_requested;
page.S_min = min(S(isfinite(S)));
page.S_max = max(S(isfinite(S)));
page.gamma_on = C.gamma_on;
page.gamma_off = C.gamma_off;
page.n_gfm_intervals = n_gfm_intervals;
page.n_mode_masked = n_mode_masked;
end

% ==========================================================================
function xt = time_ticks(xr)
%TIME_TICKS  A fixed tick set for the time axis, shared by both pages.
%   Step chosen so there are four to six labels: at 160 s that is 0, 50, 100, 150.
span = xr(2)-xr(1);
cands = [10 20 25 50 100 200 500];
step = cands(end);
for c = cands
    if span/c <= 5.5, step = c; break; end
end
xt = xr(1):step:xr(2);
end

% ==========================================================================
function iv = true_intervals(mask,t)
%TRUE_INTERVALS  Contiguous [t_start t_end] runs of a logical mask.
%   A single-sample run is given the width of one step to its neighbour, so a
%   mode change that lasted one accepted sample is still visible as a slab
%   instead of vanishing into a zero-width face.
mask = logical(mask(:));
iv = zeros(0,2);
if ~any(mask), return; end
dmask = diff([false; mask; false]);
starts = find(dmask == 1);
stops  = find(dmask == -1) - 1;
for j = 1:numel(starts)
    a = t(starts(j));
    b = t(stops(j));
    if b <= a
        nxt = min(stops(j)+1,numel(t));
        if nxt > stops(j), b = t(nxt); else, b = a + eps(a); end
    end
    iv(end+1,:) = [a b]; %#ok<AGROW>
end
end

% ==========================================================================
function draw_slab(ax,t0,t1,y,c)
%DRAW_SLAB  One GFM interval as a solid block from m = 0 up to m = 1.
%   Three faces: the front (facing the viewer), the top, and the near end. That
%   is what reads as a solid block in this projection without the cost of a
%   closed hull, and every face is a patch of the SAME interval, so the block
%   cannot disagree with itself.
w = 0.30;                       % half-depth of the slab along the converter axis
yf = y - w; yb = y + w;
FA = 0.80;
% Edges in a fixed dark grey rather than a darkened fill colour: IBR_4 is black,
% so a scaled edge would vanish into its own faces.
EC = [0.15 0.15 0.15];
% front face (at yf), top face, and the near end cap (at t0)
patch(ax,'XData',[t0 t1 t1 t0],'YData',[yf yf yf yf],'ZData',[0 0 1 1], ...
    'FaceColor',c,'FaceAlpha',FA,'EdgeColor',EC,'LineWidth',0.4, ...
    'HandleVisibility','off');
patch(ax,'XData',[t0 t1 t1 t0],'YData',[yf yf yb yb],'ZData',[1 1 1 1], ...
    'FaceColor',1-0.55*(1-c),'FaceAlpha',FA,'EdgeColor',EC, ...
    'LineWidth',0.4,'HandleVisibility','off');
patch(ax,'XData',[t0 t0 t0 t0],'YData',[yf yb yb yf],'ZData',[0 0 1 1], ...
    'FaceColor',1-0.25*(1-c),'FaceAlpha',FA,'EdgeColor',EC, ...
    'LineWidth',0.4,'HandleVisibility','off');
end

% ==========================================================================
function plane_label(ax,xr,z,txt,c,FN,fs,va)
%PLANE_LABEL  Name a decision plane at the right end of its front rule.
%   Placed on the FRONT edge (y = 0.5), where the rule ends and no ribbon runs,
%   with the caller choosing whether the name sits above or below the rule so the
%   two names never share a line.
text(ax,xr(2),0.5,z,[' ' txt], ...
    'Color',c,'FontName',FN,'FontSize',fs,'Interpreter','tex', ...
    'HorizontalAlignment','left','VerticalAlignment',va);
end

% ==========================================================================
function finish_3d(ax,fs,FN,xl,yl,zl,h_in,w_in,y_depth)
%FINISH_3D  The standing style contract, in three dimensions.
%   Same contract as the 2-D sheets -- no box, ticks outward, dashed major and
%   minor grid, Helvetica through 'tex' -- with the 3-D additions the projection
%   needs: a visible floor grid and a fixed data aspect.
%
%   The inset is computed in INCHES and then normalized, because these two pages
%   have different canvas heights: a shared normalized inset gives the shorter
%   page less absolute room and its x label falls off the bottom edge. The margins
%   below are the measured requirements at 10 pt -- 0.44 in under the axis for the
%   rotated tick labels plus the x label, and 0.56 in to the left of it for the z
%   tick labels plus the z label.
set(ax,'FontName',FN,'FontSize',fs,'Box','off','TickDir','out', ...
    'XGrid','on','YGrid','on','ZGrid','on', ...
    'GridLineStyle','--','MinorGridLineStyle','--', ...
    'XMinorGrid','off','YMinorGrid','off','ZMinorGrid','off', ...
    'GridAlpha',0.22,'TickLabelInterpreter','tex','Layer','top', ...
    'Projection','orthographic');
% y_depth is the converter axis's share of the aspect. The mode page needs more of
% it than the index page: its four y tick labels sit under one another and at the
% index page's depth they overlap.
pbaspect(ax,[2.45 y_depth 0.60]);
% Tick labels flat. MATLAB rotates 3-D tick labels to follow the projected axis,
% which tips the converter digits and the time values off the horizontal; pinned
% at 0 they read as text rather than as something to tilt the head for.
set(ax,'XTickLabelRotation',0,'YTickLabelRotation',0,'ZTickLabelRotation',0);
BOT_IN = 0.34; LEFT_IN = 0.56; TOP_IN = 0.045; RIGHT_IN = 0.09;
bot  = BOT_IN/h_in;   ht = 1 - bot - TOP_IN/h_in;
left = LEFT_IN/w_in;  wd = 1 - left - RIGHT_IN/w_in;
set(ax,'Units','normalized','Position',[left bot wd ht]);
xlabel(ax,xl,'FontName',FN,'FontSize',fs,'Interpreter','tex');
if ~isempty(yl)
    ylabel(ax,yl,'FontName',FN,'FontSize',fs,'Interpreter','tex');
end
zlabel(ax,zl,'FontName',FN,'FontSize',fs,'Interpreter','tex');
end

% ==========================================================================
function C = converter_colours(n)
%CONVERTER_COLOURS  The owner's own legend colours, in the deck's converter order.
%   Taken from the supplied reference legend (2026-09-04):
%     IBR_1 blue, IBR_2 dark grey, IBR_3 red, IBR_4 black.
%   The 2-D sheets of generate_ieee14_scenario_suite_figures now read the SAME four
%   values, so a converter has one hue on every figure of the report.
%
%   Black is a legend colour, so every derived shade in this file must survive it:
%   0.35*black is still black (the ribbon edge stays visible against the fill) and
%   1-0.65*(1-black) is mid grey (the slab's top face stays lighter than its
%   front). Both hold, so no colour needs a special case.
base = [0.00 0.16 0.70;   % IBR_1  blue
        0.32 0.32 0.32;   % IBR_2  dark grey
        0.84 0.10 0.11;   % IBR_3  red
        0.00 0.00 0.00];  % IBR_4  black
if n <= size(base,1), C = base(1:n,:); else, C = [base; lines(n-size(base,1))]; end
end

% ==========================================================================
function v = sig_num(sig,name)
v = NaN;
if isstruct(sig) && isfield(sig,name) && isscalar(sig.(name)) && ...
        isnumeric(sig.(name))
    v = double(sig.(name));
end
end

function v = num_or(s,name,default)
v = default;
if isstruct(s) && isfield(s,name) && isscalar(s.(name)) && isnumeric(s.(name))
    v = double(s.(name));
end
end

% ==========================================================================
function write_provenance(odir,out)
%WRITE_PROVENANCE  Plain-text manifest beside the pages.
%   Same shape as the suite generator's: a header, then one block per scenario
%   naming each page with its SHA-256, mtime and the cache it came from, so a
%   reader holding one slide can tell which trajectory produced it.
p = fullfile(odir,'provenance_agsi_mode_3d.txt');
fid = fopen(p,'w');
if fid < 0
    warning('generate_ieee14_agsi_mode_3d:provenanceUnwritable', ...
        'Could not write %s; the figures are still valid.',p);
    return;
end
fprintf(fid,'generator: scripts/reporting/generate_ieee14_agsi_mode_3d.m\n');
fprintf(fid,'schema:    %s\n',out.schema);
fprintf(fid,'generated: %s\n',out.generated_utc);
fprintf(fid,'caches:    %s\n',out.cache_dir);
fprintf(fid,'style:     %g in x %g in, %s %g pt, tex interpreter, %s grid, box off, ticks out\n', ...
    out.style.width_in,out.style.height_in, ...
    out.style.font_name,out.style.font_size,out.style.grid);
fprintf(fid,'\n');
fprintf(fid,['TWO PAGES per scenario, both three-dimensional with the converter ' ...
    'axis to the left\n  and time to the right:\n' ...
    '    _agsi3d  S_i(t) per converter as a filled ribbon, with the two ' ...
    'decision planes\n             Gamma_on and Gamma_off floating across the ' ...
    'whole horizon\n' ...
    '    _mode3d  m_i(t) per converter: one solid slab per contiguous ' ...
    'grid-forming interval\n\n']);
fprintf(fid,['Pure cache reader. Nothing is simulated, re-solved, smoothed, ' ...
    'filtered, decimated,\n  clipped, offset, interpolated or padded: every ' ...
    'plotted sample is a raw accepted\n  value from the stored trajectory.\n\n']);
fprintf(fid,['SYMBOLS. The reference layout letters the index AGSI_i with ' ...
    'thresholds AGSI_up and\n  AGSI_down. These pages letter them S_i, ' ...
    'Gamma_on and Gamma_off -- the names the deck\n  defines and the kernel ' ...
    'uses (S is formed at ts_simulate_ibr_hybrid.m:2973; the two\n  thresholds ' ...
    'are the run options severity_gamma_on/off). The form is the reference''s;\n' ...
    '  the names are the ones already defined elsewhere in the deck.\n\n']);
fprintf(fid,['The MODE trace is MASKED to NaN wherever a converter is out of ' ...
    'service.\n  device_modes_history holds "tripped" for such a device and a ' ...
    'bare "is it gfm" test\n  reads that as 0, which on this axis is the GFL ' ...
    'level -- an unmasked page would draw\n  a departed converter as one that ' ...
    'is following the grid. A masked stretch carries no\n  slab at all, which ' ...
    'is the honest picture; the masked count is per scenario below.\n\n']);
fprintf(fid,['The x axis spans the REQUESTED horizon, not the last accepted ' ...
    'sample: cropping to\n  the data would draw a truncated run as a finished ' ...
    'one.\n\n']);
fprintf(fid,'--------------------------------------------------------------\n');
for k = 1:numel(out.pages)
    g = out.pages(k);
    fprintf(fid,'%s\n',g.id);
    fprintf(fid,'  cache      %s\n',g.cache);
    if isfile(g.cache)
        fprintf(fid,'  cache_sha  %s\n',sha256_of(g.cache));
    end
    ids = g.sheet_ids{1}; subs = g.sheet_subjects{1};
    pngs = g.pngs{1}; figs = g.figs{1};
    for s = 1:numel(ids)
        fprintf(fid,'  page       %-7s %s\n',ids{s},subs{s});
        for a = {pngs{s},figs{s}}
            if isempty(a{1}), continue; end
            if isfile(a{1})
                dd = dir(a{1});
                fprintf(fid,'    file     %s\n',a{1});
                fprintf(fid,'      sha256 %s\n',sha256_of(a{1}));
                fprintf(fid,'      mtime  %s\n',char(datetime(dd.datenum, ...
                    'ConvertFrom','datenum','Format','yyyy-MM-dd HH:mm:ss')));
                fprintf(fid,'      bytes  %d\n',dd.bytes);
            else
                fprintf(fid,'    file     %s (MISSING)\n',a{1});
            end
        end
    end
    fprintf(fid,'  horizon    %.6f s of %.6f s requested\n', ...
        g.t_last,g.t_end_requested);
    fprintf(fid,'  thresholds Gamma_on=%.4f Gamma_off=%.4f\n', ...
        g.gamma_on,g.gamma_off);
    fprintf(fid,'  S range    [%.6f %.6f] over %d sample(s)\n', ...
        g.S_min,g.S_max,g.n_samples);
    fprintf(fid,'  GFM        %d contiguous interval(s) drawn\n',g.n_gfm_intervals);
    fprintf(fid,'  masked     %d mode sample(s) (converter offline)\n', ...
        g.n_mode_masked);
    fprintf(fid,'  labels     deck %s = code %s\n', ...
        strjoin(g.device_labels_deck{1},', '), ...
        strjoin(g.device_ids_code{1},', '));
    fprintf(fid,'\n');
end
fclose(fid);
fprintf('wrote %s\n',p);
end

% ==========================================================================
function sha = sha256_of(f)
sha = '';
try
    d = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(f,'r');
    if fid < 0, return; end
    while true
        b = fread(fid,1048576,'*uint8');
        if isempty(b), break; end
        d.update(b);
    end
    fclose(fid);
    sha = lower(reshape(dec2hex(typecast(d.digest(),'uint8')).',1,[]));
catch
    sha = '';
end
end
