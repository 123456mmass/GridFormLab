function result = analyze_cpf(results)
%ANALYZE_CPF  Send CPF results to AI for voltage stability analysis.
%
%   result = ai_client.analyze_cpf(results)
%
%   results — struct with fields:
%       .method        (char, default 'CPF Predictor-Corrector')
%       .system_name   (char)
%       .num_buses     (double)
%       .target_bus    (double)
%       .num_points    (double)
%       .nose_detected (logical)
%       .lambda_min    (double)
%       .lambda_max    (double)
%       .voltage_min   (double)
%       .voltage_max   (double)
%       .stop_reason   (char)
%
%   Returns struct with:
%       .analysis   — free-form text
%       .structured — parsed risk assessment (or [])

data = struct(...
    'method',        char_or(results, 'method', 'CPF Predictor-Corrector'), ...
    'system_name',   char_or(results, 'system_name', 'Unknown'), ...
    'num_buses',     num_or(results, 'num_buses', 0), ...
    'target_bus',    num_or(results, 'target_bus', 0), ...
    'num_points',    num_or(results, 'num_points', 0), ...
    'nose_detected', logical_or(results, 'nose_detected', false), ...
    'lambda_min',    num_or(results, 'lambda_min', 0), ...
    'lambda_max',    num_or(results, 'lambda_max', 0), ...
    'voltage_min',   num_or(results, 'voltage_min', 0), ...
    'voltage_max',   num_or(results, 'voltage_max', 0), ...
    'stop_reason',   char_or(results, 'stop_reason', '') ...
);

[resp, ok] = ai_client.call_api('/analyze/cpf', data);
if ok
    result = resp;
else
    result = resp;
end
end
