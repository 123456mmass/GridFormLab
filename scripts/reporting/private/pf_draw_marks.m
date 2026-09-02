function pf_draw_marks(ax,M,opts)
%PF_DRAW_MARKS  Draw one event-marker set on one axis.
%
%   pf_draw_marks(ax, M)
%   pf_draw_marks(ax, M, labels=true, families=["disturbance","supervisor"])
%   pf_draw_marks(ax, M, labels=true, label_band=[0.62 0.98])
%   pf_draw_marks(ax, M, labels=true, font_name="Helvetica")
%
% M is the struct returned by ieee14_switch_event_marks. Every panel of every
% figure is given the SAME M, so marker identity across panels is structural.
%
% Two invariants this function keeps, both learned from the existing
% event_lines helper (generate_ieee14_switch_report_figures.m:728-760):
%
%   1. It NEVER touches xlim. event_lines ends with xlim(ax,...) taken from "the"
%      trajectory, which is wrong on a comparison page where one arm stops at
%      t = 20 s and another runs to t = 250 s. The caller sets the axis range
%      once, for all axes, from the union it intends.
%   2. It restores ylim. xline with a Label can expand the y limits, and on a
%      tile whose purpose is reading a value against yline(1), a silently
%      rescaled y axis is a real defect.
%
% Markers are achromatic and distinguished by line style, so colour stays
% reserved for data and the page survives greyscale printing.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    M struct
    opts.labels (1,1) logical = false
    opts.families (1,:) string = ["disturbance","supervisor","validity"]
    opts.label_families (1,:) string = ["disturbance","supervisor","validity"]
    opts.regions (1,1) logical = true
    opts.font_size (1,1) double = 8
    opts.line_width (1,1) double = 0.8
    opts.window (1,2) double = [-Inf Inf]
    opts.label_band (1,2) double = [NaN NaN]
    % Marker-label typeface. Defaults to the report body font, so every page
    % already delivered letters exactly as before. A page set in another
    % typeface passes its own name: a marker label in a second font is a
    % typographic defect on a figure whose axes are lettered in the first.
    opts.font_name (1,1) string = "Times New Roman"
end

FN = char(opts.font_name);
yl = ylim(ax);
was_held = ishold(ax);
hold(ax,'on');

% Shaded regions first, so every line and every data trace sits on top of them.
if opts.regions && isfield(M,'regions')
    for k = 1:numel(M.regions)
        R = M.regions(k);
        if R.t1 < opts.window(1) || R.t0 > opts.window(2), continue; end
        if exist('xregion','file') == 2 || exist('xregion','builtin') == 5
            xregion(ax,R.t0,R.t1,'FaceColor',[0.85 0.35 0.35], ...
                'FaceAlpha',0.12,'HandleVisibility','off');
        end
    end
end

if ~isfield(M,'marks') || isempty(M.marks)
    ylim(ax,yl);
    if ~was_held, hold(ax,'off'); end
    return;
end

rows = {'top','middle','bottom'};
% label_band, when given as two axes-height fractions [lo hi], places the three
% stagger rows inside that band with an explicit text object instead of using
% xline's own Label. xline can only anchor a label to the top, middle or bottom
% of the axes, so on a panel whose data fills the lower part of the range there
% is no way to keep the middle and bottom rows clear of the traces. Reserving a
% band above the data solves that. Default is [NaN NaN], which takes the original
% xline-Label path unchanged.
use_band = all(isfinite(opts.label_band));
if use_band
    lo = min(opts.label_band); hi = max(opts.label_band);
    nr = numel(rows);
    if nr > 1
        frac = hi - (0:nr-1)*(hi-lo)/(nr-1);   % row 1 highest
    else
        frac = hi;
    end
    y_row = yl(1) + frac*(yl(2)-yl(1));
end
for k = 1:numel(M.marks)
    m = M.marks(k);
    if ~any(strcmp(m.family,opts.families)), continue; end
    if m.t < opts.window(1) || m.t > opts.window(2), continue; end
    show = opts.labels && m.is_group_label && ...
        any(strcmp(m.family,opts.label_families));
    if show && use_band
        h = xline(ax,m.t,m.style);
        ri = min(max(m.row,1),numel(rows));
        % Opaque background. A long name reaches several event instants to its
        % right, and a grey rule drawn through the glyphs is what made the name
        % hard to read. The band is reserved ABOVE the data by construction, so
        % the patch can only cover annotation rules, never a sample.
        text(ax,m.t,y_row(ri),[' ' m.group_label ' '], ...
            'FontName',FN,'FontSize',opts.font_size, ...
            'HorizontalAlignment','left','VerticalAlignment','middle', ...
            'Color',[0.15 0.15 0.15],'Clipping','on', ...
            'BackgroundColor',[1 1 1],'Margin',0.5);
    elseif show
        h = xline(ax,m.t,m.style,m.group_label);
        h.LabelVerticalAlignment = rows{min(max(m.row,1),numel(rows))};
        % Place the text to the RIGHT of the line: a label on a mark near the
        % left edge of a zoom window would otherwise be clipped by the axis.
        h.LabelHorizontalAlignment = 'right';
        h.LabelOrientation = 'horizontal';
        h.FontName = FN;
        h.FontSize = opts.font_size;
    else
        h = xline(ax,m.t,m.style);
    end
    h.Color = m.color;
    h.LineWidth = opts.line_width;
    h.Alpha = 1;
    h.HandleVisibility = 'off';
end

ylim(ax,yl);
if ~was_held, hold(ax,'off'); end
end
