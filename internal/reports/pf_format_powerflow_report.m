function lines = pf_format_powerflow_report(results)
%PF_FORMAT_POWERFLOW_REPORT Build a detailed console-style PF report.
%   LINES is a cell array of character vectors ready for TXT/PDF export.

system_name = char(get_field(results, 'system_name', 'Power Flow System'));
method_name = char(get_field(results, 'method', 'Power Flow'));
method_title = method_label(method_name);

base_values = get_field(results, 'base_values', struct());
S_base = get_field(base_values, 'S_base_MVA', 100);
V_base = get_field(base_values, 'V_base_kV', NaN);
frequency = get_field(base_values, 'frequency_Hz', NaN);

bus_ids = results.external_bus_ids(:);
bus_type = results.bus_type(:);
slack_ids = bus_ids(bus_type == 1);
pv_ids = bus_ids(bus_type == 2);
pq_ids = bus_ids(bus_type == 3);
num_buses = numel(bus_ids);
num_lines = size(results.line_endpoints, 1);
num_delta = numel(pv_ids) + numel(pq_ids);
num_voltage = numel(pq_ids);
num_unknowns = num_delta + num_voltage;

shunt_used = abs(get_field(results, 'P_shunt_injected_total', 0)) > 1e-10 || ...
    abs(get_field(results, 'Q_shunt_injected_total', 0)) > 1e-10;
P_balance = results.P_total_gen - results.P_total_load - results.P_loss_total;
Q_balance = results.Q_total_gen - results.Q_total_load - results.Q_loss_total;
if shunt_used
    P_balance = P_balance + results.P_shunt_injected_total;
    Q_balance = Q_balance + results.Q_shunt_injected_total;
end

lines = {};
add('===========================================================');
add(sprintf('       %s POWER FLOW ANALYSIS', upper(system_name)));
add(sprintf('       %s', method_title));
add('============================================================');
add('');

add('System Base Values:');
add(sprintf('  S_base = %g MVA', S_base));
if isfinite(V_base) && V_base > 0
    add(sprintf('  V_base = %g kV', V_base));
else
    add('  V_base = N/A');
end
if isfinite(frequency) && frequency > 0
    add(sprintf('  Frequency = %g Hz', frequency));
else
    add('  Frequency = N/A');
end
add('');

add('Bus Data:');
add(sprintf('  Number of buses: %d', num_buses));
add(sprintf('  Slack buses: %d', numel(slack_ids)));
add(sprintf('  PV buses: %d', numel(pv_ids)));
add(sprintf('  PQ buses: %d', numel(pq_ids)));
add('');

add('Transmission Line Data:');
add(sprintf('  Number of lines: %d', num_lines));
add('');

add('Building Y-bus matrix...');
add('Y-bus matrix constructed successfully.');
add(sprintf('  System has %d buses and %d transmission lines', num_buses, num_lines));
add('');

add('Bus Classification:');
add(sprintf('  Slack buses:%s', format_bus_ids(slack_ids)));
add('');
add(sprintf('  PV buses:%s', format_bus_ids(pv_ids)));
add('');
add(sprintf('  PQ buses:%s', format_bus_ids(pq_ids)));
add('');
add('');

add('Number of unknowns:');
add(sprintf('  Voltage angles (delta): %d', num_delta));
add(sprintf('  Voltage magnitudes (|V|): %d', num_voltage));
add(sprintf('  Total unknowns: %d', num_unknowns));
add('');

add('============================================================');
add(sprintf('  %s ITERATION', upper(method_name)));
add('============================================================');
add('');

mismatch_history = get_field(results, 'mismatch_history', []);
if isempty(mismatch_history)
    add('Iteration history is not available.');
else
    mismatch_history = mismatch_history(:);
    for iter = 1:numel(mismatch_history)
        add(sprintf('Iteration %2d: Max Mismatch = %.6e', iter, mismatch_history(iter)));
    end
end
add('');

if get_field(results, 'converged', false)
    add(sprintf('*** CONVERGED in %d iterations ***', get_field(results, 'iterations', numel(mismatch_history))));
else
    add(sprintf('*** WARNING: Did not converge in %d iterations ***', get_field(results, 'iterations', numel(mismatch_history))));
end
add('');

if isfield(results, 'q_limit_switching') && isfield(results.q_limit_switching, 'events') && ~isempty(results.q_limit_switching.events)
    add('Q-limit switching events:');
    for i = 1:numel(results.q_limit_switching.events)
        event = results.q_limit_switching.events(i);
        add(sprintf('  Round %d, Bus %d: %s -> %s, Qg %.6f pu fixed at %s %.6f pu', ...
            event.round, event.bus_id, event.from_type, event.to_type, ...
            event.Q_generation_before, event.limit_type, event.Q_fixed));
    end
    add('');
end

add('============================================================');
add('  LINE FLOW CALCULATIONS');
add('============================================================');
add('');
add('');

add('================================================================');
add('                     POWER FLOW RESULTS');
add('================================================================');
add('');

add('------------------------------------------------------------');
add('                    BUS VOLTAGES');
add('------------------------------------------------------------');
add(sprintf('%-6s %-8s %-10s %-10s %-12s %-10s', ...
    'Bus', 'Type', '|V| (pu)', '|V| (kV)', 'Angle (deg)', 'Angle (rad)'));
add('------------------------------------------------------------');
for i = 1:num_buses
    add(sprintf('%-6g %-8s %-10.4f %-10.2f %-12.4f %-10.4f', ...
        bus_ids(i), bus_type_name(bus_type(i)), results.bus_voltage(i), ...
        results.bus_voltage_kV(i), results.bus_angle_deg(i), results.bus_angle(i)));
end
add('');

add('------------------------------------------------------------');
add('              POWER GENERATION AND LOAD');
add('------------------------------------------------------------');
add(sprintf('%-6s %-12s %-12s %-12s %-12s', ...
    'Bus', 'P_gen (pu)', 'Q_gen (pu)', 'P_load (pu)', 'Q_load (pu)'));
add('------------------------------------------------------------');
for i = 1:num_buses
    add(sprintf('%-6g %-12.4f %-12.4f %-12.4f %-12.4f', ...
        bus_ids(i), results.P_generation(i), results.Q_generation(i), ...
        results.P_load(i), results.Q_load(i)));
end
add('');

add('------------------------------------------------------------');
add('                 POWER BALANCE SUMMARY');
add('------------------------------------------------------------');
add('Total Generation:');
add(sprintf('  P_gen = %.4f pu (%.2f MW)', results.P_total_gen, results.P_total_gen * S_base));
add(sprintf('  Q_gen = %.4f pu (%.2f MVAr)', results.Q_total_gen, results.Q_total_gen * S_base));
add('');
add('Total Load:');
add(sprintf('  P_load = %.4f pu (%.2f MW)', results.P_total_load, results.P_total_load * S_base));
add(sprintf('  Q_load = %.4f pu (%.2f MVAr)', results.Q_total_load, results.Q_total_load * S_base));
add('');
add('Total Losses:');
add(sprintf('  P_loss = %.4f pu (%.2f MW)', results.P_loss_total, results.P_loss_total * S_base));
add(sprintf('  Q_loss = %.4f pu (%.2f MVAr)', results.Q_loss_total, results.Q_loss_total * S_base));
add('');
if shunt_used
    add('Total Bus Shunt Injection:');
    add(sprintf('  P_shunt_inj = %.4f pu (%.2f MW)', results.P_shunt_injected_total, results.P_shunt_injected_total * S_base));
    add(sprintf('  Q_shunt_inj = %.4f pu (%.2f MVAr)', results.Q_shunt_injected_total, results.Q_shunt_injected_total * S_base));
    add('');
end
add('Balance Check:');
if shunt_used
    add(sprintf('  P_gen + P_shunt_inj - P_load - P_loss = %.6e pu', P_balance));
    add(sprintf('  Q_gen + Q_shunt_inj - Q_load - Q_loss = %.6e pu', Q_balance));
else
    add(sprintf('  P_gen - P_load - P_loss = %.6e pu', P_balance));
    add(sprintf('  Q_gen - Q_load - Q_loss = %.6e pu', Q_balance));
end
add('');

add('------------------------------------------------------------');
add('                    LINE FLOW REPORT');
add('------------------------------------------------------------');
add(sprintf('%-5s %-5s %-11s %-11s %-11s %-11s', ...
    'From', 'To', 'P_from (pu)', 'Q_from (pu)', 'P_loss (pu)', 'Q_loss (pu)'));
add('------------------------------------------------------------');
for i = 1:num_lines
    add(sprintf('%-5g %-5g %-11.4f %-11.4f %-11.6f %-11.6f', ...
        results.line_endpoints(i, 1), results.line_endpoints(i, 2), ...
        results.line_flow_P(i), results.line_flow_Q(i), ...
        results.line_loss_P(i), results.line_loss_Q(i)));
end
add('');

add('================================================================');
add('                    END OF REPORT');
add('================================================================');
add('');
add('Results saved to variable ''results'' in workspace.');
add('To save as .mat file: save(''powerflow_results.mat'', ''results'')');

    function add(text)
        lines{end + 1, 1} = text;
    end
end

function value = get_field(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    value = s.(field_name);
else
    value = default_value;
end
end

function label = method_label(method_name)
if contains(lower(method_name), 'method')
    label = method_name;
else
    label = sprintf('%s Method', method_name);
end
end

function text = format_bus_ids(ids)
if isempty(ids)
    text = '      (none)';
else
    text = sprintf('%7g', ids(:).');
end
end

function name = bus_type_name(bus_type)
switch bus_type
    case 1
        name = 'Slack';
    case 2
        name = 'PV';
    case 3
        name = 'PQ';
    otherwise
        name = 'Unknown';
end
end
