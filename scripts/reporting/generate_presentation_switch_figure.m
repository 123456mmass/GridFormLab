function out = generate_presentation_switch_figure(opts)
%GENERATE_PRESENTATION_SWITCH_FIGURE  Slide-native figures for the PF/SSSA/TS/GFM deck.
%
%   generate_presentation_switch_figure()
%
% Reads the delivered arm caches under
% output/diagnostics/ieee14_gfm_lock_compare_zeta/ and emits three figures into
% docs/source/figures/presentation_pf_sssa_ts_gfm/:
%
%   slide_supervisor.png   the supervisor's decision over the whole 250 s run:
%                          (a) severity index per converter against both
%                          thresholds, (b) which converters are grid-forming,
%                          (c) who owns the island angle reference.
%   slide_electrical.png   the electrical response over the same axis: active
%                          and reactive power per converter, centre-of-inertia
%                          frequency, and the network minimum voltage.
%   slide_necessity.png    frequency over the islanding window for three
%                          control policies -- adaptive, all-four pinned, and
%                          every converter locked grid-following.
%
% WHY THESE ARE NOT THE REPORT FIGURES. The report figures are sized for a
% report page: 6.20 in wide by 7.6-8.4 in tall, lettered at 11 pt to match the
% report body. A 16:9 slide has about 2.9 in of usable height, so including a
% report figure on a slide requires scaling it to about a third of its size,
% which shrinks its lettering to about 4 pt and breaks the AGENTS.md contract
% that figure lettering match the body text in typeface AND size. These figures
% are therefore drawn at slide dimensions and lettered at the deck's own body
% size, and are included at 1:1 with \includegraphics[width=<width_in>in].
%
% This is a pure cache reader: no simulation is run here, nothing is written
% back to the caches, and every trace is drawn from the stored result exactly as
% delivered. An arm that stops is drawn stopping -- nothing is extended,
% interpolated or padded.
%
% Classification: presentation only over production runs (ASSUMED_DIAGNOSTIC).

arguments
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_gfm_lock_compare_zeta')
    opts.figure_dir (1,1) string = fullfile('docs','source','figures', ...
        'presentation_pf_sssa_ts_gfm')
    opts.width_in (1,1) double = 5.90
    opts.font_size (1,1) double = 10
    opts.dpi (1,1) double = 300
    opts.necessity_window (1,2) double = [18 30]
end

pf_init_paths();

C = char(opts.cache_dir);
F = char(opts.figure_dir);
if ~isfolder(F), mkdir(F); end

r = load_arm(C,'adaptive');

out = struct();
out.supervisor = draw_supervisor(r,F,opts);
out.electrical = draw_electrical(r,F,opts);
out.necessity  = draw_necessity(C,F,opts);
out.width_in = opts.width_in;
out.font_size = opts.font_size;
out.dpi = opts.dpi;
end

% =========================================================================
function r = load_arm(cache_dir,id)
file = fullfile(cache_dir,[id '_250s.mat']);
assert(isfile(file),'generate_presentation_switch_figure:missingCache', ...
    'Arm cache not found: %s',file);
S = load(file);
r = S.result;
end

% =========================================================================
function png = draw_supervisor(r,F,opts)
%DRAW_SUPERVISOR  Severity index, committed mode, and reference owner.
h_in = 2.55;
f = pf_page_figure(opts.width_in,h_in,opts.font_size);
tl = tiledlayout(f,3,1,'TileSpacing','tight','Padding','tight');

t = r.t(:);
sev = severity_index(r);
nd = size(sev,2);
col = converter_colours(nd);

% --- (a) severity index -------------------------------------------------
ax = nexttile(tl);
hold(ax,'on');
for k = 1:nd
    plot(ax,t,sev(:,k),'Color',col(k,:),'LineWidth',0.9);
end
yline(ax,0.65,'-','Color',[0.75 0.10 0.10],'LineWidth',0.8);
yline(ax,0.35,'-','Color',[0.10 0.35 0.75],'LineWidth',0.8);
text(ax,246,0.72,'\Gamma_{on}=0.65','Color',[0.75 0.10 0.10], ...
    'FontName','Times New Roman','FontSize',opts.font_size-2, ...
    'HorizontalAlignment','right','VerticalAlignment','bottom');
text(ax,246,0.28,'\Gamma_{off}=0.35','Color',[0.10 0.35 0.75], ...
    'FontName','Times New Roman','FontSize',opts.font_size-2, ...
    'HorizontalAlignment','right','VerticalAlignment','top');
ylim(ax,[0 1.12]);
set(ax,'YTick',[0 0.35 0.65 1]);
ylabel(ax,'severity {\itS}');
grid(ax,'on'); box(ax,'on');
set(ax,'XTickLabel',[]);
xlim(ax,[0 250]);
lg = legend(ax,converter_labels(r,nd),'Orientation','horizontal', ...
    'FontSize',opts.font_size-2.5,'Box','off');
lg.Layout.Tile = 'north';

% --- (b) committed mode -------------------------------------------------
ax = nexttile(tl);
hold(ax,'on');
modes = r.device_modes_history;
ibr = converter_rows(r);
for k = 1:numel(ibr)
    m = double(strcmpi(modes(ibr(k),:),'gfm')).';
    stairs(ax,t,m,'Color',col(k,:),'LineWidth',0.9);
end
ylim(ax,[-0.25 1.25]);
set(ax,'YTick',[0 1],'YTickLabel',{'follow','form'},'XTickLabel',[]);
ylabel(ax,'mode');
grid(ax,'on'); box(ax,'on');
xlim(ax,[0 250]);

% --- (c) reference owner ------------------------------------------------
ax = nexttile(tl);
code = owner_code(r);
stairs(ax,t,code,'Color',[0.25 0.10 0.55],'LineWidth',1.1);
nvis = max(1,max(code));
ylim(ax,[-0.4 nvis+0.4]);
set(ax,'YTick',0:nvis,'YTickLabel',owner_labels(r,nvis));
ylabel(ax,'reference');
xlabel(ax,'{\itt} [s]');
grid(ax,'on'); box(ax,'on');
xlim(ax,[0 250]);

png = fullfile(F,'slide_supervisor.png');
pf_page_export(f,png,opts.dpi);
end

% =========================================================================
function png = draw_electrical(r,F,opts)
%DRAW_ELECTRICAL  Power per converter, system frequency, network voltage.
h_in = 2.55;
f = pf_page_figure(opts.width_in,h_in,opts.font_size);
tl = tiledlayout(f,2,2,'TileSpacing','tight','Padding','tight');

t = r.t(:);
ibr = converter_rows(r);
nd = numel(ibr);
col = converter_colours(nd);
sg = setdiff(1:size(r.device_P_pu,1),ibr);

% --- active power -------------------------------------------------------
ax1 = nexttile(tl);
hold(ax1,'on');
for k = 1:nd
    plot(ax1,t,r.device_P_pu(ibr(k),:),'Color',col(k,:),'LineWidth',0.9);
end
if ~isempty(sg)
    plot(ax1,t,r.device_P_pu(sg(1),:),'k--','LineWidth',0.9);
end
ylabel(ax1,'{\itP} [pu]'); grid(ax1,'on'); box(ax1,'on');
xlim(ax1,[0 250]); set(ax1,'XTickLabel',[]);
title(ax1,'(a) active power','FontWeight','normal', ...
    'FontSize',opts.font_size-1);

% Shared legend across top.  The compact labels preserve full text at the
% physical 5.90 in slide width; the caption identifies these as converters.
lbls = cell(1,nd);
for k = 1:nd
    lbls{k} = sprintf('bus %d',r.device_bus_ids(ibr(k)));
end
if ~isempty(sg)
    lbls = [lbls, {'SG'}];
end
lg = legend(ax1,lbls,'Orientation','horizontal', ...
    'FontSize',opts.font_size-2.5,'Box','off');
lg.Layout.Tile = 'north';

% --- reactive power -----------------------------------------------------
ax2 = nexttile(tl);
hold(ax2,'on');
for k = 1:nd
    plot(ax2,t,r.device_Q_pu(ibr(k),:),'Color',col(k,:),'LineWidth',0.9);
end
if ~isempty(sg)
    plot(ax2,t,r.device_Q_pu(sg(1),:),'k--','LineWidth',0.9);
end
ylabel(ax2,'{\itQ} [pu]'); grid(ax2,'on'); box(ax2,'on');
xlim(ax2,[0 250]); set(ax2,'XTickLabel',[]);
title(ax2,'(b) reactive power','FontWeight','normal', ...
    'FontSize',opts.font_size-1);

% --- COI frequency ------------------------------------------------------
ax3 = nexttile(tl);
plot(ax3,t,r.coi_frequency_Hz(:),'Color',[0.00 0.24 0.75],'LineWidth',1.0);
yline(ax3,60,':','Color',[0.45 0.45 0.45],'LineWidth',0.8);
ylabel(ax3,'{\itf}_{COI} [Hz]'); xlabel(ax3,'{\itt} [s]');
grid(ax3,'on'); box(ax3,'on'); xlim(ax3,[0 250]);
title(ax3,'(c) system frequency','FontWeight','normal', ...
    'FontSize',opts.font_size-1);

% --- network minimum voltage -------------------------------------------
ax4 = nexttile(tl);
plot(ax4,t,min(r.bus_voltage_magnitude,[],1),'Color',[0.18 0.55 0.34], ...
    'LineWidth',1.0);
ylabel(ax4,'min|{\itV}| [pu]'); xlabel(ax4,'{\itt} [s]');
grid(ax4,'on'); box(ax4,'on'); xlim(ax4,[0 250]);
title(ax4,'(d) network minimum voltage','FontWeight','normal', ...
    'FontSize',opts.font_size-1);

png = fullfile(F,'slide_electrical.png');
pf_page_export(f,png,opts.dpi);
end

% =========================================================================
function png = draw_necessity(C,F,opts)
%DRAW_NECESSITY  Multi-signal comparison over islanding window (P, Q, f, V).
arms = { ...
  'adaptive',    'adaptive switching',    [0.00 0.24 0.75], '-'; ...
  'pinned_gfm4', 'all four pinned',       [0.49 0.18 0.56], '-'; ...
  'locked_gfl',  'none allowed to form',  [0.20 0.20 0.20], '--'};

w0 = opts.necessity_window(1); w1 = opts.necessity_window(2);
h_in = 2.55;
f = pf_page_figure(opts.width_in,h_in,opts.font_size);
tl = tiledlayout(f,2,2,'TileSpacing','tight','Padding','tight');

t_trip = 20;

% Panel (a): COI Frequency
ax1 = nexttile(tl);
hold(ax1,'on');
for k = 1:size(arms,1)
    r = load_arm(C,arms{k,1});
    t = r.t(:); sig = r.coi_frequency_Hz(:);
    w = t >= w0 & t <= w1 & isfinite(sig);
    plot(ax1,t(w),sig(w),'Color',arms{k,3},'LineStyle',arms{k,4}, ...
        'LineWidth',1.2,'DisplayName',arms{k,2});
    if strcmp(arms{k,1},'locked_gfl')
        idx = find(w);
        if ~isempty(idx)
            plot(ax1,t(idx(end)),sig(idx(end)),'x','Color',arms{k,3}, ...
                'MarkerSize',7,'LineWidth',1.4,'HandleVisibility','off');
        end
    end
end
xline(ax1,t_trip,':','Color',[0.45 0.45 0.45],'LineWidth',0.8,'HandleVisibility','off');
grid(ax1,'on'); box(ax1,'on'); xlim(ax1,[w0 w1]);
ylabel(ax1,'{\itf}_{COI} [Hz]'); set(ax1,'XTickLabel',[]);
title(ax1,'(a) system frequency','FontWeight','normal','FontSize',opts.font_size-1);

% Shared Legend
lg = legend(ax1,'Orientation','horizontal','FontSize',opts.font_size-2.5,'Box','off');
lg.Layout.Tile = 'north';

% Panel (b): Total Active Power
ax2 = nexttile(tl);
hold(ax2,'on');
for k = 1:size(arms,1)
    r = load_arm(C,arms{k,1});
    t = r.t(:);
    sig = sum(r.device_P_pu, 1).';
    w = t >= w0 & t <= w1 & isfinite(sig);
    plot(ax2,t(w),sig(w),'Color',arms{k,3},'LineStyle',arms{k,4}, ...
        'LineWidth',1.2,'HandleVisibility','off');
    if strcmp(arms{k,1},'locked_gfl')
        idx = find(w);
        if ~isempty(idx)
            plot(ax2,t(idx(end)),sig(idx(end)),'x','Color',arms{k,3}, ...
                'MarkerSize',7,'LineWidth',1.4,'HandleVisibility','off');
        end
    end
end
xline(ax2,t_trip,':','Color',[0.45 0.45 0.45],'LineWidth',0.8);
grid(ax2,'on'); box(ax2,'on'); xlim(ax2,[w0 w1]);
ylabel(ax2,'\Sigma{\itP} [pu]'); set(ax2,'XTickLabel',[]);
title(ax2,'(b) total active power','FontWeight','normal','FontSize',opts.font_size-1);

% Panel (c): Total Reactive Power
ax3 = nexttile(tl);
hold(ax3,'on');
for k = 1:size(arms,1)
    r = load_arm(C,arms{k,1});
    t = r.t(:);
    sig = sum(r.device_Q_pu, 1).';
    w = t >= w0 & t <= w1 & isfinite(sig);
    plot(ax3,t(w),sig(w),'Color',arms{k,3},'LineStyle',arms{k,4}, ...
        'LineWidth',1.2,'HandleVisibility','off');
    if strcmp(arms{k,1},'locked_gfl')
        idx = find(w);
        if ~isempty(idx)
            plot(ax3,t(idx(end)),sig(idx(end)),'x','Color',arms{k,3}, ...
                'MarkerSize',7,'LineWidth',1.4,'HandleVisibility','off');
        end
    end
end
xline(ax3,t_trip,':','Color',[0.45 0.45 0.45],'LineWidth',0.8);
grid(ax3,'on'); box(ax3,'on'); xlim(ax3,[w0 w1]);
ylabel(ax3,'\Sigma{\itQ} [pu]'); xlabel(ax3,'{\itt} [s]');
title(ax3,'(c) total reactive power','FontWeight','normal','FontSize',opts.font_size-1);

% Panel (d): Minimum Voltage
ax4 = nexttile(tl);
hold(ax4,'on');
for k = 1:size(arms,1)
    r = load_arm(C,arms{k,1});
    t = r.t(:);
    sig = min(r.bus_voltage_magnitude,[],1).';
    w = t >= w0 & t <= w1 & isfinite(sig);
    plot(ax4,t(w),sig(w),'Color',arms{k,3},'LineStyle',arms{k,4}, ...
        'LineWidth',1.2,'HandleVisibility','off');
    if strcmp(arms{k,1},'locked_gfl')
        idx = find(w);
        if ~isempty(idx)
            plot(ax4,t(idx(end)),sig(idx(end)),'x','Color',arms{k,3}, ...
                'MarkerSize',7,'LineWidth',1.4,'HandleVisibility','off');
        end
    end
end
xline(ax4,t_trip,':','Color',[0.45 0.45 0.45],'LineWidth',0.8);
grid(ax4,'on'); box(ax4,'on'); xlim(ax4,[w0 w1]);
ylabel(ax4,'min|{\itV}| [pu]'); xlabel(ax4,'{\itt} [s]');
title(ax4,'(d) network min voltage','FontWeight','normal','FontSize',opts.font_size-1);

png = fullfile(F,'slide_necessity.png');
pf_page_export(f,png,opts.dpi);
end

% =========================================================================
function sev = severity_index(r)
%SEVERITY_INDEX  The published severity index per converter, as computed.
%   Read from the reference-AGSI overlay the run published; the deck presents
%   only the two sub-indices that decide anything.
a = r.agsi_reference;
assert(isfield(a,'terms'), ...
    'generate_presentation_switch_figure:noAgsiTerms', ...
    'The cache carries no reference-AGSI terms; the supervisor panel cannot be drawn.');
JV = a.terms.J_V; Jf = a.terms.J_f;
if size(JV,1) ~= numel(r.t), JV = JV.'; end
if size(Jf,1) ~= numel(r.t), Jf = Jf.'; end
if size(Jf,2) == 1, Jf = repmat(Jf,1,size(JV,2)); end
sev = min(1,max(0,0.5*JV + 0.5*Jf));
end

% =========================================================================
function idx = converter_rows(r)
%CONVERTER_ROWS  Rows of the per-device histories that are converters.
n = size(r.device_modes_history,1);
idx = setdiff(1:n,r.sg_indices(:).');
end

function C = converter_colours(n)
base = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; 0.00 0.00 0.00];
C = base(1:min(n,size(base,1)),:);
if n > size(base,1), C = [C; lines(n-size(base,1))]; end
end

function L = converter_labels(r,n)
ibr = converter_rows(r);
L = cell(1,n);
for k = 1:n
    L{k} = sprintf('converter at bus %d',r.device_bus_ids(ibr(k)));
end
end

function L = owner_labels(r,n)
L = cell(1,n+1);
L{1} = 'machine';
ibr = converter_rows(r);
for k = 1:n
    L{k+1} = sprintf('bus %d',r.device_bus_ids(ibr(k)));
end
end

% =========================================================================
function code = owner_code(r)
%OWNER_CODE  0 when the machine owns the island reference, k for converter k.
%   Read per sample from the event context, not from the final snapshot.
nt = numel(r.t);
code = zeros(nt,1);
ibr = converter_rows(r);
ec = r.event_context_history;
for i = 1:nt
    own = [];
    if iscell(ec) && numel(ec) >= i && isstruct(ec{i}) ...
            && isfield(ec{i},'hybrid_state') ...
            && isfield(ec{i}.hybrid_state,'reference_owner_indices')
        own = ec{i}.hybrid_state.reference_owner_indices;
    end
    if isempty(own), continue; end
    k = find(ibr == own(1),1);
    if ~isempty(k), code(i) = k; end
end
end
