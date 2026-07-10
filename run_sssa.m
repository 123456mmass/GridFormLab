%% RUN_SSSA Interactive in-house Small-Signal Stability launcher.
% The selected-case result is saved as sssa_result in the workspace.

% -------------------------------------------------------------------------
% USER SETTINGS
% Leave sssa_options.model unset to use the selected case's default model.
sssa_options = struct();
sssa_options.stability_tolerance = 1e-7;
sssa_options.fd_eps = 1e-6;
% Uncomment ONE line only when a model override is wanted:
% sssa_options.model = 'classical';
% sssa_options.model = 'emf6';      % requires compatible 6th-order data
% sssa_options.model = 'flux6';     % requires compatible 6th-order data
% -------------------------------------------------------------------------

pf_init_paths;
sssa_result = solve_case('analysis','sssa','options',sssa_options);
