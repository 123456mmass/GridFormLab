function app = run_tests_action(app, fig)
%RUN_TESTS_ACTION Run automated test suite from the GUI.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'Running automated tests ...', ...
    'Executing regression checks for PF, CPF, and OPF.');
try
    import matlab.unittest.TestSuite;
    import matlab.unittest.TestRunner;
    import matlab.unittest.plugins.DiagnosticsValidationPlugin;

    tests_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'tests');
    pfapp.append_log(app, 'Running automated tests ...');

    if ~exist(tests_dir, 'dir')
        pfapp.append_log(app, 'No tests/ directory found.');
        app = pfapp.set_busy(app, false);
        return;
    end

    suite = TestSuite.fromFolder(tests_dir, 'IncludingSubfolders', false);
    if isempty(suite)
        pfapp.append_log(app, 'No test files found in tests/.');
        app = pfapp.set_busy(app, false);
        return;
    end

    runner = TestRunner.withTextOutput();
    runner.addPlugin(DiagnosticsValidationPlugin());

    pfapp.append_log(app, sprintf('Running %d test suites ...', numel(suite)));
    results = runner.run(suite);

    passed = sum([results.Passed]);
    failed = sum([results.Failed]);
    total = numel(results);
    duration = sum([results.Duration]);

    pfapp.append_log(app, sprintf('Tests complete: %d/%d passed, %d failed, %.1f s', ...
        passed, total, failed, duration));

    if failed > 0
        pfapp.append_log(app, 'FAILED TESTS:');
        for i = 1:numel(results)
            if results(i).Failed
                pfapp.append_log(app, sprintf('  FAIL: %s', results(i).Name));
            end
        end
    end

    % Update metric card
    if isfield(app, 'metric_title_1') && isfield(app, 'metric_value_1')
        app.metric_title_1.Text = 'TESTS';
        if failed == 0
            app.metric_value_1.Text = sprintf('%d/%d', passed, total);
            app.metric_caption_1.Text = 'All passed';
        else
            app.metric_value_1.Text = sprintf('%d fail', failed);
            app.metric_caption_1.Text = sprintf('%d/%d passed', passed, total);
        end
    end
catch err
    pfapp.append_log(app, sprintf('TEST ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'Tests Failed');
    catch
    end
end
app = pfapp.set_busy(app, false);
end
