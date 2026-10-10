function h = icon_button(parent, label, icon_file, callback)
%ICON_BUTTON  Push button with an optional icon and a text fallback.
%   h = studio.ui.icon_button(parent, label, icon_file, callback) creates a
%   studio-styled uibutton.  If ICON_FILE names an existing image, it is set
%   as the button icon; a missing or unusable asset NEVER blocks launch --
%   the button simply keeps its text LABEL.  CALLBACK is a (src,evt) handle.
%
%   See also: studio.ui.INSTALL_HOVER, studio.ui.BUILD_LAYOUT.

c = studio.ui.layout_constants();
h = uibutton(parent, ...
    'Text', label, ...
    'FontName', c.font_name, ...
    'FontSize', c.font_size, ...
    'BackgroundColor', c.button_idle, ...
    'FontColor', c.black);
if nargin >= 3 && ~isempty(icon_file)
    try
        if ischar(icon_file) || isstring(icon_file)
            if exist(char(icon_file), 'file') == 2
                h.Icon = char(icon_file);
            end
        else
            h.Icon = icon_file;   % CData supplied directly
        end
    catch
        % Missing/corrupt asset: keep the text label; never block launch.
    end
end
if nargin >= 4 && ~isempty(callback)
    h.ButtonPushedFcn = callback;
end
end
