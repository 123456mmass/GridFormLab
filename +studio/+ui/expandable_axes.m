function expandable_axes(ax, expand_now)
%EXPANDABLE_AXES  Double-click an embedded axes to copy it into its own figure.
%   studio.ui.expandable_axes(ax) installs a double-click handler on AX.
%   studio.ui.expandable_axes(ax, true) expands immediately (the Plots /
%   Expand buttons use this path).
%
%   A double-click copies the axes into a standalone figure (copyobj).  The
%   copy is created with 'Visible','off' and shown only when the session is
%   interactive -- a batch drive must never throw a window on screen.
%
%   State is stored handle-locally on AX via setappdata, never on the root
%   (the reference GUI's setappdata(0,...) pattern is breakable and global).
%
%   Double-click is detected from two ButtonDownFcn hits inside a short
%   threshold (uiaxes has no SelectionType); click times come from toc on a
%   base clock stored with the same appdata struct.
%
%   See also: studio.ui.BUILD_LAYOUT.

c = studio.ui.layout_constants();
if nargin < 2, expand_now = false; end
setappdata(ax, 'studio_expand', struct('tbase', tic, 'last_click', -Inf, ...
    'threshold', 0.4, 'font_name', c.font_name, 'font_size', c.font_size));
ax.ButtonDownFcn = @(src, evt) on_click(src);
if expand_now
    expand(ax);
end
end

function on_click(ax)
if ~isgraphics(ax), return; end
st = getappdata(ax, 'studio_expand');
if isempty(st) || ~isstruct(st), return; end
t_now = toc(st.tbase);
if isfield(st, 'last_click') && isfinite(st.last_click) && ...
        (t_now - st.last_click) < st.threshold
    st.last_click = -Inf;
    setappdata(ax, 'studio_expand', st);
    expand(ax);
else
    st.last_click = t_now;
    setappdata(ax, 'studio_expand', st);
end
end

function expand(ax)
vf = figure('Name', 'Studio plot (expanded)', 'NumberTitle', 'off', ...
    'Color', 'w', 'Visible', 'off', 'Position', [120 120 820 520]);
ax2 = copyobj(ax, vf);
ax2.Units = 'normalized';
ax2.Position = [0.10 0.10 0.86 0.84];
ax2.Visible = 'on';
if usejava('desktop') && feature('ShowFigureWindows')
    vf.Visible = 'on';   % shown only on request, in an interactive session
end
end
