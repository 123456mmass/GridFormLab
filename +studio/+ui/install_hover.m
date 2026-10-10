function hover = install_hover(fig, buttons)
%INSTALL_HOVER  One WindowButtonMotionFcn with a manual rect hit-test.
%   hover = studio.ui.install_hover(fig, buttons) installs a SINGLE motion
%   callback on FIG that repaints the hovered button of BUTTONS with the
%   hover tokens and restores the idle look when the pointer leaves.
%
%   Two deliberate departures from the reference GUI's behaviour:
%     1. the hovered INDEX is cached and the callback EARLY-OUTS when the
%        pointer is still over the same button -- the reference repaints on
%        every motion event;
%     2. hover state is stored handle-locally (fig appdata), not on the
%        root (no root-global state survives a clearvars for us).
%
%   The hit-test uses the buttons' pixel rectangles (figure pixels,
%   bottom-left origin) against fig.CurrentPoint.  When CurrentPoint is
%   unavailable the callback is a harmless no-op -- never an error.
%
%   See also: studio.ui.ICON_BUTTON.

c = studio.ui.layout_constants();
buttons = buttons(:);
n = numel(buttons);
rects = zeros(n, 4);
for k = 1:n
    if isgraphics(buttons(k))
        rects(k, :) = getpixelposition(buttons(k), true);
    end
end
hover = struct('buttons', buttons, 'rects', rects, 'index', 0, ...
    'idle_bg', c.button_idle, 'hover_bg', c.hover_bg, 'hover_fg', c.hover_fg, ...
    'idle_fg', c.black);
setappdata(fig, 'studio_hover', hover);
fig.WindowButtonMotionFcn = @(src, evt) motion(src);
end

function motion(fig)
if ~isgraphics(fig), return; end
hover = getappdata(fig, 'studio_hover');
if isempty(hover) || ~isstruct(hover), return; end
p = pointer_pixels(fig);
if any(~isfinite(p)), return; end
idx = 0;
for k = 1:size(hover.rects, 1)
    r = hover.rects(k, :);
    if p(1) >= r(1) && p(1) <= r(1) + r(3) && p(2) >= r(2) && p(2) <= r(2) + r(4)
        idx = k; break
    end
end
if idx == hover.index
    return;   % EARLY-OUT: hovered index unchanged, nothing to repaint.
end
if hover.index >= 1 && hover.index <= numel(hover.buttons) && ...
        isgraphics(hover.buttons(hover.index))
    b = hover.buttons(hover.index);
    b.BackgroundColor = hover.idle_bg;
    b.FontColor = hover.idle_fg;
end
if idx >= 1 && isgraphics(hover.buttons(idx))
    b = hover.buttons(idx);
    b.BackgroundColor = hover.hover_bg;
    b.FontColor = hover.hover_fg;
end
hover.index = idx;
setappdata(fig, 'studio_hover', hover);
end

function p = pointer_pixels(fig)
p = [NaN NaN];
try
    q = fig.CurrentPoint;
    if isnumeric(q) && numel(q) >= 2
        p = [q(1, 1), q(1, 2)];
    end
catch
end
end
