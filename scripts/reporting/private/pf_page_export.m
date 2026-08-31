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
    savefig(f,figpath);
    fprintf('wrote %s\n',figpath);
end
close(f);
fprintf('wrote %s\n',p);
end
