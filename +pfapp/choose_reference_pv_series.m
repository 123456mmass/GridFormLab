function [plot_bus_id, plot_voltage, note_text] = choose_reference_pv_series(cpf)
plot_bus_id = cpf.target_bus;
plot_bus_index = cpf.target_bus_index;
plot_voltage = cpf.target_voltage(:);
note_text = '';

if isempty(cpf.bus_voltage) || size(cpf.bus_voltage, 2) < 2
    return;
end

if ~isempty(cpf.results) && isfield(cpf.results{1}, 'bus_type')
    bus_type = cpf.results{1}.bus_type(:);
else
    bus_type = [];
end

voltage_span = max(cpf.bus_voltage, [], 2) - min(cpf.bus_voltage, [], 2);
target_is_flat = voltage_span(plot_bus_index) < 0.02;
target_is_regulated = ~isempty(bus_type) && bus_type(plot_bus_index) ~= 3;
if ~(target_is_flat || target_is_regulated)
    return;
end

candidate_idx = (1:numel(cpf.external_bus_ids)).';
if ~isempty(bus_type)
    pq_idx = find(bus_type == 3);
    if ~isempty(pq_idx)
        candidate_idx = pq_idx;
    else
        candidate_idx = find(bus_type ~= 1);
    end
end

if isempty(candidate_idx)
    return;
end

score = voltage_span(candidate_idx) + (1 - cpf.bus_voltage(candidate_idx, end));
[~, local_pick] = max(score);
plot_bus_index = candidate_idx(local_pick);
plot_bus_id = cpf.external_bus_ids(plot_bus_index);
plot_voltage = cpf.bus_voltage(plot_bus_index, :).';
note_text = sprintf('Reference P-V view auto-switched from target bus %g to weak bus %g', ...
    cpf.target_bus, plot_bus_id);
end
