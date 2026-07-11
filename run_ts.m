%% 
%% RUN_TS Interactive in-house Transient Stability launcher.
% The selected-case result is saved as ts_result in the workspace.

% -------------------------------------------------------------------------
% USER SETTINGS
% These common settings are applied after choosing a case. Keep model and
% fault_bus commented to retain the selected case's own defaults.
ts_options = struct();
ts_options.t_end = 15.0;          % simulation end time (s)
ts_options.dt = 0.01;             % integration time step (s)
ts_options.t_fault = 1.0;         % fault application time (s)
ts_options.t_clear = 1.1;         % fault clearing time (s)
ts_options.Zf = 0 + 0.1j;         % fault impedance (pu): Rf + jXf
ts_options.method = 'trapezoidal';
ts_options.corrector_mode = 'adaptive';
ts_options.corrector_abs_tol = 1e-10;
ts_options.corrector_rel_tol = 1e-8;
ts_options.max_corrector_iter = 10;
ts_options.pm_mode = 'balanced';
ts_options.verbose = true;
ts_options.plot_results = true;

% Optional case-specific overrides -- uncomment only when required:
% ts_options.fault_bus = 15;
% ts_options.model = 'classical';
% ts_options.H = 5;                % scalar or one value per generator bus
% ts_options.D = 0;                % scalar or one value per generator bus
% ts_options.Xdp = 0.30;           % scalar or one value per generator bus
% For reproduction/diagnostic with fixed iterations:
% ts_options.corrector_mode = 'fixed';
% ts_options.corrector_iter = 3;
% -------------------------------------------------------------------------

pf_init_paths;
ts_result = solve_case('analysis','ts','options',ts_options);
