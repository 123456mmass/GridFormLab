function line = powerflow_summary_line(result)
if ~isempty(result.mismatch_history)
    final_mismatch = result.mismatch_history(end);
else
    final_mismatch = NaN;
end
if result.converged
    status = 'CONVERGED';
else
    status = 'NOT CONVERGED';
end
line = sprintf('%s: %s, iterations=%d, final mismatch=%.6g, P_loss=%.6f pu, Vmin=%.4f pu, Vmax=%.4f pu', ...
    result.method, status, result.iterations, final_mismatch, result.P_loss_total, ...
    min(result.bus_voltage), max(result.bus_voltage));
if isfield(result, 'q_limit_switching') && ~isempty(result.q_limit_switching.events)
    line = sprintf('%s, Q-limit switches=%d', line, numel(result.q_limit_switching.events));
end
end
