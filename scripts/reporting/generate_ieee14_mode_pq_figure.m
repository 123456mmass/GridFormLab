function out = generate_ieee14_mode_pq_figure(opts)
%GENERATE_IEEE14_MODE_PQ_FIGURE  Severity + mode + reference owner + P and Q.
%
%   generate_ieee14_mode_pq_figure(result_file="...", output="...")
%
% Five stacked panels on one page, reading top to bottom as cause then effect:
%
%   (a) severity     the AGSI decision variable S with both thresholds
%   mode strip       GFL/GFM of each converter -- what the supervisor DECIDED
%   reference owner  which single device holds the island angle reference
%   (b)              per-converter active power   -- what the network DID
%   (c)              per-converter reactive power
%
% The severity panel is the top panel because it is the only quantity on the page
% that CAUSES anything: the mode strip immediately below it is its consequence.
% It also hosts the event labels, in a band reserved above S = 1, so the names of
% the chronology instants are readable without any label lying over a trace.
%
% Mode and reference ownership are SEPARATE contracts: several converters can be
% grid-forming at once, but exactly one owns the angle reference. The owner trace
% is therefore read from the accepted hybrid-state history, never inferred from
% "the first grid-forming unit".
%
% The mode strip carries NO display offset. Where several converters share a
% level their traces coincide exactly, which is the honest picture of a
% synchronous mode change; a nudge would invent a difference that is not there.
%
% Every plotted sample is a raw accepted value. The severity axis is drawn to
% 1.85 so that the label band clears the saturation ceiling S = 1; no sample is
% outside [0,1] and none is hidden.
%
% Classification: presentation only.

arguments
    opts.result_file (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_gfm_lock_compare','adaptive_250s.mat')
    opts.output (1,1) string = fullfile('docs','source','figures', ...
        'switch_ieee14_decision','mode_switch_PQ.png')
    opts.font_name (1,1) string = "Times New Roman"
    opts.font_size (1,1) double = 12
    opts.width_in (1,1) double = 6.20
    opts.height_in (1,1) double = 7.80
    opts.dpi (1,1) double = 300
    opts.labels (1,1) logical = true
    opts.label_families (1,:) string = ["disturbance","supervisor"]
    opts.gamma_on (1,1) double = 0.65
    opts.gamma_off (1,1) double = 0.35
end

pf_init_paths();
r = load_result(opts.result_file);
e = ieee14_switch_electrical_signals(r);
d = ieee14_switch_decision_signals(r,gamma_on=opts.gamma_on, ...
    gamma_off=opts.gamma_off);
M = ieee14_switch_event_marks(r,t_end=requested_horizon(r));

FS = opts.font_size;
FN = char(opts.font_name);
t = e.t;
tmax = M.t_range(2);
nibr = numel(e.device_ids);
col = {[0 0.447 0.741],[0.85 0.325 0.098],[0.929 0.694 0.125],[0 0 0]};
lst = {'-','--','-','-'};
lwd = [1.1 1.3 1.0 1.0];
lbl = cell(1,nibr);
for j = 1:nibr
    lbl{j} = sprintf('IBR_%d (bus %g)',j,e.device_bus_ids(j));
end

figW = opts.width_in; figH = opts.height_in;
f = pf_page_figure(figW,figH,FS,FN);
x0 = 0.90/figW; aw = 5.05/figW;

% ---- (a) severity, with the event-label band above S = 1 ----------------
S_TOP = 1.85;
axS = axes('Parent',f,'Units','normalized', ...
    'Position',[x0, 6.34/figH, aw, 1.00/figH]); hold(axS,'on');
% S is a PER-DEVICE quantity: J_f is common but J_V is each converter's own
% terminal deviation. Drawing it in the device colours of the legend above keeps
% the page consistent and lets a reader see which unit crossed first.
nS = size(d.S,2);
for j = 1:nS
    cj = col{min(j,numel(col))};
    sj = lst{min(j,numel(lst))};
    wj = lwd(min(j,numel(lwd)));
    plot(axS,t,d.S(:,j),sj,'Color',cj,'LineWidth',wj);
end
yline(axS,opts.gamma_on,'-','Color',[0.75 0.10 0.10],'LineWidth',0.9, ...
    'Alpha',1,'HandleVisibility','off');
yline(axS,opts.gamma_off,'-','Color',[0.10 0.45 0.75],'LineWidth',0.9, ...
    'Alpha',1,'HandleVisibility','off');
text(axS,tmax,opts.gamma_on,sprintf('\\Gamma_{on}=%.2f ',opts.gamma_on), ...
    'HorizontalAlignment','right','VerticalAlignment','bottom', ...
    'FontName',FN,'FontSize',FS-3,'Color',[0.75 0.10 0.10]);
text(axS,tmax,opts.gamma_off,sprintf('\\Gamma_{off}=%.2f ',opts.gamma_off), ...
    'HorizontalAlignment','right','VerticalAlignment','top', ...
    'FontName',FN,'FontSize',FS-3,'Color',[0.10 0.45 0.75]);
grid(axS,'on');
set(axS,'XLim',[0 tmax],'YLim',[-0.05 S_TOP],'YTick',[0 0.35 0.65 1], ...
    'FontName',FN,'FontSize',FS-1,'Box','on','XTickLabel',[], ...
    'TickDir','out','Layer','top','GridAlpha',0.15);
ylabel(axS,'{\itS}(t)','FontName',FN,'FontSize',FS);
text(axS,0.012,0.93,'(a)','Units','normalized','FontName',FN,'FontSize',FS);
% No strip titles on this page. The panel tag and the y label name each strip
% and the caption carries the rest; an in-figure sentence that repeats the
% caption is text a paper does not print.
pf_draw_marks(axS,M,labels=opts.labels,label_families=opts.label_families, ...
    font_size=FS-4,window=[0 tmax],label_band=[0.62 0.98]);

% ---- mode strip ---------------------------------------------------------
axM = axes('Parent',f,'Units','normalized', ...
    'Position',[x0, 5.54/figH, aw, 0.66/figH]); hold(axM,'on');
for j = 1:nibr
    stairs(axM,t,double(d.mode_gfm(:,j)),lst{j},'Color',col{j}, ...
        'LineWidth',lwd(j));
end
set(axM,'XLim',[0 tmax],'YLim',[-0.25 1.25],'YTick',[0 1], ...
    'YTickLabel',{'GFL','GFM'},'FontName',FN,'FontSize',FS,'Box','on', ...
    'XTickLabel',[],'TickDir','out','Layer','top','GridAlpha',0.15);
grid(axM,'on');
ylabel(axM,'mode','FontName',FN,'FontSize',FS);
pf_draw_marks(axM,M,labels=false,window=[0 tmax]);

% ---- reference owner ----------------------------------------------------
axR = axes('Parent',f,'Units','normalized', ...
    'Position',[x0, 4.66/figH, aw, 0.70/figH]); hold(axR,'on');
refcol = [0.35 0.15 0.55];
stairs(axR,t,d.ref_code,'-','Color',refcol,'LineWidth',1.6);
label_owner_segments(axR,t,d.ref_code,tmax,FN,FS,refcol);
set(axR,'XLim',[0 tmax],'YLim',[-0.6 nibr+0.6],'YTick',0:nibr, ...
    'YTickLabel',[{'SG'} compose('IBR_%d',1:nibr)],'FontName',FN, ...
    'FontSize',FS-2,'Box','on','XTickLabel',[],'TickDir','out','Layer','top');
ylabel(axR,'ref. owner','FontName',FN,'FontSize',FS-1);
pf_draw_marks(axR,M,labels=false,window=[0 tmax]);

% ---- (b) active power, (c) reactive power -------------------------------
% Event lines only, no labels: panel (a) names every instant once, and a second
% set of names laid over these curves would obscure the quantity the panel exists
% to show.
axA = panel(f,[x0, 2.60/figH, aw, 1.90/figH],t,e.P,col,lst,lwd,tmax, ...
    '{\itP_i} [pu]','(b)',FN,FS,false);
pf_draw_marks(axA,M,labels=false,window=[0 tmax]);
axB = panel(f,[x0, 0.72/figH, aw, 1.75/figH],t,e.Q,col,lst,lwd,tmax, ...
    '{\itQ_i} [pu]','(c)',FN,FS,true);
pf_draw_marks(axB,M,labels=false,window=[0 tmax]);

lg = legend(axA,lbl,'Orientation','horizontal','Box','off', ...
    'FontName',FN,'FontSize',FS-2);
lg.Units = 'normalized';
lg.Position = [x0, 7.50/figH, aw, 0.17/figH];

pf_page_export(f,opts.output,opts.dpi);

out = struct();
out.output = char(opts.output);
out.result_file = char(opts.result_file);
out.n_samples = numel(t);
out.t_max = tmax;
out.mode_offset = 0;
out.n_marks = numel(M.marks);
out.n_mark_groups = M.n_groups;
out.severity_axis_top = S_TOP;
out.severity_max = max(d.S(isfinite(d.S)));
out.provenance = e.provenance;
end

% ==========================================================================
function ax = panel(f,pos,t,Y,col,lst,lwd,tmax,ylab,tag,FN,FS,want_x)
ax = axes('Parent',f,'Units','normalized','Position',pos); hold(ax,'on');
for j = 1:size(Y,2)
    plot(ax,t,Y(:,j),lst{j},'Color',col{j},'LineWidth',lwd(j));
end
grid(ax,'on'); box(ax,'on');
set(ax,'XLim',[0 tmax],'FontName',FN,'FontSize',FS,'GridAlpha',0.15, ...
    'TickDir','out');
ylabel(ax,ylab,'FontName',FN,'FontSize',FS);
if want_x
    xlabel(ax,'{\itt} [s]','FontName',FN,'FontSize',FS);
else
    set(ax,'XTickLabel',[]);
end
text(ax,0.012,0.93,tag,'Units','normalized','FontName',FN,'FontSize',FS);
end

% ==========================================================================
function label_owner_segments(ax,t,rc,tmax,FN,FS,colr)
%LABEL_OWNER_SEGMENTS  One in-axes label per contiguous ownership segment.
rc = rc(:); t = t(:);
dd = [true; diff(rc) ~= 0];
s0 = find(dd);
s1 = [s0(2:end)-1; numel(rc)];
for s = 1:numel(s0)
    val = rc(s0(s));
    if val < 0, continue; end
    if t(s1(s)) - t(s0(s)) < 0.03*tmax, continue; end   % skip slivers
    tm = mean([t(s0(s)) t(s1(s))]);
    if val == 0, nm = 'SG'; else, nm = sprintf('IBR_%d',val); end
    text(ax,tm,val+0.34,nm,'HorizontalAlignment','center', ...
        'FontName',FN,'FontSize',FS-3,'Color',colr);
end
end

% ==========================================================================
function r = load_result(file)
p = char(file);
if ~isfile(p)
    error('generate_ieee14_mode_pq_figure:missingResult', ...
        'No stored result at %s.',p);
end
S = load(p);
if isfield(S,'result'), r = S.result;
elseif isfield(S,'r'), r = S.r;
else
    error('generate_ieee14_mode_pq_figure:badResultFile', ...
        '%s contains neither "result" nor "r".',p);
end
end

function t_end = requested_horizon(r)
t_end = NaN;
if isfield(r,'sched') && isstruct(r.sched) && isfield(r.sched,'t_end')
    t_end = r.sched.t_end;
end
end
