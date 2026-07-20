function result = sssa_load_sweep(case_data, opt)
%SSSA_LOAD_SWEEP  Generic SSSA load-sweep orchestrator (public entry point).
%   RESULT = stability.sssa_load_sweep(CASE_DATA, OPT) evaluates a declared
%   sequence of independently solved loading points. For each point:
%     1. construct the scaled case (constant power factor);
%     2. rebuild devices / scenario;
%     3. solve PF + dynamic equilibrium;
%     4. linearize the accepted equilibrium via full-KCL SSSA;
%     5. report equilibrium, limit, conditioning, spectrum, stability metrics.
%
%   Each load point is an independent fail-closed transaction. A failure at
%   one point preserves its failure ID, stage, residuals, diagnostics, and
%   requested load scale, then continues with every later independent point.
%   Abort the entire sweep only for request-level failures (invalid
%   percentages, malformed schema, unsupported contract, missing mpc.bus for a
%   consumer that needs it).
%
%   Mode tracking runs AFTER all points (reporting-only, does not feed back).
%   result.sssa_load_sweep attaches additively; existing single-point SSSA
%   fields are never mutated.

arguments
    case_data struct
    opt struct = struct()
end

result = struct();
result.sssa_load_sweep = struct();
result.sssa_load_sweep.schema_version = 'sssa_load_sweep/1.0';
result.sssa_load_sweep.case_id = option_value(opt,'case_id','');

% --- Request-level validation ---------------------------------------------
percentages = option_value(opt,'sssa_load_percentages',[20 40 60 80]);
validate_percentages(percentages);

policy = option_value(opt,'sssa_load_scaling_policy','constant_power_factor');
if ~strcmp(policy,'constant_power_factor')
    error('sssa_load_sweep:unsupportedScalingPolicy', ...
        'Only constant_power_factor scaling policy is supported; got %s.', policy);
end

% Applicability.
[applicable, reason, route_hint] = stability.load_sweep.applicability(case_data);
if ~applicable
    result.sssa_load_sweep.applicability = struct( ...
        'applicable', false, 'reason', reason);
    result.sssa_load_sweep.load_percentages = percentages;
    result.sssa_load_sweep.load_scales = 1 + percentages/100;
    result.sssa_load_sweep.points = struct([]);
    result.sssa_load_sweep.mode_tracking = struct('available', false, ...
        'reason', reason);
    result.sssa_load_sweep.summary_table = struct();
    result.sssa_load_sweep.figure_files = {};
    result.converged = false;
    result.failure_id = 'sssa_load_sweep:notApplicable';
    result.failure_reason = reason;
    return;
end

% Route resolution: smib_ibr for smib_loaded_ibr; ieee14_ibr if scenario/IBR
% config present; else sg.
route = option_value(opt,'route','');
if isempty(route)
    if isfield(case_data,'smib_loaded_ibr') && isstruct(case_data.smib_loaded_ibr)
        route = 'smib_ibr';
    elseif isfield(opt,'scenario') && ~isempty(opt.scenario)
        route = 'ieee14_ibr';
    else
        route = 'sg';
    end
end
result.sssa_load_sweep.applicability = struct( ...
    'applicable', true, 'reason', '', 'route', route);

% --- Per-point evaluation (independent transactions) ---------------------
alphas = 1 + percentages/100;
npts = numel(percentages);
points = cell(npts,1);
for k = 1:npts
    points{k} = stability.sssa_load_sweep_point( ...
        case_data, alphas(k), percentages(k), route, opt);
end
result.sssa_load_sweep.points = points;

% --- Mode tracking (reporting-only, after all points) --------------------
result.sssa_load_sweep.mode_tracking = stability.sssa_load_sweep_mode_match(points, opt);

% --- Summary table --------------------------------------------------------
result.sssa_load_sweep.summary_table = stability.sssa_load_sweep_tables(points);

% --- Plots (headless) -----------------------------------------------------
plot_opt = struct('visible', logical(option_value(opt,'sssa_plot_visible',true)), ...
    'save_plots', logical(option_value(opt,'sssa_save_plots',true)), ...
    'case_id', result.sssa_load_sweep.case_id, ...
    'output_root', option_value(opt,'output_root',''));
if plot_opt.save_plots
    [fig_files, plot_status] = stability.sssa_load_sweep_plots(points, ...
        result.sssa_load_sweep.mode_tracking, plot_opt);
    result.sssa_load_sweep.figure_files = fig_files;
    result.sssa_load_sweep.plot_status = plot_status;
else
    result.sssa_load_sweep.figure_files = {};
end

% --- Overall convergence --------------------------------------------------
% A sweep "converges" only if every requested point succeeded. Individual
% point failures are preserved in points{k}; the sweep does NOT abort.
success = cellfun(@(p) strcmp(p.status,'SUCCESS'), points);
result.converged = all(success);
result.sssa_load_sweep.load_percentages = percentages;
result.sssa_load_sweep.load_scales = alphas;
result.sssa_load_sweep.point_status = cellfun(@(p) p.status, points, ...
    'UniformOutput', false).';
if ~result.converged
    failed_idx = find(~success);
    result.failure_id = 'sssa_load_sweep:pointFailures';
    result.failure_reason = sprintf( ...
        '%d of %d load points failed: indices [%s].', ...
        numel(failed_idx), npts, num2str(failed_idx));
else
    result.failure_id = '';
    result.failure_reason = '';
end
end

function validate_percentages(percentages)
% Validate in user-entered order. Strictly increasing and unique.
% No sort, dedup, clip, or canonicalization.
if ~isnumeric(percentages) || ~isvector(percentages) || isempty(percentages)
    error('sssa_load_sweep:invalidPercentages', ...
        'sssa_load_percentages must be a nonempty numeric vector.');
end
percentages = percentages(:).';
if ~isreal(percentages) || any(~isfinite(percentages))
    error('sssa_load_sweep:invalidPercentages', ...
        'sssa_load_percentages must be finite real values.');
end
if any(percentages < 0)
    error('sssa_load_sweep:invalidPercentages', ...
        'sssa_load_percentages must be nonnegative.');
end
if numel(unique(percentages)) ~= numel(percentages)
    error('sssa_load_sweep:invalidPercentages', ...
        'sssa_load_percentages must be unique.');
end
if ~all(diff(percentages) > 0)
    error('sssa_load_sweep:invalidPercentages', ...
        'sssa_load_percentages must be strictly increasing.');
end
end

function value = option_value(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end
