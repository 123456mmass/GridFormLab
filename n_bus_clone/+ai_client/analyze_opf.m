function result = analyze_opf(results)
%ANALYZE_OPF  Send OPF / economic dispatch results to AI for analysis.
%
%   result = ai_client.analyze_opf(results)
%
%   results — struct with fields:
%       .system_name      (char)
%       .demand_MW        (double)
%       .total_cost       (double, $/h)
%       .lambda_cost      (double, $/MWh)
%       .balance_residual (double, MW)
%       .generators       (struct array with id, P_MW, cost, limit)
%
%   Returns struct with:
%       .analysis   — free-form text
%       .structured — parsed dispatch assessment (or [])

gen_array = {};
if isfield(results, 'generators') && ~isempty(results.generators)
    gens = results.generators;
    for i = 1:numel(gens)
        % Preserve the original limit value (char or numeric) without
        % coercing numeric limits to 'free'.
        lim = value_or(gens(i), 'limit', 'free');
        if isnumeric(lim)
            lim = num2str(lim);
        end
        gen_array{end+1} = struct(...
            'id',    char_or(gens(i), 'id', num2str(i)), ...
            'P_MW',  num_or(gens(i), 'P_MW', 0), ...
            'cost',  num_or(gens(i), 'cost', 0), ...
            'limit', lim ...
        );
    end
end

data = struct(...
    'system_name',      char_or(results, 'system_name', 'Unknown'), ...
    'demand_MW',        num_or(results, 'demand_MW', 0), ...
    'total_cost',       num_or(results, 'total_cost', 0), ...
    'lambda_cost',      num_or(results, 'lambda_cost', 0), ...
    'balance_residual', num_or(results, 'balance_residual', 0), ...
    'generators',       {gen_array} ...
);

[resp, ok] = ai_client.call_api('/analyze/opf', data);
if ok
    result = resp;
else
    result = resp;
end
end
