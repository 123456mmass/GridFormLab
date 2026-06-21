function results = powerflow_newton_raphson(case_data, options)
pf_init_paths();
if nargin < 1
    case_data = [];
end
if nargin < 2
    options = struct();
end
results = pfsolver.powerflow_newton_raphson(case_data, options);
end
