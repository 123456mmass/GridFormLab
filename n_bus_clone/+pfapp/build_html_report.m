function html = build_html_report(data)
%BUILD_HTML_REPORT Generate a standalone HTML5 report from export data.

sys_name = char(data.system_name);
method = char(data.method);

rows = {};
rows{end+1} = '<!DOCTYPE html>';
rows{end+1} = '<html lang="en">';
rows{end+1} = '<head>';
rows{end+1} = '<meta charset="UTF-8">';
rows{end+1} = '<meta name="viewport" content="width=device-width, initial-scale=1.0">';
rows{end+1} = sprintf('<title>%s - %s</title>', sys_name, method);
rows{end+1} = '<style>';
rows{end+1} = build_css();
rows{end+1} = '</style>';
rows{end+1} = '</head>';
rows{end+1} = '<body>';
rows{end+1} = '<div class="container">';
rows{end+1} = sprintf('<h1>%s</h1>', sys_name);
rows{end+1} = sprintf('<p class="subtitle">%s &mdash; Power Flow Analysis Report</p>', method);
rows{end+1} = '<hr>';

% Summary cards
rows{end+1} = '<div class="cards">';
if isfield(data, 'converged')
    conv_str = ternary(data.converged, 'Yes', 'No');
    conv_class = ternary(data.converged, 'badge-ok', 'badge-fail');
    rows{end+1} = sprintf('<div class="card"><span class="label">Converged</span><span class="%s">%s</span></div>', conv_class, conv_str);
end
if isfield(data, 'iterations')
    rows{end+1} = sprintf('<div class="card"><span class="label">Iterations</span><span class="value">%d</span></div>', data.iterations);
end
if isfield(data, 'P_loss_total')
    rows{end+1} = sprintf('<div class="card"><span class="label">P Loss</span><span class="value">%.6f pu</span></div>', data.P_loss_total);
end
if isfield(data, 'Q_loss_total')
    rows{end+1} = sprintf('<div class="card"><span class="label">Q Loss</span><span class="value">%.6f pu</span></div>', data.Q_loss_total);
end
if isfield(data, 'total_cost')
    rows{end+1} = sprintf('<div class="card"><span class="label">Total Cost</span><span class="value">%.2f $/h</span></div>', data.total_cost);
end
if isfield(data, 'lambda')
    rows{end+1} = sprintf('<div class="card"><span class="label">System Lambda</span><span class="value">%.4f $/MWh</span></div>', data.lambda);
end
rows{end+1} = '</div>';

% Bus table
if isfield(data, 'bus_voltage') && ~isempty(data.bus_voltage)
    rows{end+1} = '<h2>Bus Results</h2>';
    rows{end+1} = '<table><thead><tr><th>Bus</th><th>|V| (pu)</th><th>Angle (deg)</th></tr></thead><tbody>';
    bus_ids = data.external_bus_ids;
    for i = 1:numel(data.bus_voltage)
        angle = 0;
        if isfield(data, 'bus_angle_deg') && numel(data.bus_angle_deg) >= i
            angle = data.bus_angle_deg(i);
        end
        rows{end+1} = sprintf('<tr><td>%d</td><td>%.6f</td><td>%.4f</td></tr>', bus_ids(i), data.bus_voltage(i), angle);
    end
    rows{end+1} = '</tbody></table>';
end

% Generator dispatch
if isfield(data, 'P_generation_MW') && ~isempty(data.P_generation_MW)
    rows{end+1} = '<h2>Generator Dispatch</h2>';
    rows{end+1} = '<table><thead><tr><th>Gen</th><th>P (MW)</th><th>Cost ($/h)</th></tr></thead><tbody>';
    for i = 1:numel(data.P_generation_MW)
        cost = 0;
        if isfield(data, 'generator_cost') && numel(data.generator_cost) >= i
            cost = data.generator_cost(i);
        end
        gen_id = i;
        if isfield(data, 'generator_ids') && numel(data.generator_ids) >= i
            gen_id = data.generator_ids(i);
        end
        rows{end+1} = sprintf('<tr><td>%d</td><td>%.4f</td><td>%.2f</td></tr>', gen_id, data.P_generation_MW(i), cost);
    end
    rows{end+1} = '</tbody></table>';
end

% CPF
if isfield(data, 'nose_detected')
    rows{end+1} = '<h2>CPF Results</h2>';
    rows{end+1} = sprintf('<p>Target Bus: %d | Nose: %s | Lambda: %.4f - %.4f | V: %.4f - %.4f pu</p>', ...
        data.target_bus, ternary(data.nose_detected, 'Detected', 'Not detected'), ...
        data.lambda_min, data.lambda_max, data.voltage_min, data.voltage_max);
end

rows{end+1} = sprintf('<p class="footer">Generated %s by N-Bus Power Flow Studio</p>', char(datetime('now')));
rows{end+1} = '</div></body></html>';

html = strjoin(rows, newline);

    function css = build_css()
        css = [ ...
            'body{font-family:"Segoe UI",system-ui,sans-serif;background:#f0f2f5;margin:0;padding:20px;color:#1a1a2e}', ...
            '.container{max-width:900px;margin:0 auto;background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,.08)}', ...
            'h1{font-size:24px;margin:0;color:#0066a1}', ...
            '.subtitle{color:#667;margin:4px 0 20px}', ...
            '.cards{display:flex;gap:16px;flex-wrap:wrap;margin:20px 0}', ...
            '.card{flex:1;min-width:140px;background:#f5f7fa;padding:16px;border-radius:8px;text-align:center}', ...
            '.label{display:block;font-size:10px;text-transform:uppercase;color:#889;margin-bottom:6px}', ...
            '.value{font-size:20px;font-weight:700;color:#1a1a2e}', ...
            '.badge-ok{font-size:20px;font-weight:700;color:#267a3a}', ...
            '.badge-fail{font-size:20px;font-weight:700;color:#c0392b}', ...
            'table{width:100%;border-collapse:collapse;margin:16px 0}', ...
            'th,td{padding:10px 14px;text-align:left;border-bottom:1px solid #e8ecf0}', ...
            'th{background:#f5f7fa;font-size:11px;text-transform:uppercase;color:#667}', ...
            'tr:hover{background:#fafbfc}', ...
            '.footer{color:#aab;font-size:11px;margin-top:30px;text-align:center}', ...
            'hr{border:none;border-top:1px solid #e8ecf0}'];
    end

    function out = ternary(cond, t, f)
        if cond, out = t; else, out = f; end
    end
end
