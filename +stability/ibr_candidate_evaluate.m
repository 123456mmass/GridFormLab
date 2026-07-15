function cand = ibr_candidate_evaluate(case_data, resources, candidate, scr_metrics, gamma_req, opt)
%IBR_CANDIDATE_EVALUATE  Evaluate one exact-size GFM subset: SCR + equilibrium + SSSA.
%
%   CAND = ibr_candidate_evaluate(CASE_DATA, RESOURCES, CANDIDATE, SCR_METRICS,
%       GAMMA_REQ, OPT) evaluates a single candidate configuration.
%
%   CANDIDATE must contain:
%     selected_gfm_indices, reference_resource_index, n_gfm_required,
%     resource_ids, modes (cell), online, resource_type, n_mode_changes, tie_break, ordering_key
%
%   Steps (PROJECT_DERIVED, no external solver):
%     1. SCR gate for GFL remainder (uses scr_metrics per-resource)
%     2. Build devices via production builder (build_mixed_resource_devices)
%     3. Build hybrid_state via ts_hybrid_state_init + apply candidate modes
%     4. mixed_equilibrium_solve with exact tuple
%     5. physical_kcl_norm <=1e-6 gate
%     6. full-KCL composite_sssa_model with exact u_eq/context/active
%     7. gamma_req frozen before evaluation, pass when max(real(lambda)) <= -gamma_req
%     8. No eigenvalue deletion after eig, store full set + reduction metadata
%
%   Output CAND extended with:
%     topology_evaluated, scr_evaluated, scr_pass, equilibrium_evaluated,
%     sssa_evaluated, physical_kcl_norm, equilibrium_converged, sssa_pass,
%     margin, omega, eigenvalues, gy_rcond, feasible, ready_to_commit, reason, failure_id

arguments
    case_data struct
    resources struct
    candidate struct
    scr_metrics struct = struct()
    gamma_req double = 0.1
    opt struct = struct()
end

% --- initialize output as copy of input candidate ---
cand = candidate;
% ensure required flags exist
if ~isfield(cand,'topology_evaluated'), cand.topology_evaluated = false; end
if ~isfield(cand,'scr_evaluated'), cand.scr_evaluated = false; end
if ~isfield(cand,'scr_pass'), cand.scr_pass = false; end
if ~isfield(cand,'equilibrium_evaluated'), cand.equilibrium_evaluated = false; end
if ~isfield(cand,'sssa_evaluated'), cand.sssa_evaluated = false; end
if ~isfield(cand,'sssa_pass'), cand.sssa_pass = []; end
if ~isfield(cand,'feasible'), cand.feasible = false; end
if ~isfield(cand,'ready_to_commit'), cand.ready_to_commit = false; end
if ~isfield(cand,'margin'), cand.margin = NaN; end
if ~isfield(cand,'omega'), cand.omega = NaN; end
if ~isfield(cand,'physical_kcl_norm'), cand.physical_kcl_norm = Inf; end
if ~isfield(cand,'reason'), cand.reason = ''; end
if ~isfield(cand,'failure_id'), cand.failure_id = ''; end
if ~isfield(cand,'eigenvalues'), cand.eigenvalues = []; end
if ~isfield(cand,'physical_eigenvalues'), cand.physical_eigenvalues = []; end
if ~isfield(cand,'raw_omega'), cand.raw_omega = NaN; end
if ~isfield(cand,'physical_reduction_method'), cand.physical_reduction_method = ''; end
if ~isfield(cand,'active_bound_constraint_count'), cand.active_bound_constraint_count = 0; end
if ~isfield(cand,'coordinate_mode_count'), cand.coordinate_mode_count = 0; end
if ~isfield(cand,'gy_rcond'), cand.gy_rcond = NaN; end

% --- gamma_req frozen check ---
if ~isscalar(gamma_req) || ~isfinite(gamma_req) || gamma_req < 0
    cand.reason = 'gamma_req invalid';
    cand.failure_id = 'stability:ibr_candidate_evaluate:badGammaReq';
    return;
end

% --- topology + scr evaluation flag ---
if ~isempty(scr_metrics) && isfield(scr_metrics,'Ybus') && ~isempty(scr_metrics.Ybus)
    cand.topology_evaluated = true;
    if isfield(scr_metrics,'is_singular') && scr_metrics.is_singular
        cand.reason = 'topology singular/island - fail closed';
        cand.failure_id = 'stability:ibr_candidate_evaluate:singularY';
        cand.scr_evaluated = true;
        cand.scr_pass = false;
        return;
    end
end

% --- SCR gate for GFL remainder ---
cand.scr_evaluated = false;
cand.scr_pass = false;
if ~isempty(scr_metrics) && isfield(scr_metrics,'per_resource') && ~isempty(scr_metrics.per_resource)
    cand.scr_evaluated = true;
    % Determine GFL indices for this candidate: online IBR not in selected set
    nr = numel(resources);
    gfl_indices = [];
    for k=1:nr
        if isfield(resources(k),'initial_online') && ~logical(resources(k).initial_online)
            continue;
        end
        if ismember(k, cand.selected_gfm_indices)
            continue;
        end
        % only IBR
        rt = '';
        try, rt = lower(char(resources(k).resource_type)); catch, rt='ibr'; end
        if ~strcmp(rt,'ibr'), continue; end
        gfl_indices(end+1)=k; %#ok<AGROW>
    end
    % Check each GFL resource's SCR
    scr_fail = false;
    fail_reason = '';
    fail_id = '';
    for gi = gfl_indices
        % find per_resource entry matching index
        pr = [];
        for pp=1:numel(scr_metrics.per_resource)
            if scr_metrics.per_resource(pp).resource_index == gi
                pr = scr_metrics.per_resource(pp);
                break;
            end
        end
        if isempty(pr)
            scr_fail = true;
            fail_reason = sprintf('SCR metrics missing for GFL index %d', gi);
            fail_id = 'stability:ibr_candidate_evaluate:missingScrMetrics';
            break;
        end
        if ~pr.pass
            scr_fail = true;
            fail_reason = sprintf('GFL %s (idx %d) %s', pr.resource_id, gi, pr.reason);
            if ~isempty(pr.failure_id)
                fail_id = pr.failure_id;
            else
                fail_id = 'stability:ibr_candidate_evaluate:scrWeak';
            end
            break;
        end
    end
    if scr_fail
        cand.reason = fail_reason;
        cand.failure_id = fail_id;
        cand.scr_pass = false;
        cand.feasible = false;
        return;
    else
        cand.scr_pass = true;
    end
else
    % No SCR metrics supplied – treat as not evaluated, pass through (structural-only path uses this)
    cand.scr_evaluated = false;
    cand.scr_pass = true; % do not block if SCR not evaluated
end

% --- Build devices via production builder ---
devices = [];
dev_meta = [];
dispatch = struct();
if isfield(opt,'dispatch') && has_dispatch_values(opt.dispatch)
    dispatch = opt.dispatch;
elseif isfield(case_data,'dispatch_contract') && isfield(case_data.dispatch_contract,'post_trip')
    % IEEE14 dispatch contract fallback – build post-trip Pg
    if isfield(case_data.dispatch_contract.post_trip,'post_trip_Pg_MW')
        dispatch = case_data.dispatch_contract.post_trip.post_trip_Pg_MW;
    end
end
% Also check opt.scenario_opt.dispatch
if isfield(opt,'scenario_opt') && isstruct(opt.scenario_opt) && ...
        isfield(opt.scenario_opt,'dispatch') && ...
        has_dispatch_values(opt.scenario_opt.dispatch) && ...
        ~has_dispatch_values(dispatch)
    dispatch = opt.scenario_opt.dispatch;
end

try
    % Generic builder requires case_data + resources + scenario_opt
    scenario_opt = struct();
    if ~isempty(dispatch)
        scenario_opt.dispatch = dispatch;
    end
    % Apply candidate modes as initial_modes override for builder?
    % build_mixed_resource_devices uses resources.initial_mode, not scenario_opt.
    % So we will generate temporary resources copy with updated initial_mode
    resources_tmp = resources;
    for k=1:numel(resources_tmp)
        resource_type = lower(char(resources_tmp(k).resource_type));
        sg_online = isfield(opt,'sg_online') && isscalar(opt.sg_online) && ...
            logical(opt.sg_online);
        if strcmp(resource_type,'sg') && ~sg_online
            % The selector owns the post-SG-trip configuration contract.
            % Evaluate the candidate with every SG breaker open; leaving the
            % source online here would test a different physical system and
            % falsely certify/reject the requested GFM subset.
            resources_tmp(k).initial_online = false;
            if any(strcmpi(string(resources_tmp(k).supported_modes),'breaker_open'))
                resources_tmp(k).initial_mode = 'breaker_open';
            end
        elseif ismember(k, cand.selected_gfm_indices)
            resources_tmp(k).initial_mode = 'GFM';
        else
            % Keep original if not eligible; but if originally GFM and now not selected, set to gfl if capable
            if isfield(resources_tmp(k),'supported_modes') && any(strcmpi(string(resources_tmp(k).supported_modes),'gfl'))
                % only switch if previously gfl or gfm capable
                % For SG keep synchronous
                rt = '';
                try, rt = char(resources_tmp(k).resource_type); catch, end
                if strcmpi(rt,'ibr')
                    resources_tmp(k).initial_mode = 'gfl';
                end
            end
        end
    end
    [devices, dev_meta] = stability.build_mixed_resource_devices(case_data, resources_tmp, scenario_opt);
catch me
    cand.reason = sprintf('device build failed: %s', me.message);
    cand.failure_id = 'stability:ibr_candidate_evaluate:deviceBuild';
    cand.equilibrium_evaluated = false;
    return;
end

% --- Build hybrid_state and commit selection ---
try
    hs = stability.ts_hybrid_state_init(devices);
    % Apply candidate modes to hs.device_modes
    for k=1:numel(devices)
        did = devices(k).device_id;
        key = matlab.lang.makeValidName(did,'ReplacementStyle','underscore');
        if ~isfield(hs.device_modes, key)
            continue;
        end
        is_sg = isfield(devices(k),'capabilities') && ...
            strcmpi(char(devices(k).capabilities.resource_type),'sg');
        sg_online = isfield(opt,'sg_online') && isscalar(opt.sg_online) && ...
            logical(opt.sg_online);
        if is_sg && ~sg_online
            hs.device_online.(key) = false;
            hs.device_modes.(key) = 'breaker_open';
        elseif ismember(k, cand.selected_gfm_indices)
            hs.device_modes.(key) = 'GFM';
        else
            % Keep as per resources_tmp logic
            if ismember(k, cand.selected_gfm_indices)
                hs.device_modes.(key)='GFM';
            else
                % if IBR and supports gfl, set gfl
                try
                    if isfield(devices(k),'capabilities') && any(strcmpi(string(devices(k).capabilities.supported_modes),'gfl'))
                        rt = char(devices(k).capabilities.resource_type);
                        if strcmpi(rt,'ibr')
                            hs.device_modes.(key)='gfl';
                        end
                    end
                catch
                end
            end
        end
    end
    hs.selected_gfm_indices = cand.selected_gfm_indices;
    hs.n_gfm_required = cand.n_gfm_required;
    hs.reference_resource_index = cand.reference_resource_index;
    hs.committed_selection = struct('selected_gfm_indices', cand.selected_gfm_indices, ...
        'n_gfm_required', cand.n_gfm_required, 'reference_resource_index', cand.reference_resource_index);
catch me
    cand.reason = sprintf('hybrid_state build failed: %s', me.message);
    cand.failure_id = 'stability:ibr_candidate_evaluate:hybridState';
    return;
end

% --- Prepare cfg for mixed_equilibrium_solve ---
cfg = struct();
cfg.devices = devices;
cfg.hybrid_state = hs;
cfg.selected_gfm_indices = cand.selected_gfm_indices;
cfg.n_gfm_required = cand.n_gfm_required;
cfg.reference_resource_index = cand.reference_resource_index;
% Preserve resource_ids for drift guard
try
    cfg.resource_ids = {devices.device_id};
catch
    cfg.resource_ids = cand.resource_ids;
end

eq_opt = struct('verbose',false,'tolerance',1e-8,'max_iter',300,'load_model','cz_p_cz_q');
if isfield(opt,'equilibrium_opt') && isstruct(opt.equilibrium_opt)
    fn = fieldnames(opt.equilibrium_opt);
    for f=1:numel(fn)
        eq_opt.(fn{f}) = opt.equilibrium_opt.(fn{f});
    end
end

% --- Solve equilibrium ---
cand.equilibrium_evaluated = false;
eq_result = [];
try
    eq_result = stability.mixed_equilibrium_solve(case_data, cfg, eq_opt);
catch me
    cand.reason = sprintf('equilibrium solve exception: %s', me.message);
    cand.failure_id = 'stability:ibr_candidate_evaluate:equilibriumException';
    return;
end
cand.equilibrium_evaluated = true;
cand.physical_kcl_norm = eq_result.physical_kcl_norm;
if ~eq_result.converged
    cand.reason = sprintf('equilibrium not converged: %s', eq_result.failure_reason);
    cand.failure_id = eq_result.failure_id;
    cand.feasible = false;
    return;
end
if eq_result.physical_kcl_norm > 1e-6
    cand.reason = sprintf('physical KCL %.3e >1e-6', eq_result.physical_kcl_norm);
    cand.failure_id = 'stability:ibr_candidate_evaluate:physicalKCL';
    cand.feasible = false;
    return;
end
% store equilibrium data for SSSA
cand.eq_x0 = eq_result.x0;
cand.eq_y0 = eq_result.y0;
cand.eq_u_eq = eq_result.u_eq;
cand.eq_context = eq_result.equilibrium_context;
cand.eq_active_indices = eq_result.active_state_indices;
cand.eq_rcond = eq_result.rcond;
cand.eq_partition = eq_result.partition;

% --- Full-KCL SSSA evaluation ---
cand.sssa_evaluated = false;
sssa = [];
sssa_opt = struct('full_kcl',true,'u_eq',eq_result.u_eq,...
    'event_context',eq_result.equilibrium_context,...
    'active_state_indices',eq_result.active_state_indices, ...
    'reference_device_index',cand.reference_resource_index);
if isfield(eq_result,'active_bound_regime_history') && ...
        ~isempty(eq_result.active_bound_regime_history)
    sssa_opt.active_bound_regimes = eq_result.active_bound_regime_history{end};
end
if isfield(opt,'sssa_opt') && isstruct(opt.sssa_opt)
    % keep full_kcl enforced – ignore other sssa options that could disable it
end
try
    sssa = stability.composite_sssa_model(devices, eq_result.x0, eq_result.y0, case_data, sssa_opt);
catch me
    cand.reason = sprintf('SSSA failed: %s', me.message);
    cand.failure_id = 'stability:ibr_candidate_evaluate:sssaFailure';
    return;
end
cand.sssa_evaluated = true;
cand.eigenvalues = sssa.eigenvalues;
cand.physical_eigenvalues = sssa.physical_eigenvalues;
cand.gy_rcond = sssa.gy_rcond;
cand.reduction_method = sssa.reduction_method;
cand.physical_reduction_method = sssa.physical_reduction_method;
cand.active_bound_constraint_count = sssa.active_bound_constraint_count;
cand.coordinate_mode_count = sssa.coordinate_mode_count;
cand.sssa_f0_norm = sssa.active_f_residual_norm;
cand.sssa_g0_norm = sssa.physical_kcl_residual_norm;
cand.full_kcl = sssa.full_kcl;

% --- Stability gate (frozen gamma_req) ---
% The full state spectrum is retained above for reporting.  The decision
% spectrum is a pre-eig fixed-active-set/gauge-coordinate projection; no
% eigenvalue is filtered or deleted after eig.
cand.raw_omega = max(real(sssa.eigenvalues));
omega = max(real(sssa.physical_eigenvalues));
if isempty(omega), omega = NaN; end
cand.omega = omega;
% margin definition: positive means stable beyond requirement
% margin = -omega - gamma_req (so >0 means pass)
if isfinite(omega) && isfinite(gamma_req)
    cand.margin = -omega - gamma_req;
else
    cand.margin = NaN;
end
if omega <= -gamma_req
    cand.sssa_pass = true;
else
    cand.sssa_pass = false;
    cand.reason = sprintf('Omega %.4g > -gamma_req %.4g (margin %.4g) insufficient', omega, gamma_req, cand.margin);
    cand.failure_id = 'stability:ibr_candidate_evaluate:insufficientMargin';
    cand.feasible = false;
    return;
end

% --- All gates pass ---
cand.feasible = true;
cand.ready_to_commit = true;
cand.reason = sprintf(['feasible: KCL %.2e, physical Omega %.4g <= -%.4g, ' ...
    'margin %.4g, full roots=%d, decision roots=%d, SCR pass'], ...
    cand.physical_kcl_norm, omega, gamma_req, cand.margin, ...
    numel(cand.eigenvalues),numel(cand.physical_eigenvalues));
cand.failure_id = '';

end

function tf = has_dispatch_values(dispatch)
tf = isstruct(dispatch) && isscalar(dispatch) && ...
    ~isempty(fieldnames(dispatch));
end
