function bar = segment_bar(parent, arg2)
%SEGMENT_BAR  40-segment progress bar (rectangle patches).
%   bar = studio.ui.segment_bar(parent) builds a small axes in PARENT
%   carrying c.segment_count rectangular patches and returns a handle struct
%   (bar.ax, bar.segments, bar.n).
%
%   studio.ui.segment_bar(bar, fraction) paints progress in [0,1]: filled
%   segments get the navy token, empty ones stay idle.
%
%   Patches are drawn with patch() (base graphics on uiaxes) rather than
%   rectangle(), which is not available on uiaxes across supported releases.
%
%   See also: studio.ui.BUILD_LAYOUT.

if isstruct(parent)
    if nargin < 2, return; end
    paint(parent, arg2);
    bar = parent;
    return;
end

c = studio.ui.layout_constants();
bar = struct();
bar.n = c.segment_count;
bar.ax = uiaxes(parent, 'Visible', 'off');
hold(bar.ax, 'on');
bar.ax.XLim = [0 1]; bar.ax.YLim = [0 1];
bar.ax.XTick = []; bar.ax.YTick = [];
bar.ax.Box = 'off';
bar.segments = gobjects(1, bar.n);
seg_w = 1 / bar.n;
for i = 1:bar.n
    x0 = (i - 1) * seg_w + 0.15 * seg_w;
    x1 = i * seg_w - 0.15 * seg_w;
    bar.segments(i) = patch(bar.ax, [x0 x1 x1 x0], [0.15 0.15 0.85 0.85], ...
        c.button_idle, 'EdgeColor', 'none');
end
paint(bar, 0);
end

function paint(bar, fraction)
c = studio.ui.layout_constants();
fraction = min(1, max(0, double(fraction)));
filled = round(fraction * bar.n);
for i = 1:bar.n
    if i <= filled
        bar.segments(i).FaceColor = c.navy;
    else
        bar.segments(i).FaceColor = c.button_idle;
    end
end
end
