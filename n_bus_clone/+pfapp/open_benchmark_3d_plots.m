function open_benchmark_3d_plots(case_labels, case_loaders, base_options, acceleration)
method_labels = {'NR', 'GS'};
num_cases = numel(case_labels);
num_methods = numel(method_labels);

loss = nan(num_methods, num_cases);
iterations = nan(num_methods, num_cases);
elapsed_time = nan(num_methods, num_cases);
vmin = nan(num_methods, num_cases);
angle_spread = nan(num_methods, num_cases);
angle_min = nan(num_methods, num_cases);

for c = 1:num_cases
    case_data = case_loaders{c}();

    nr_options = base_options;
    nr_options.max_iter = 80;
    nr_options.plot_results = false;
    nr_options.verbose = false;
    t_start = tic;
    nr = powerflow_newton_raphson(case_data, nr_options);
    elapsed_time(1, c) = toc(t_start);
    if nr.converged
        loss(1, c) = nr.P_loss_total;
        iterations(1, c) = nr.iterations;
        vmin(1, c) = min(nr.bus_voltage);
        angle_spread(1, c) = max(nr.bus_angle_deg) - min(nr.bus_angle_deg);
        angle_min(1, c) = min(nr.bus_angle_deg);
    end

    gs_options = base_options;
    gs_options.max_iter = 500;
    gs_options.acceleration = acceleration;
    gs_options.plot_results = false;
    gs_options.verbose = false;
    t_start = tic;
    gs = powerflow_gauss_seidel(case_data, gs_options);
    elapsed_time(2, c) = toc(t_start);
    if gs.converged
        loss(2, c) = gs.P_loss_total;
        iterations(2, c) = gs.iterations;
        vmin(2, c) = min(gs.bus_voltage);
        angle_spread(2, c) = max(gs.bus_angle_deg) - min(gs.bus_angle_deg);
        angle_min(2, c) = min(gs.bus_angle_deg);
    end
end

figure('Name', 'Power Flow Benchmark 3D Plots', 'Color', 'w', 'Position', [80 50 1280 790]);
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
pfapp.plot_metric_3d(loss, method_labels, case_labels, 'Total P Loss (pu)');
pfapp.plot_metric_3d(iterations, method_labels, case_labels, 'Converged Iterations');
pfapp.plot_metric_3d(elapsed_time, method_labels, case_labels, 'Computation Time (s)');
pfapp.plot_metric_3d(vmin, method_labels, case_labels, 'Minimum Voltage |V| (pu)');
pfapp.plot_metric_3d(angle_spread, method_labels, case_labels, 'Voltage Angle Spread (deg)');
pfapp.plot_metric_3d(abs(angle_min), method_labels, case_labels, 'Max Lagging Angle Magnitude (deg)');
sgtitle('PF Results Under Various Test Systems', 'FontWeight', 'bold');
end
