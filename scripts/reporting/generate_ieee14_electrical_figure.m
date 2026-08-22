function out = generate_ieee14_electrical_figure(opts)
%GENERATE_IEEE14_ELECTRICAL_FIGURE  Eight-panel electrical response, one arm.
%
%   generate_ieee14_electrical_figure(result_file="...", output="...")
%
% Eight panels on one page, one shared time axis, identical event markers on
% every panel:
%
%   (a) P            (b) Q            (c) i_d          (d) i_q
%   (e) f            (f) theta        (g) |V| at PCC   (h) min |V| network
%
% Panels (a)-(g) carry the four converters plus the synchronous machine as a
% black dashed overlay. Panel (h) is the network minimum voltage, a single
% system-wide scalar with no per-machine counterpart, so it carries one trace by
% definition rather than by omission.
%
% The panel geometry deliberately reproduces
% generate_switch_new_report_figures.m:431-496 so the two pages are visually
% comparable; the additions are the event markers and the SG trace on panel (g).
%
% Every plotted sample is a raw accepted value. Nothing is smoothed, filtered,
% decimated, clipped, offset, interpolated, or augmented with synthetic noise.
%
% Classification: presentation only.

arguments
    opts.result_file (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_gfm_lock_compare','adaptive_250s.mat')
    opts.output (1,1) string = fullfile('docs','source','figures', ...
        'switch_ieee14_decision','electrical_adaptive.png')
    opts.arm_label (1,1) string = ""
    opts.window (1,2) double = [-Inf Inf]
    opts.width_in (1,1) double = 6.20
    opts.height_in (1,1) double = 7.90
    opts.font_size (1,1) double = 11
    opts.dpi (1,1) double = 300
    % Off by default: the report caption already names the arm and states the
    % no-synthetic-signal contract, so an in-figure title block repeats it and
    % spends vertical space the eight panels can use instead. Set title=true for
    % a standalone copy of the page that will be read outside the report.
    opts.title (1,1) logical = false
end

pf_init_paths();
r = load_result(opts.result_file);
e = ieee14_switch_electrical_signals(r);
M = ieee14_switch_event_marks(r,t_end=requested_horizon(r));

win = opts.window;
if ~isfinite(win(1)), win(1) = M.t_range(1); end
if ~isfinite(win(2)), win(2) = M.t_range(2); end

FS = opts.font_size;
FN = 'Times New Roman';
nd = numel(e.device_ids);
col = lines(nd);
SGC = [0 0 0];

f = pf_page_figure(opts.width_in,opts.height_in,FS);
tl = tiledlayout(f,4,2,'TileSpacing','compact','Padding','compact');

P = e.panels;
h = gobjects(1,nd+1);
in_win = e.t >= win(1) & e.t <= win(2);
for k = 1:numel(P)
    ax = nexttile(tl); hold(ax,'on');
    Y = e.(P(k).field)*P(k).scale;
    if size(Y,2) == nd
        for q = 1:nd
            hh = plot(ax,e.t,Y(:,q),'-','Color',col(q,:),'LineWidth',0.9);
            if k == 1, h(q) = hh; end
        end
    else
        hh = plot(ax,e.t,Y,'-','Color',[0.15 0.15 0.15],'LineWidth',1.0);
    end
    lo = min(Y(in_win,:),[],'all'); hi = max(Y(in_win,:),[],'all');
    if ~isempty(P(k).sg_field)
        S = e.(P(k).sg_field)*P(k).scale;
        hh = plot(ax,e.t,S,'--','Color',SGC,'LineWidth',1.0);
        if k == 1, h(nd+1) = hh; end
        lo = min(lo,min(S(in_win))); hi = max(hi,max(S(in_win)));
    end
    % Autoscale to the WINDOW. Nothing is clipped: out-of-window samples are
    % simply off-screen, and the full-horizon page shows them.
    if isfinite(lo) && isfinite(hi)
        pad = 0.06*max(hi-lo,eps);
        ylim(ax,[lo-pad hi+pad]);
    end
    bottom = k >= numel(P)-1;
    grid(ax,'on'); box(ax,'on');
    set(ax,'FontName',FN,'FontSize',FS-1,'GridAlpha',0.12);
    title(ax,sprintf('%s %s',P(k).tag,P(k).title), ...
        'FontName',FN,'FontSize',FS-2,'FontWeight','normal');
    ylabel(ax,P(k).ylabel,'FontName',FN,'FontSize',FS-1);
    if bottom
        xlabel(ax,'{\itt} [s]','FontName',FN,'FontSize',FS-1);
    end
    % Lines without labels. Each panel here is half a page wide, so a full set
    % of chronology names collides with itself horizontally and lies over the
    % traces the panel exists to show. The severity page names every instant
    % once, on a panel that reserves a band for it; repeating the names here buys
    % nothing and costs legibility.
    pf_draw_marks(ax,M,labels=false,label_families=["disturbance"], ...
        font_size=FS-4,window=win);
end

lbl = cell(1,nd+1);
for q = 1:nd
    lbl{q} = sprintf('%s (bus %g)',e.device_ids{q},e.device_bus_ids(q));
end
lbl{nd+1} = sprintf('%s (bus %g)',e.sg_id_label,e.sg_bus);
lg = legend(h,lbl,'Orientation','horizontal','NumColumns',nd+1,'Box','off');
lg.Layout.Tile = 'north';
set(lg,'FontName',FN,'FontSize',FS-2);

axall = findall(f,'Type','axes');
linkaxes(axall,'x');
xlim(axall(1),win);
for k = 1:numel(axall)
    xl = get(axall(k),'XLabel');
    if isempty(get(xl,'String')), set(axall(k),'XTickLabel',[]); end
end

if opts.title
    arm = char(opts.arm_label);
    if isempty(arm), arm = 'IEEE 14-bus EECON49 chronology'; end
    sgtitle(f,sprintf(['Electrical response --- %s\n' ...
        '\\rm\\fontsize{%d}{}raw accepted samples; no smoothing, ' ...
        'filtering, decimation, clipping or synthetic noise'],arm,FS-4), ...
        'FontName',FN,'FontSize',FS-1,'FontWeight','bold','Interpreter','tex');
end

pf_page_export(f,opts.output,opts.dpi);

out = struct();
out.output = char(opts.output);
out.result_file = char(opts.result_file);
out.n_samples = numel(e.t);
out.n_devices = nd;
out.window = win;
out.provenance = e.provenance;
end

% ==========================================================================
function r = load_result(file)
p = char(file);
if ~isfile(p)
    error('generate_ieee14_electrical_figure:missingResult', ...
        'No stored result at %s.',p);
end
S = load(p);
if isfield(S,'result'), r = S.result;
elseif isfield(S,'r'), r = S.r;
else
    error('generate_ieee14_electrical_figure:badResultFile', ...
        '%s contains neither "result" nor "r".',p);
end
end

function t_end = requested_horizon(r)
t_end = NaN;
if isfield(r,'sched') && isstruct(r.sched) && isfield(r.sched,'t_end')
    t_end = r.sched.t_end;
end
end
