function p6_show_section(src, panel, view)
%P6_SHOW_SECTION  Callback: show the selected section's content.
sel = get(src, 'Value');
if isempty(sel) || sel < 1 || sel > numel(view.sections), return; end
wizard.pages.p6_render_section(panel, view, sel);
end
