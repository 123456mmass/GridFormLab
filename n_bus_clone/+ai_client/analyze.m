function result = analyze(method, results)
%ANALYZE  Send power flow results to AI for analysis.
%
%   result = ai_client.analyze(method, results)
%
%   method  — solver name string, e.g. 'Newton-Raphson'
%   results — struct with fields:
%       .system_name     (char)
%       .num_buses       (double)
%       .num_lines       (double)
%       .iterations      (double)
%       .converged       (logical)
%       .P_loss_total    (double, pu)
%       .Q_loss_total    (double, pu)
%       .bus_data        (struct or [])
%       .mismatch_history (vector or [])
%
%   Returns struct with:
%       .analysis   — free-form text
%       .structured — parsed structured findings (or [])

data = struct(...
    'method',       method, ...
    'system_name',  char_or(results, 'system_name', 'Unknown'), ...
    'num_buses',    num_or(results, 'num_buses', 0), ...
    'num_lines',    num_or(results, 'num_lines', 0), ...
    'iterations',   num_or(results, 'iterations', 0), ...
    'converged',    logical_or(results, 'converged', true), ...
    'P_loss_total', num_or(results, 'P_loss_total', 0), ...
    'Q_loss_total', num_or(results, 'Q_loss_total', 0) ...
);

bd = value_or(results, 'bus_data', []);
if ~isempty(bd)
    data.bus_data = bd;
end
mh = value_or(results, 'mismatch_history', []);
if ~isempty(mh)
    data.mismatch_history = mh;
end

[resp, ok] = ai_client.call_api('/analyze', data);
if ok
    result = resp;
else
    result = resp;
end
end
