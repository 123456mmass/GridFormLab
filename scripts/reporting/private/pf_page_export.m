function pf_page_export(f,path,dpi,save_fig)
%PF_PAGE_EXPORT  Write a report page at 1:1 and close it.
%
%   pf_page_export(f, path, dpi)
%   pf_page_export(f, path, dpi, save_fig)
%
% Uses print -dpng -rN, which honours the figure's PaperPosition, so the emitted
% PNG has exactly the physical size the figure declares. exportgraphics would
% re-derive the size and is used by the older generators at inconsistent
% resolutions; -r300 with an inch-sized canvas is the modern convention here
% (generate_switch_new_report_figures.m:206).
%
% save_fig=true additionally writes the live MATLAB figure beside the PNG as a
% .fig file, so the artwork can be reopened and adjusted (limits, labels,
% colours) without re-running the generator. The .fig is a convenience copy of
% the SAME figure the PNG came from -- the PNG remains the artifact the report
% includes, and nothing about the plotted values depends on it.
%
% Visible is flipped ON before savefig. pf_page_figure builds the canvas with
% Visible='off' so a batch run does not raise windows, and savefig stores that
% property verbatim: a .fig written from the hidden figure reopens hidden, so
% openfig loads the axes and lines into memory but draws no window and the user
% sees nothing. The flip happens AFTER print, so the exported PNG is unaffected,
% and the figure is closed immediately below, so nothing is left on screen.

arguments
    f (1,1) matlab.ui.Figure
    path (1,1) string
    dpi (1,1) double {mustBePositive} = 300
    save_fig (1,1) logical = false
end

p = char(path);
d = fileparts(p);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
print(f,p,'-dpng',sprintf('-r%d',round(dpi)));
if save_fig
    [dd,bb] = fileparts(p);
    figpath = fullfile(dd,[bb '.fig']);
    was_visible = f.Visible;
    f.Visible = 'on';      % so the reopened .fig actually draws a window
    savefig(f,figpath);
    f.Visible = was_visible;
    fprintf('wrote %s\n',figpath);
end
close(f);
fprintf('wrote %s\n',p);
end
