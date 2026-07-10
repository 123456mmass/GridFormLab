%% RUN_POWERFLOW Interactive in-house Newton-Raphson Power Flow launcher.
% Press Run in the MATLAB Editor. The result is saved as pf_result in the
% workspace; the semicolon prevents MATLAB from printing an `ans` struct.

% -------------------------------------------------------------------------
% USER SETTINGS
% Edit these values only when needed. They apply to whichever case is
% selected in the dialog below.
pf_options = struct();
pf_options.tolerance = 1e-10;
pf_options.max_iter = 50;
pf_options.enforce_q_limits = true;
pf_options.q_limit_tolerance = 1e-6;
pf_options.max_q_limit_switches = 20;
pf_options.verbose = true;
pf_options.plot_results = true;
% -------------------------------------------------------------------------

pf_init_paths;
pf_result = solve_case('analysis','pf','options',pf_options);
