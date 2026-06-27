function results = run_nbus_example()
%RUN_NBUS_EXAMPLE Run the IEEE 5-bus NR example.

pf_init_paths();
case_data = case_ieee5bus();

options = struct( ...
    'max_iter', 20, ...
    'tolerance', 1e-6, ...
    'plot_results', true, ...
    'verbose', true);

results = powerflow_newton_raphson(case_data, options);
end
