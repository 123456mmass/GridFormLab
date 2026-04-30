function app = run_tests_action(app, fig)
%RUN_TESTS_ACTION Run automated test suite from the GUI.
%   Returns modified app struct.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'Running automated tests ...', ...
    'Executing regression checks for PF, CPF, and OPF.');
try
    pfapp.append_log(app, 'Running automated tests ...');
    summary = run_powerflow_tests();
    pfapp.append_log(app, sprintf('Tests passed=%d failed=%d', ...
        summary.passed, summary.failed));
catch err
    pfapp.append_log(app, sprintf('TEST ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'Tests Failed');
    catch
    end
end
app = pfapp.set_busy(app, false);
end
