function lines = format_overview(case_id, case_label, case_data, report, event_lines)
%FORMAT_OVERVIEW  Build the Overview band text for an imported case.
%   lines = studio.format_overview(case_id, case_label, case_data, report,
%   event_lines) returns a cellstr for the read-only Overview box:
%   case identity, network summary, the resource-detection headline and
%   detail (from studio.detect_resources), then any event lines.
%
%   EVENT_LINES is a cellstr (may be empty).  The text is English-only.
%
%   See also: studio.DETECT_RESOURCES, studio.ui.BUILD_LAYOUT.

if nargin < 5 || isempty(event_lines), event_lines = {}; end
if ischar(event_lines) || isstring(event_lines), event_lines = cellstr(event_lines); end

lines = {};
lines{end+1} = sprintf('Case     : %s (%s)', case_label, case_id);
if isfield(case_data, 'schema_version')
    lines{end+1} = sprintf('Schema   : %s', char(case_data.schema_version));
end
if isfield(case_data, 'base_values')
    lines{end+1} = sprintf('Base     : %.6g MVA, %.6g Hz', ...
        case_data.base_values.S_base_MVA, case_data.base_values.frequency_Hz);
end
if isfield(case_data, 'bus_data') && isfield(case_data, 'line_data')
    lines{end+1} = sprintf('Network  : %d buses, %d branches', ...
        size(case_data.bus_data, 1), size(case_data.line_data, 1));
end
lines{end+1} = '';
lines{end+1} = 'Resource detection';
lines{end+1} = report.headline;
d = splitlines(report.detail);
for k = 1:numel(d)
    if strlength(strtrim(d{k})) > 0
        lines{end+1} = char(d{k}); %#ok<AGROW>
    end
end
if ~isempty(event_lines)
    lines{end+1} = '';
    lines{end+1} = 'Event settings';
    for k = 1:numel(event_lines)
        lines{end+1} = char(event_lines{k}); %#ok<AGROW>
    end
end
lines = lines(:);
end
