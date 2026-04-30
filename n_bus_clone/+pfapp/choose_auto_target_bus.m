function [target_idx, reason] = choose_auto_target_bus(model, base_pf)
%CHOOSE_AUTO_TARGET_BUS Pick the weakest PQ (or non-slack) bus for CPF.

if ~isempty(model.pq_buses)
    candidate_idx = model.pq_buses;
    reason = 'weakest PQ';
else
    candidate_idx = setdiff((1:model.num_buses).', model.slack_buses);
    reason = 'weakest non-slack';
end

if isempty(candidate_idx)
    error('Cannot choose auto target bus: no eligible buses found ' ...
          '(all buses may be slack).');
end

[~, local_idx] = min(base_pf.bus_voltage(candidate_idx));
target_idx = candidate_idx(local_idx);
end
