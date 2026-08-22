function pf_page_export(f,path,dpi)
%PF_PAGE_EXPORT  Write a report page at 1:1 and close it.
%
%   pf_page_export(f, path, dpi)
%
% Uses print -dpng -rN, which honours the figure's PaperPosition, so the emitted
% PNG has exactly the physical size the figure declares. exportgraphics would
% re-derive the size and is used by the older generators at inconsistent
% resolutions; -r300 with an inch-sized canvas is the modern convention here
% (generate_switch_new_report_figures.m:206).

arguments
    f (1,1) matlab.ui.Figure
    path (1,1) string
    dpi (1,1) double {mustBePositive} = 300
end

p = char(path);
d = fileparts(p);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
print(f,p,'-dpng',sprintf('-r%d',round(dpi)));
close(f);
fprintf('wrote %s\n',p);
end
