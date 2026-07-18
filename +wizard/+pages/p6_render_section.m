function p6_render_section(panel, view, idx)
%P6_RENDER_SECTION  Render the content of section IDX into the content area.
sec = view.sections(idx);
ctrl = findobj(panel, 'Tag', 'p6_content');
if isempty(ctrl), return; end
txt = wizard.pages.p6_section_text(sec);
set(ctrl, 'String', txt);
end

function txt = p6_section_text(sec)
% Build a readable text dump of a section's content struct.
lines = {sprintf('Section %d: %s', sec.index, sec.title); ...
         sprintf('Status: %s', sec.status); ...
         ''};
if isstruct(sec.content) && ~isempty(fieldnames(sec.content))
    fn = fieldnames(sec.content);
    for k = 1:numel(fn)
        v = sec.content.(fn{k});
        lines{end+1} = sprintf('  %-22s : %s', fn{k}, wizard.pages.format_value(v)); %#ok<AGROW>
    end
elseif isempty(fieldnames(sec.content))
    lines{end+1} = '  (no data)';
end
txt = strjoin(lines, newline);
end
