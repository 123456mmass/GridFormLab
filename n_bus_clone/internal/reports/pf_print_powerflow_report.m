function pf_print_powerflow_report(results)
%PF_PRINT_POWERFLOW_REPORT Print a consistent text report for solver output.

S_base = results.base_values.S_base_MVA;
bus_type_str = {'Slack', 'PV', 'PQ'};

fprintf('================================================================\n');
fprintf('                     POWER FLOW RESULTS\n');
fprintf('                     %s\n', upper(results.method));
fprintf('================================================================\n\n');

fprintf('------------------------------------------------------------\n');
fprintf('                    BUS VOLTAGES\n');
fprintf('------------------------------------------------------------\n');
fprintf('%-8s %-8s %-10s %-10s %-12s %-12s\n', 'Bus', 'Type', '|V| (pu)', '|V| (kV)', 'Angle (deg)', 'Angle (rad)');
fprintf('------------------------------------------------------------\n');
for i = 1:numel(results.external_bus_ids)
    fprintf('%-8d %-8s %-10.4f %-10.2f %-12.4f %-12.4f\n', ...
        results.external_bus_ids(i), bus_type_str{results.bus_type(i)}, ...
        results.bus_voltage(i), results.bus_voltage_kV(i), ...
        results.bus_angle_deg(i), results.bus_angle(i));
end
fprintf('\n');

fprintf('------------------------------------------------------------\n');
fprintf('              POWER GENERATION, LOAD, AND NET INJECTION\n');
fprintf('------------------------------------------------------------\n');
fprintf('%-8s %-12s %-12s %-12s %-12s %-12s %-12s\n', ...
    'Bus', 'P_gen', 'Q_gen', 'P_load', 'Q_load', 'P_net', 'Q_net');
fprintf('------------------------------------------------------------\n');
for i = 1:numel(results.external_bus_ids)
    fprintf('%-8d %-12.4f %-12.4f %-12.4f %-12.4f %-12.4f %-12.4f\n', ...
        results.external_bus_ids(i), results.P_generation(i), results.Q_generation(i), ...
        results.P_load(i), results.Q_load(i), ...
        results.P_generation(i) - results.P_load(i), results.Q_generation(i) - results.Q_load(i));
end
fprintf('\n');

fprintf('------------------------------------------------------------\n');
fprintf('                 POWER BALANCE SUMMARY\n');
fprintf('------------------------------------------------------------\n');
fprintf('Total Generation:\n');
fprintf('  P_gen = %.4f pu (%.2f MW)\n', results.P_total_gen, results.P_total_gen * S_base);
fprintf('  Q_gen = %.4f pu (%.2f MVAr)\n', results.Q_total_gen, results.Q_total_gen * S_base);
fprintf('\n');
fprintf('Total Load:\n');
fprintf('  P_load = %.4f pu (%.2f MW)\n', results.P_total_load, results.P_total_load * S_base);
fprintf('  Q_load = %.4f pu (%.2f MVAr)\n', results.Q_total_load, results.Q_total_load * S_base);
fprintf('\n');
fprintf('Total Losses:\n');
fprintf('  P_loss = %.4f pu (%.2f MW)\n', results.P_loss_total, results.P_loss_total * S_base);
fprintf('  Q_loss = %.4f pu (%.2f MVAr)\n', results.Q_loss_total, results.Q_loss_total * S_base);
fprintf('\n');
fprintf('Total Bus Shunt Injection:\n');
fprintf('  P_shunt_inj = %.4f pu (%.2f MW)\n', results.P_shunt_injected_total, results.P_shunt_injected_total * S_base);
fprintf('  Q_shunt_inj = %.4f pu (%.2f MVAr)\n', results.Q_shunt_injected_total, results.Q_shunt_injected_total * S_base);
fprintf('\n');
fprintf('Balance Check:\n');
fprintf('  P_gen + P_shunt_inj - P_load - P_loss = %.6e pu\n', ...
    results.P_total_gen + results.P_shunt_injected_total - results.P_total_load - results.P_loss_total);
fprintf('  Q_gen + Q_shunt_inj - Q_load - Q_loss = %.6e pu\n', ...
    results.Q_total_gen + results.Q_shunt_injected_total - results.Q_total_load - results.Q_loss_total);
fprintf('\n');

fprintf('------------------------------------------------------------\n');
fprintf('                    LINE FLOW REPORT\n');
fprintf('------------------------------------------------------------\n');
fprintf('%-8s %-8s %-10s %-10s %-12s %-12s\n', 'From', 'To', 'P_from', 'Q_from', 'P_loss', 'Q_loss');
fprintf('------------------------------------------------------------\n');
for i = 1:size(results.line_endpoints, 1)
    fprintf('%-8d %-8d %-10.4f %-10.4f %-12.6f %-12.6f\n', ...
        results.line_endpoints(i, 1), results.line_endpoints(i, 2), ...
        results.line_flow_P(i), results.line_flow_Q(i), ...
        results.line_loss_P(i), results.line_loss_Q(i));
end
fprintf('\n');
end
