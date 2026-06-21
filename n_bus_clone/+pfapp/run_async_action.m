function app = run_async_action(app, fig)
%RUN_ASYNC_ACTION Run selected solver asynchronously using parfeval (if PCT available).
%   Falls back to synchronous execution if Parallel Computing Toolbox is unavailable.

if isempty(ver('parallel'))
    pfapp.append_log(app, 'Parallel Computing Toolbox not available; running synchronously.');
    app = pfapp.run_selected_action(app, fig);
    return;
end

app = pfapp.set_busy(app, true);
pfapp.append_log(app, 'Launching async solver job...');

try
    case_data = pfapp.load_selected_case(app);
    method = app.method_dropdown.Value;

    switch method
        case 'Newton-Raphson'
            opts = pfapp.common_options(app.tolerance_field.Value);
            opts.max_iter = app.max_iter_field.Value;
            opts.enforce_q_limits = app.q_limit_checkbox.Value;
            opts.verbose = false;
            opts.plot_results = false;
            f = parfeval(@powerflow_newton_raphson, 1, case_data, opts);

        case 'Gauss-Seidel'
            opts = pfapp.common_options(app.tolerance_field.Value);
            opts.max_iter = app.max_iter_field.Value;
            opts.acceleration = app.accel_field.Value;
            opts.verbose = false;
            opts.plot_results = false;
            f = parfeval(@powerflow_gauss_seidel, 1, case_data, opts);

        otherwise
            pfapp.append_log(app, 'Async mode only supports NR and GS; running synchronously.');
            app = pfapp.set_busy(app, false);
            app = pfapp.run_selected_action(app, fig);
            return;
    end

    % Store future in app for later retrieval
    app.async_future = f;
    app.async_method = method;
    app.async_case_data = case_data;
    pfapp.append_log(app, sprintf('Async job queued: %s on %s', method, case_data.system_name));

    % Start a timer to poll for completion
    poll_timer = timer('ExecutionMode', 'fixedRate', 'Period', 0.5, ...
        'TimerFcn', @(~, ~) check_async_completion(), ...
        'ErrorFcn', @(~, ~) pfapp.append_log(app, 'Async polling error'));
    start(poll_timer);
    app.async_timer = poll_timer;

catch err
    pfapp.append_log(app, sprintf('ASYNC ERROR: %s', err.message));
    app = pfapp.set_busy(app, false);
end

    function check_async_completion()
        if strcmp(f.State, 'finished')
            stop(poll_timer);
            delete(poll_timer);
            try
                result = fetchOutputs(f);
                app.last_result = result{1};
                app.last_cpf = [];
                app.last_suite = [];
                app.last_opf = [];
                pfapp.show_powerflow_result(app, result{1}, app.tolerance_field.Value);
                pfapp.append_log(app, sprintf('Async done: %s converged=%d iter=%d', ...
                    method, result{1}.converged, result{1}.iterations));
            catch err2
                pfapp.append_log(app, sprintf('Async result error: %s', err2.message));
            end
            app = pfapp.set_busy(app, false);
        elseif strcmp(f.State, 'failed')
            stop(poll_timer);
            delete(poll_timer);
            pfapp.append_log(app, 'Async job failed.');
            app = pfapp.set_busy(app, false);
        end
    end
end
