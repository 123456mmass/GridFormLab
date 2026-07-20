function point = sssa_load_sweep_point(base_case, alpha, pct, route, opt)
%SSSA_LOAD_SWEEP_POINT  Single-point evaluator for the SSSA load sweep.
%   POINT = sssa_load_sweep_point(BASE_CASE, ALPHA, PCT, ROUTE, OPT) evaluates
%   ONE load-sweep point at load scale ALPHA (= 1 + PCT/100). ROUTE selects
%   'sg' or 'ieee14_ibr'. The point is an independent fail-closed transaction:
%   any failure preserves failure ID, stage, residuals, diagnostics, and the
%   requested load scale.
%
%   Stages (each fail-closed with a typed failure_stage + failure_id):
%     INPUT_VALIDATION -> CASE_CONSTRUCTION -> PF -> DEVICE_BUILD ->
%     EQUILIBRIUM -> SSSA_LINEARIZATION -> MODAL_REPORTING
%
%   point.case_data stores the scaled snapshot BEFORE solver execution. A
%   separate working copy is passed into PF/equilibrium/SSSA so the stored
%   snapshot is never mutated by runtime-added solved fields.

point = struct();
point.load_percentage = pct;
point.alpha = alpha;
point.route = route;
point.status = 'FAILED';
point.failure_stage = '';
point.failure_id = '';
point.failure_reason = '';

% --- INPUT_VALIDATION -----------------------------------------------------
if ~isfinite(alpha) || ~isreal(alpha) || ~isscalar(alpha)
    point.failure_stage = 'INPUT_VALIDATION';
    point.failure_id = 'sssa_load_sweep_point:invalidAlpha';
    point.failure_reason = 'alpha must be a finite real scalar.';
    return;
end
if ~ismember(route, {'sg','ieee14_ibr','smib_ibr'})
    point.failure_stage = 'INPUT_VALIDATION';
    point.failure_id = 'sssa_load_sweep_point:unknownRoute';
    point.failure_reason = sprintf('Unknown route %s.', route);
    return;
end

% --- CASE_CONSTRUCTION ----------------------------------------------------
% The scale helper fails closed on dual-representation mismatch or missing
% mpc.bus when the route requires it.
scale_opt = opt;
scale_opt.requires_mpc = strcmp(route, 'ieee14_ibr');
try
    [scaled_snapshot, audit] = stability.sssa_load_sweep_scale_case( ...
        base_case, alpha, scale_opt);
catch err
    point.failure_stage = 'CASE_CONSTRUCTION';
    point.failure_id = err.identifier;
    point.failure_reason = err.message;
    return;
end
% Store the pre-solver immutable snapshot. Pass a separate working copy
% downstream so runtime-added solved fields never mutate the snapshot.
point.case_data = scaled_snapshot;
point.case_audit = audit;

% Deep-copy the working copy (force separate bus_data / mpc.bus matrices).
% smib_loaded_ibr/1.0 has no bus_data; just copy the smib_loaded_ibr struct.
working = scaled_snapshot;
if isfield(scaled_snapshot,'bus_data')
    working.bus_data = scaled_snapshot.bus_data;
end
if isfield(scaled_snapshot,'mpc') && isstruct(scaled_snapshot.mpc) && ...
        isfield(scaled_snapshot.mpc,'bus')
    working.mpc.bus = scaled_snapshot.mpc.bus;
end
if isfield(scaled_snapshot,'smib_loaded_ibr') && isstruct(scaled_snapshot.smib_loaded_ibr)
    working.smib_loaded_ibr = scaled_snapshot.smib_loaded_ibr;
end

% --- Route-specific PF + DEVICE_BUILD + EQUILIBRIUM + SSSA + MODAL ---------
scenario = [];
if isfield(opt,'scenario') && isstruct(opt.scenario)
    scenario = opt.scenario;
end
if isempty(scenario)
    scenario = struct();
end

switch route
    case 'ieee14_ibr'
        rp = stability.load_sweep.route_ieee14_ibr(working, scenario, opt);
    case 'sg'
        rp = stability.load_sweep.route_sg(working, scenario, opt);
    case 'smib_ibr'
        rp = stability.load_sweep.route_smib_ibr(working, scenario, opt);
end

% Merge route point fields.
merge_fields = {'pf','equilibrium','sssa','modal','devices','dev_meta', ...
    'failure_stage','failure_id','failure_reason'};
for k = 1:numel(merge_fields)
    if isfield(rp, merge_fields{k})
        point.(merge_fields{k}) = rp.(merge_fields{k});
    end
end

% --- Status determination -------------------------------------------------
if ~isempty(point.failure_stage) && ~isempty(point.failure_id)
    point.status = 'FAILED';
    % Ensure SSSA fields are empty (never success-looking defaults).
    if ~isfield(point,'sssa') || isempty(point.sssa)
        point.sssa = [];
    end
    if ~isfield(point,'modal') || isempty(point.modal)
        point.modal = [];
    end
    return;
end

point.status = 'SUCCESS';

% --- Record per-point SSSA diagnostics (when successful) -----------------
if isfield(point,'sssa') && ~isempty(point.sssa) && isstruct(point.sssa)
    s = point.sssa;
    point.sssa_diag = struct();
    if isfield(s,'eigenvalues')
        lam = s.eigenvalues(:);
        point.sssa_diag.eigenvalue_count = numel(lam);
        point.sssa_diag.max_real_eigenvalue = max(real(lam));
        tol = 1e-7;
        point.sssa_diag.unstable_roots = sum(real(lam) > tol);
        point.sssa_diag.marginal_roots = sum(abs(real(lam)) <= tol);
        point.sssa_diag.stable_roots = sum(real(lam) < -tol);
        % Oscillatory modes (nonzero imag).
        osc = abs(imag(lam)) > tol;
        if any(osc)
            lam_osc = lam(osc);
            re_osc = real(lam_osc);
            im_osc = imag(lam_osc);
            [max_re, idx] = max(re_osc);
            point.sssa_diag.critical_mode_frequency_Hz = abs(im_osc(idx))/(2*pi);
            point.sssa_diag.critical_mode_damping = -max_re / sqrt(max_re^2 + im_osc(idx)^2);
        end
    end
    if isfield(s,'gy_rcond'), point.sssa_diag.gy_rcond = s.gy_rcond; end
    if isfield(s,'A'), point.sssa_diag.A_size = size(s.A); end
    if isfield(s,'physical_A'), point.sssa_diag.has_physical_A = true; end
end
end
