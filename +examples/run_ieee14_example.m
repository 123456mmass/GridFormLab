function results = run_ieee14_example()
%RUN_IEEE14_EXAMPLE Run the IEEE 14-bus NR example.

pf_init_paths();
case_data = case_ieee14bus();

options = struct( ...
    'max_iter', 30, ...
    'tolerance', 1e-6, ...
    'plot_results', true, ...
    'verbose', true);

results = powerflow_newton_raphson(case_data, options);
end
