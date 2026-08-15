function generate_readme_chronology_figure(varargin)
%GENERATE_README_CHRONOLOGY_FIGURE  Chronology figure for the repository README.
%
%   generate_readme_chronology_figure()
%   generate_readme_chronology_figure('result','output/diagnostics/my_run.mat', ...
%       'output','docs/figures/ieee14_eecon49_chronology_250s.png')
%
% Renders the IEEE 14-bus EECON49 mixed SG/IBR chronology from a saved
% stability.run_hybrid_case result: COI and SG frequency, the network voltage
% envelope, and the committed per-device controller mode, with every scheduled
% and supervisor-committed event annotated.
%
% The figure is sized in physical units and lettered in Times New Roman 11 pt so
% it matches the report typography contract in AGENTS.md.
%
% Nothing is recomputed: every trace is read from the stored result, so the
% figure cannot disagree with the run that produced it.

p = inputParser;
p.addParameter('result',fullfile('output','diagnostics','reclose_e4_efdctrl.mat'));
p.addParameter('output',fullfile('docs','figures','ieee14_eecon49_chronology_250s.png'));
p.addParameter('dpi',220);
p.parse(varargin{:});
a = p.Results;

assert(isfile(a.result),'result file not found: %s',a.result);
S = load(a.result);
assert(isfield(S,'r'),'%s does not contain a run result named r',a.result);
r = S.r;

outdir = fileparts(a.output);
if ~isempty(outdir) && ~isfolder(outdir), mkdir(outdir); end

t  = r.t(:).';
n  = numel(t);
fn = 'Times New Roman';
fs = 11;

fig = figure('Units','inches','Position',[1 1 7.0 6.4], ...
    'Color','w','PaperUnits','inches','PaperPosition',[0 0 7.0 6.4]);
tl = tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');

% ---- events worth annotating -------------------------------------------------
ev = struct('t',{},'label',{},'style',{});
sched = getfielddef(r,'sched',struct());
add = @(tt,lab,sty) struct('t',tt,'label',lab,'style',sty);
for f = {{'sg_trip','SG trip'},{'load_step','+20% load'}, ...
         {'fault_on','fault'},{'line_trip','line trip'}, ...
         {'restore_time','restore'}}
    key = f{1}{1};
    if isfield(sched,key) && isfinite(sched.(key))
        ev(end+1) = add(sched.(key),f{1}{2},'k'); %#ok<AGROW>
    end
end
if isfield(r,'actual_reclose_time') && isfinite(r.actual_reclose_time)
    ev(end+1) = add(r.actual_reclose_time,'reclose','r'); %#ok<AGROW>
end
[~,ord] = sort([ev.t]); ev = ev(ord);

% ---- (a) frequency ----------------------------------------------------------
ax1 = nexttile(tl); hold(ax1,'on'); grid(ax1,'on'); box(ax1,'on');
plot(ax1,t,r.coi_frequency_Hz(:).','LineWidth',1.4,'DisplayName','f_{COI}');
if isfield(r,'sg_freq')
    sgf = r.sg_freq(:).';
    plot(ax1,t,sgf,'--','LineWidth',1.1,'DisplayName','f_{SG}');
end
draw_events(ax1,ev,fn,fs,true);
ylabel(ax1,'frequency [Hz]');
legend(ax1,'Location','southeast','Box','off');
title(ax1,'(a)  Island frequency','FontWeight','bold');
ylim_pad(ax1,0.30);

% ---- (b) voltage envelope ---------------------------------------------------
ax2 = nexttile(tl); hold(ax2,'on'); grid(ax2,'on'); box(ax2,'on');
Vm = r.bus_voltage_magnitude;
vmin = min(Vm,[],1); vmax = max(Vm,[],1);
fill(ax2,[t fliplr(t)],[vmin fliplr(vmax)],[0.80 0.86 0.95], ...
    'EdgeColor','none','FaceAlpha',0.9,'DisplayName','all-bus range');
plot(ax2,t,vmin,'LineWidth',1.1,'DisplayName','min |V|');
plot(ax2,t,vmax,'LineWidth',1.1,'DisplayName','max |V|');
draw_events(ax2,ev,fn,fs,false);
ylabel(ax2,'|V| [p.u.]');
legend(ax2,'Location','southeast','Box','off');
title(ax2,'(b)  Network voltage envelope','FontWeight','bold');
ylim(ax2,[max(0,min(vmin)-0.05) max(vmax)+0.05]);

% ---- (c) committed device modes ---------------------------------------------
ax3 = nexttile(tl); hold(ax3,'on'); grid(ax3,'on'); box(ax3,'on');
nd = numel(r.device_ids);
lv = zeros(nd,n);
for k = 1:nd
    for j = 1:n
        lv(k,j) = mode_level(r.device_modes_history{k,j}, ...
            r.device_online_history(k,j));
    end
end
% Small vertical offsets so overlapping traces stay readable (display only).
off = linspace(-0.12,0.12,nd);
for k = 1:nd
    stairs(ax3,t,lv(k,:)+off(k),'LineWidth',1.5, ...
        'DisplayName',char(string(r.device_ids{k})));
end
draw_events(ax3,ev,fn,fs,false);
set(ax3,'YTick',[0 1 2],'YTickLabel',{'open','GFL','GFM / SG'});
ylim(ax3,[-0.45 2.45]);
ylabel(ax3,'committed mode');
xlabel(ax3,'time [s]');
legend(ax3,'Location','southeast','Box','off','NumColumns',5,'FontSize',fs-2);
title(ax3,'(c)  Committed controller mode per resource','FontWeight','bold');

% ---- headline ---------------------------------------------------------------
rs = char(string(getfielddef(r,'reclose_status','')));
art = getfielddef(r,'actual_reclose_time',NaN);
head = sprintf(['IEEE 14-bus, 1 SG + 4 IBR (EECON49): %.0f s chronology, ' ...
    'reclose %s at t = %.3f s'],t(n),rs,art);
title(tl,head,'FontName',fn,'FontSize',fs+1,'FontWeight','bold');

set(findall(fig,'-property','FontName'),'FontName',fn);
set(findall(fig,'-property','FontSize'),'FontSize',fs);
linkaxes([ax1 ax2 ax3],'x'); xlim(ax1,[t(1) t(n)]);

print(fig,a.output,'-dpng',sprintf('-r%d',a.dpi));
close(fig);
fprintf('wrote %s\n',a.output);
fprintf('  horizon      %.4f s\n',t(n));
fprintf('  reclose      %s at %.4f s\n',rs,art);
fprintf('  terminal f   %.6f Hz\n',r.coi_frequency_Hz(n));
fprintf('  terminal |V| %.4f .. %.4f pu\n',min(Vm(:,n)),max(Vm(:,n)));
end

% ---------------------------------------------------------------------------
function draw_events(ax,ev,fn,fs,label_them)
% Event lines on every panel; labels only where asked, staggered vertically so
% adjacent events on a 250 s axis do not overprint each other.
if nargin < 5, label_them = false; end
yl = ylim(ax);
rows = {'top','bottom'};   % 2-row stagger keeps labels off the traces
for k = 1:numel(ev)
    args = {':','Color',ev(k).style,'LineWidth',1.0, ...
        'HandleVisibility','off','Alpha',0.85};
    if label_them
        args = [args,{'Label',ev(k).label, ...
            'LabelOrientation','horizontal', ...
            'LabelVerticalAlignment',rows{mod(k-1,2)+1}, ...
            'LabelHorizontalAlignment','left', ...
            'FontName',fn,'FontSize',fs-2}]; %#ok<AGROW>
    end
    xline(ax,ev(k).t,args{:});
end
ylim(ax,yl);
end

function L = mode_level(m,online)
% 0 = breaker open, 1 = grid-following, 2 = voltage-forming (GFM or SG).
if ~online, L = 0; return; end
s = lower(char(string(m)));
if contains(s,'open'),      L = 0;
elseif strcmp(s,'gfl'),     L = 1;
else,                       L = 2;   % gfm, sg, synchronous
end
end

function ylim_pad(ax,frac)
if nargin < 2, frac = 0.08; end
yl = ylim(ax); d = diff(yl);
if d > 0, ylim(ax,yl + frac*d*[-1 1]); end
end

function v = getfielddef(s,f,d)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
