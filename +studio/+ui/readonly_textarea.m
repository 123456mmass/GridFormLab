function h = readonly_textarea(parent, varargin)
%READONLY_TEXTAREA  Read-only multiline text box with the studio grey text.
%   h = studio.ui.readonly_textarea(parent, 'Position', POS, ...) returns a
%   uitextarea that is Editable='off', Arial 9 (or the mono tokens when
%   'Mono' is true), and painted with the grey read-only text colour.
%
%   Name-value pairs other than 'Mono' are forwarded to uitextarea, so the
%   caller sets Position/Value/Tag. 'Mono' selects the eigenvalue-box font
%   (Courier New 8). Forwarded pairs win over the studio defaults.
%
%   See also: studio.ui.APPEND_LOG, studio.ui.BUILD_LAYOUT.

c = studio.ui.layout_constants();
mono = false;
if ~isempty(varargin) && (strcmpi(varargin{1}, 'Mono'))
    mono = logical(varargin{2});
    varargin = varargin(3:end);
end
if mono
    fname = c.mono_font_name; fsize = c.mono_font_size;
else
    fname = c.font_name; fsize = c.font_size;
end

defaults = {'Editable', 'off', 'FontName', fname, 'FontSize', fsize, ...
    'FontColor', c.text_grey, 'BackgroundColor', c.bg, 'Value', {''}};
% Forwarded pairs win: strip defaults whose name the caller supplies.
for k = 1:2:numel(varargin)
    name = char(varargin{k});
    hit = find(strcmpi(defaults(1:2:end), name), 1);
    if ~isempty(hit)
        defaults(2*hit-1:2*hit) = [];
    end
end
h = uitextarea(parent, defaults{:}, varargin{:});
end
