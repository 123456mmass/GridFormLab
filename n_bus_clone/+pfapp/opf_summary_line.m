function line = opf_summary_line(result)
if isfield(result, 'max_power_balance_mismatch')
    if isfield(result, 'line_loading_percent') && ~isempty(result.line_loading_percent)
        line_text = sprintf('max line=%.1f%%', max(result.line_loading_percent));
    else
        line_text = sprintf('max line flow=%.2f MVA', max(max(result.line_from_MVA, result.line_to_MVA)));
    end
    line = sprintf('%s: buses=%d, generators=%d, cost=%.2f $/h, mismatch=%.3g pu, %s', ...
        result.method, result.equivalent_bus_count, numel(result.generator_ids), result.total_cost, ...
        result.max_power_balance_mismatch, line_text);
else
    line = sprintf('%s: buses=%d, generators=%d, lambda=%.4f $/MWh, total cost=%.2f $/h, residual=%.3g MW', ...
        result.method, result.equivalent_bus_count, numel(result.generator_ids), result.lambda, ...
        result.total_cost, sum(result.P_generation_MW) - result.P_demand_MW);
end
end
