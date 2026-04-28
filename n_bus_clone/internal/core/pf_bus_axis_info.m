function info = pf_bus_axis_info(external_bus_ids)
%PF_BUS_AXIS_INFO Build a readable plotting/table axis description for bus IDs.

ids = external_bus_ids(:);
n = numel(ids);
display_index = (1:n).';
is_standard_sequence = isequal(ids, display_index);

info = struct( ...
    'display_index', display_index, ...
    'external_ids', ids, ...
    'use_external_axis', is_standard_sequence, ...
    'x', display_index, ...
    'xlabel', 'Bus Index', ...
    'note', '');

if is_standard_sequence
    info.x = ids;
    info.xlabel = 'Bus';
else
    info.note = 'Actual bus IDs are non-sequential source labels; table keeps both index and ID.';
end
end
