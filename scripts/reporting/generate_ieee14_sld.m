function generate_ieee14_sld(varargin)
%GENERATE_IEEE14_SLD  Classic orthogonal single-line diagram of the IEEE 14-bus system.
%
%   generate_ieee14_sld()
%   generate_ieee14_sld('annotate','eecon49')   % converters at buses 2,3,6,8
%   generate_ieee14_sld('key',true)             % add a symbol key
%   generate_ieee14_sld('output','docs/figures/my_sld.png','dpi',300)
%
% Drawn in the conventional switchgear style: thick bus bars, every branch routed
% as horizontal and vertical segments only, transformers as two tangent circles
% on the branch, machines as circles on a short lead, and loads as solid arrows.
%
% The ELECTRICAL content comes from the case, so the diagram cannot drift away
% from the code:
%   buses, branches ........ CASE_DEFINED, +cases/case_ieee14bus.m
%   transformer branches ... CASE_DEFINED, the branches with exactly zero series
%                            resistance: 4-7, 4-9, 5-6, 7-8, 7-9. Three carry an
%                            off-nominal tap (0.978, 0.969, 0.932).
%   machine / load buses ... CASE_DEFINED from the bus type and the scheduled
%                            generation and load columns.
%
% The GEOMETRY is presentation only and carries no electrical meaning:
%   bus coordinates ........ PROJECT_DERIVED, chosen to reproduce the layout of
%                            the conventional published figure.
%   branch routing ......... PROJECT_DERIVED waypoints, orthogonal.
%
% Note on the 4-7-9 group: published figures usually draw it as a three-winding
% transformer equivalent and therefore show fewer than five symbols. This figure
% instead marks every zero-resistance branch, so the symbol count matches the
% case data rather than the drawing convention.
%
% Lettering is Times New Roman and the figure is sized in inches, so it can be
% included in the reports at 1:1 scale per the typography contract in AGENTS.md.

p = inputParser;
p.addParameter('annotate','plain');      % 'plain' | 'eecon49'
p.addParameter('key',false);
p.addParameter('output','');
p.addParameter('dpi',300);
p.addParameter('width',6.5);
p.addParameter('height',7.4);
p.addParameter('title',true);
p.parse(varargin{:});
a = p.Results;
mode = lower(char(string(a.annotate)));
if isempty(a.output)
    if strcmp(mode,'eecon49')
        a.output = fullfile('docs','figures','ieee14_sld_eecon49.png');
    else
        a.output = fullfile('docs','figures','ieee14_sld.png');
    end
end
outdir = fileparts(a.output);
if ~isempty(outdir) && ~isfolder(outdir), mkdir(outdir); end

c  = cases.case_ieee14bus();
bd = c.bus_data;
ld = c.line_data;
nb = size(bd,1);

% --- bus geometry (PROJECT_DERIVED presentation) ---------------------------
% [x y orientation half_width]
G = containers.Map('KeyType','double','ValueType','any');
G(1)  = {1.2 , 4.30, 'h'};   G(2)  = {3.3 , 2.70, 'h'};
G(3)  = {5.9 , 2.70, 'h'};   G(4)  = {6.0 , 4.90, 'h'};
G(5)  = {3.1 , 4.50, 'h'};   G(6)  = {3.1 , 7.40, 'h'};
G(7)  = {7.1 , 6.30, 'h'};   G(8)  = {8.6 , 6.30, 'v'};
G(9)  = {6.3 , 7.80, 'h'};   G(10) = {6.0 , 9.50, 'h'};
G(11) = {4.4 , 9.50, 'h'};   G(12) = {2.0 , 9.30, 'h'};
G(13) = {2.9 ,10.70, 'h'};   G(14) = {6.1 ,10.70, 'h'};
BW = 0.35;                                  % bus-bar half length

% --- orthogonal branch routes (PROJECT_DERIVED) ---------------------------
% Each entry is the polyline from the first bus to the second, inclusive.
R = route_table();

fn = 'Times New Roman'; fs = 12;
lw_branch = 1.1; lw_bar = 5.5;
col   = [0 0 0];
col_sg  = [0.05 0.35 0.65];
col_ibr = [0.78 0.32 0.06];

fig = figure('Units','inches','Position',[1 1 a.width a.height], ...
    'Color','w','PaperUnits','inches','PaperPosition',[0 0 a.width a.height]);
ax = axes(fig,'Position',[0.03 0.02 0.94 0.94]); hold(ax,'on');
axis(ax,'equal'); axis(ax,'off');

% --- branches --------------------------------------------------------------
for k = 1:size(ld,1)
    f = ld(k,1); t = ld(k,2);
    key = sprintf('%d-%d',f,t);
    assert(isKey(R,key),'no route defined for branch %s',key);
    W = R(key);
    plot(ax,W(:,1),W(:,2),'-','Color',col,'LineWidth',lw_branch, ...
        'HandleVisibility','off');
    if ld(k,3) == 0
        draw_transformer_on(ax,W,col);
    end
end

% --- bus bars --------------------------------------------------------------
for k = 1:nb
    id = bd(k,1); g = G(id);
    if strcmp(g{3},'h')
        plot(ax,g{1}+[-BW BW],[g{2} g{2}],'-','Color',col,'LineWidth',lw_bar, ...
            'HandleVisibility','off');
    else
        plot(ax,[g{1} g{1}],g{2}+[-BW BW],'-','Color',col,'LineWidth',lw_bar, ...
            'HandleVisibility','off');
    end
end

% --- machines, converters, loads ------------------------------------------
% Side on which the source symbol hangs, so it never collides with the load.
SRC_SIDE = containers.Map({1,2,3,6,8},{'left','down','down','left','right'});
for k = 1:nb
    id = bd(k,1); g = G(id);
    btype = bd(k,2);
    if btype == 1
        draw_source(ax,g,SRC_SIDE(id),'sg',col_sg,BW);
    elseif btype == 2
        if strcmp(mode,'eecon49')
            draw_source(ax,g,SRC_SIDE(id),'ibr',col_ibr,BW);
        else
            draw_source(ax,g,SRC_SIDE(id),'sg',col_sg,BW);
        end
    end
    if abs(bd(k,7)) > 0 || abs(bd(k,8)) > 0
        used = occupied_offsets(R,id,g,BW);
        if isKey(SRC_SIDE,id) && strcmp(SRC_SIDE(id),'down')
            used(end+1) = -0.20; %#ok<AGROW>
        end
        draw_load(ax,g,id,col,BW,used);
    end
end

% --- bus numbers -----------------------------------------------------------
LBL = label_offsets();
for k = 1:nb
    id = bd(k,1); g = G(id); o = LBL(id);
    text(ax,g{1}+o{1},g{2}+o{2},sprintf('%d',id), ...
        'FontName',fn,'FontSize',fs,'FontWeight','bold', ...
        'HorizontalAlignment',o{3},'VerticalAlignment',o{4});
end

if a.title
    if strcmp(mode,'eecon49')
        ttl = 'IEEE 14-bus: one synchronous machine and four converters';
    else
        ttl = 'IEEE 14-bus single-line diagram';
    end
    title(ax,ttl,'FontName',fn,'FontSize',fs+1,'FontWeight','bold');
end
if a.key
    draw_key(ax,mode,fn,fs,col,col_sg,col_ibr);
end

xlim(ax,[0.0 10.2]); ylim(ax,[1.30 11.6]);
print(fig,a.output,'-dpng',sprintf('-r%d',a.dpi));
close(fig);

fprintf('wrote %s\n',a.output);
fprintf('  buses %d, branches %d, transformer branches %d\n', ...
    nb,size(ld,1),sum(ld(:,3)==0));
fprintf('  REF bus %s | PV buses %s\n', ...
    mat2str(bd(bd(:,2)==1,1).'),mat2str(bd(bd(:,2)==2,1).'));
fprintf('  load buses %s\n', ...
    mat2str(bd(abs(bd(:,7))>0 | abs(bd(:,8))>0,1).'));
end

% ==========================================================================
function R = route_table()
% Orthogonal waypoints per branch. Verticals leaving a bus are offset within
% the bar so that two branches out of the same bus never overlap.
R = containers.Map('KeyType','char','ValueType','any');
R('1-2')  = [1.20 4.30; 1.20 2.70; 2.95 2.70];
R('1-5')  = [1.20 4.30; 1.20 3.90; 2.90 3.90; 2.90 4.50];
R('2-3')  = [3.65 2.70; 5.55 2.70];
R('2-4')  = [3.45 2.70; 3.45 3.50; 5.80 3.50; 5.80 4.90];
R('2-5')  = [3.10 2.70; 3.10 4.50];
R('3-4')  = [6.10 2.70; 6.10 4.90];
R('4-5')  = [5.65 4.90; 4.40 4.90; 4.40 4.50; 3.45 4.50];
R('4-7')  = [6.35 4.90; 7.10 4.90; 7.10 6.30];
R('4-9')  = [6.20 4.90; 6.20 7.80];
R('5-6')  = [3.10 4.50; 3.10 7.40];
R('6-11') = [3.30 7.40; 3.30 8.60; 4.40 8.60; 4.40 9.50];
R('6-12') = [2.80 7.40; 2.80 9.30; 2.35 9.30];
R('6-13') = [3.10 7.40; 3.10 10.70];
R('7-8')  = [7.45 6.30; 8.60 6.30];
R('7-9')  = [6.95 6.30; 6.95 7.80; 6.65 7.80];
R('9-10') = [6.20 7.80; 6.20 9.50];
R('9-14') = [6.45 7.80; 6.45 10.70];
R('10-11')= [5.65 9.50; 4.75 9.50];
R('12-13')= [2.00 9.30; 2.00 10.70; 2.55 10.70];
R('13-14')= [3.25 10.70; 5.75 10.70];
end

function L = label_offsets()
% [dx dy halign valign] per bus, keeping the number off the bars and the routes.
L = containers.Map('KeyType','double','ValueType','any');
L(1)  = {-0.42,  0.16,'right','bottom'};
L(2)  = {-0.42,  0.16,'right','bottom'};
L(3)  = { 0.42,  0.16,'left' ,'bottom'};
L(4)  = { 0.42,  0.16,'left' ,'bottom'};
L(5)  = {-0.42,  0.16,'right','bottom'};
L(6)  = { 0.42,  0.16,'left' ,'bottom'};
L(7)  = {-0.42, -0.06,'right','middle'};
L(8)  = { 0.16,  0.42,'left' ,'bottom'};
L(9)  = { 0.42,  0.16,'left' ,'bottom'};
L(10) = {-0.42,  0.16,'right','bottom'};
L(11) = {-0.42,  0.16,'right','bottom'};
L(12) = {-0.42,  0.16,'right','bottom'};
L(13) = { 0.42,  0.16,'left' ,'bottom'};
L(14) = { 0.42,  0.16,'left' ,'bottom'};
end

function draw_transformer_on(ax,W,col)
% Two tangent circles on the longest segment of the route.
d = hypot(diff(W(:,1)),diff(W(:,2)));
[~,i] = max(d);
p1 = W(i,:); p2 = W(i+1,:);
m = (p1+p2)/2; u = (p2-p1)/max(d(i),eps);
r = 0.16;
th = linspace(0,2*pi,64);
for s = [-1 1]
    cc = m + u*(r*0.80*s);
    patch(ax,cc(1)+r*cos(th),cc(2)+r*sin(th),'w', ...
        'EdgeColor',col,'LineWidth',1.1,'HandleVisibility','off');
end
end

function draw_source(ax,g,side,kind,col,BW)
% Machine or converter on a short lead off the given side of the bus bar.
lead = 0.44; r = 0.28;
switch side
    case 'down',  base = [g{1}-0.20, g{2}]; c = base + [0 -(lead+r)];
    case 'left',  base = [g{1}-BW  , g{2}]; c = base + [-(lead+r) 0];
    case 'right', base = [g{1}+BW  , g{2}]; c = base + [ (lead+r) 0];
    otherwise,    base = [g{1}, g{2}];      c = base + [0 -(lead+r)];
end
plot(ax,[base(1) c(1)],[base(2) c(2)],'-','Color',col,'LineWidth',1.1, ...
    'HandleVisibility','off');
if strcmp(kind,'sg')
    th = linspace(0,2*pi,80);
    patch(ax,c(1)+r*cos(th),c(2)+r*sin(th),'w','EdgeColor',col, ...
        'LineWidth',1.4,'HandleVisibility','off');
    s = linspace(-0.60,0.60,40);
    plot(ax,c(1)+s*r,c(2)+0.40*r*sin(s*pi/0.60),'-','Color',col, ...
        'LineWidth',1.2,'HandleVisibility','off');
else
    h = r*0.92;
    patch(ax,c(1)+h*[-1 1 1 -1],c(2)+h*[-1 -1 1 1],'w','EdgeColor',col, ...
        'LineWidth',1.4,'HandleVisibility','off');
    plot(ax,c(1)+h*[-1 1],c(2)+h*[-1 1],'-','Color',col,'LineWidth',1.1, ...
        'HandleVisibility','off');
    plot(ax,c(1)+h*[-0.60 -0.18],c(2)+h*[-0.32 -0.32],'-','Color',col, ...
        'LineWidth',1.0,'HandleVisibility','off');
    plot(ax,c(1)+h*[-0.60 -0.18],c(2)+h*[-0.60 -0.60],'-','Color',col, ...
        'LineWidth',1.0,'HandleVisibility','off');
    s = linspace(0.18,0.60,20);
    plot(ax,c(1)+h*s,c(2)+h*(0.44+0.16*sin((s-0.18)/0.42*2*pi)),'-', ...
        'Color',col,'LineWidth',1.0,'HandleVisibility','off');
end
end

function used = occupied_offsets(R,id,g,BW)
% x-offsets, relative to the bus centre, already taken by branch segments that
% leave this bus vertically. Used so a load arrow is never drawn on top of a
% branch. Reads the route table, so it stays correct if a route changes.
used = [];
ks = keys(R);
for i = 1:numel(ks)
    parts = sscanf(ks{i},'%d-%d');
    if numel(parts) ~= 2 || ~any(parts == id), continue; end
    W = R(ks{i});
    for e = [1 size(W,1)]                    % both endpoints of the polyline
        if abs(W(e,2)-g{2}) < 1e-9 && abs(W(e,1)-g{1}) <= BW + 1e-9
            used(end+1) = W(e,1) - g{1}; %#ok<AGROW>
        end
    end
end
end

function draw_load(ax,g,id,col,BW,used)
% Solid arrow away from the bus, placed at the freest position along the bar.
UP = [9 10 13 14];
if ismember(id,UP), sgn = 1; else, sgn = -1; end
if strcmp(g{3},'v')
    x = g{1};
else
    cand = [-0.26 -0.13 0 0.13 0.26];
    if isempty(used)
        off = 0.22;
    else
        d = arrayfun(@(cx) min(abs(cx-used)),cand);
        [~,i] = max(d);
        off = cand(i);
    end
    x = g{1} + off;
end
L = 0.46; hw = 0.085; hl = 0.20;
y0 = g{2};
y1 = y0 + sgn*(L-hl);
plot(ax,[x x],[y0 y1],'-','Color',col,'LineWidth',1.3,'HandleVisibility','off');
patch(ax,x+[-hw hw 0],[y1 y1 y1+sgn*hl],col,'EdgeColor',col, ...
    'HandleVisibility','off');
end

function draw_key(ax,mode,fn,fs,col,col_sg,col_ibr)
x = 8.15; y = 11.15; dy = 0.62; r = 0.20;
th = linspace(0,2*pi,60);
patch(ax,x+r*cos(th),y+r*sin(th),'w','EdgeColor',col_sg,'LineWidth',1.3, ...
    'HandleVisibility','off');
s = linspace(-0.6,0.6,30);
plot(ax,x+s*r,y+0.4*r*sin(s*pi/0.6),'-','Color',col_sg,'LineWidth',1.1, ...
    'HandleVisibility','off');
text(ax,x+0.36,y,'synchronous machine','FontName',fn,'FontSize',fs-3, ...
    'VerticalAlignment','middle');
y = y - dy;
if strcmp(mode,'eecon49')
    h = 0.18;
    patch(ax,x+h*[-1 1 1 -1],y+h*[-1 -1 1 1],'w','EdgeColor',col_ibr, ...
        'LineWidth',1.3,'HandleVisibility','off');
    plot(ax,x+h*[-1 1],y+h*[-1 1],'-','Color',col_ibr,'LineWidth',1.0, ...
        'HandleVisibility','off');
    text(ax,x+0.36,y,'converter','FontName',fn,'FontSize',fs-3, ...
        'VerticalAlignment','middle');
    y = y - dy;
end
for s2 = [-1 1]
    patch(ax,x+s2*0.15+r*0.8*cos(th),y+r*0.8*sin(th),'w','EdgeColor',col, ...
        'LineWidth',1.0,'HandleVisibility','off');
end
text(ax,x+0.36,y,'transformer','FontName',fn,'FontSize',fs-3, ...
    'VerticalAlignment','middle');
y = y - dy;
plot(ax,[x x],[y+0.18 y-0.08],'-','Color',col,'LineWidth',1.3, ...
    'HandleVisibility','off');
patch(ax,x+[-0.085 0.085 0],[y-0.08 y-0.08 y-0.26],col,'EdgeColor',col, ...
    'HandleVisibility','off');
text(ax,x+0.36,y,'load','FontName',fn,'FontSize',fs-3, ...
    'VerticalAlignment','middle');
end
