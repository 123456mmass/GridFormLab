function f = pf_page_figure(w_in,h_in,fs,font_name)
%PF_PAGE_FIGURE  A report page figure sized in inches, lettered in the body font.
%
%   f = pf_page_figure(width_in, height_in, font_size)
%   f = pf_page_figure(width_in, height_in, font_size, font_name)
%
% AGENTS.md requires figure lettering to match the report body text in typeface
% AND size, and requires the figure to be sized in physical units and included
% at 1:1 (\includegraphics[width=<exact>in]) rather than rescaled from a
% pixel-sized canvas -- rescaling changes the rendered font size.
%
% The default is Times New Roman, which matches the English report (set in
% newtxtext/newtxmath). The Thai report shares these figures by contract, so its
% figure lettering is Times as well; pass font_name only if a future report body
% changes typeface AND the font is installed system-wide (MATLAB resolves figure
% fonts through the OS, not through the repository's bundled TTFs).
%
% Deliberately NOT built on scripts/reporting/report_figure_helpers.m: that
% helper sizes in pixels (report_figure_helpers.m:39-42) and its style map
% specifies Helvetica 10 pt (report_style_map.m:62-63), both of which predate and
% contradict the current contract. It serves the older PF/SSSA validation
% figures and must keep doing so.

arguments
    w_in (1,1) double {mustBePositive}
    h_in (1,1) double {mustBePositive}
    fs (1,1) double {mustBePositive} = 11
    font_name (1,1) string = "Times New Roman"
end

FN = char(font_name);
if ~any(strcmp(listfonts,FN))
    warning('pf_page_figure:fontUnavailable', ...
        ['Font "%s" is not installed; MATLAB will substitute. The figure ' ...
         'lettering will not match the report body exactly.'],FN);
end
f = figure('Units','inches','Position',[1 1 w_in h_in], ...
    'Color','w','PaperUnits','inches', ...
    'PaperSize',[w_in h_in],'PaperPosition',[0 0 w_in h_in], ...
    'DefaultAxesFontName',FN,'DefaultAxesFontSize',fs, ...
    'DefaultTextFontName',FN,'DefaultTextFontSize',fs, ...
    'DefaultLegendFontName',FN,'DefaultLegendFontSize',fs, ...
    'InvertHardcopy','off','Visible','off');
end
