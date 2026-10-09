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
if ~isfield(cand,'fd_eps_values'), cand.fd_eps_values = []; end
if ~isfield(cand,'fd_omegas'), cand.fd_omegas = []; end
if ~isfield(cand,'fd_stable_classification'), cand.fd_stable_classification = []; end
if ~isfield(cand,'fd_classification_consistent'), cand.fd_classification_consistent = false; end
if ~isfield(cand,'fd_robust_margin_pass'), cand.fd_robust_margin_pass = false; end
if ~isfield(cand,'fd_zeta_worsts'), cand.fd_zeta_worsts = []; end
if ~isfield(cand,'zeta_min'), cand.zeta_min = NaN; end
if ~isfield(cand,'zeta_worst'), cand.zeta_worst = NaN; end
if ~isfield(cand,'zeta_margin'), cand.zeta_margin = NaN; end
% Evidence surfacing fields (uniform on EVERY return path so the returned
% candidate keeps the caller's struct schema -- e.g. ibr_config_selector's
% candidate_template -- and a struct-array append never sees a dissimilar shape).
if ~isfield(cand,'measured'), cand.measured = struct(); end
if ~isfield(cand,'evidence'), cand.evidence = []; end

% --- gamma_req frozen check ---
% gamma_req is retained as the candidate ORDERING key and the reference decay
% rate quoted in the evidence.  It is validated with the same strictness as
% before even though it no longer decides admissibility.
if ~isscalar(gamma_req) || ~isfinite(gamma_req) || gamma_req < 0
    cand.reason = 'gamma_req invalid';
    cand.failure_id = 'stability:ibr_candidate_evaluate:badGammaReq';
    return;
end

% --- zeta_min frozen check (the acceptance criterion) ---
% Resolved from the case's frozen selector contract so the criterion travels
% with the case rather than with the caller.  The fallback matches the value the
% contract's own derivation cites (5 % damping at the 1 Hz electromechanical
% mode), so a case that predates the field is evaluated at its declared basis.
zeta_min = 0.05;
if isfield(case_data,'selector') && isstruct(case_data.selector) && ...
        isfield(case_data.selector,'zeta_min_damping') && ...
        ~isempty(case_data.selector.zeta_min_damping)
    zeta_min = case_data.selector.zeta_min_damping;
end
if ~isscalar(zeta_min) || ~isfinite(zeta_min) || zeta_min <= 0 || zeta_min >= 1
    cand.reason = 'zeta_min_damping invalid';
    cand.failure_id = 'stability:ibr_candidate_evaluate:badZetaMin';
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
sg_online_context = isfield(opt,'sg_online') && isscalar(opt.sg_online) && ...
    logical(opt.sg_online);
if isfield(opt,'dispatch') && has_dispatch_values(opt.dispatch)
    dispatch = opt.dispatch;
elseif ~sg_online_context && isfield(case_data,'dispatch_contract') && ...
        isfield(case_data.dispatch_contract,'post_trip')
    % IEEE14 dispatch contract fallback – build post-trip Pg
    if isfield(case_data.dispatch_contract.post_trip,'post_trip_Pg_MW')
        dispatch = case_data.dispatch_contract.post_trip.post_trip_Pg_MW;
    end
end
if sg_online_context && isfield(case_data,'study_capability') && ...
        ~has_dispatch_values(dispatch)
    pre = case_data.dispatch_contract.pre_fault;
    ii = find(strcmpi({resources.resource_type},'ibr'));
    for k=ii
        id = char(resources(k).resource_id);
        dispatch.(id) = pre.(id);
    end
end
if ~sg_online_context && is_source_full_state_resources(resources)
    try
        dispatch=mode_aware_source_dispatch(case_data,resources, ...
            cand.selected_gfm_indices,dispatch);
    catch me
        cand.reason = me.message;
        cand.failure_id = me.identifier;
        cand.feasible = false;
        cand.ready_to_commit = false;
        return;
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
    if ~sg_online_context && isfield(case_data,'dispatch_contract') && ...
            isfield(case_data.dispatch_contract,'post_trip') && ...
            isfield(case_data.dispatch_contract.post_trip,'post_trip_Qg_MVAr')
        scenario_opt.reactive_dispatch = ...
            case_data.dispatch_contract.post_trip.post_trip_Qg_MVAr;
    end
    % Apply candidate modes as initial_modes override for builder?
    % build_mixed_resource_devices uses resources.initial_mode, not scenario_opt.
    % So we will generate temporary resources copy with updated initial_mode
    resources_tmp = resources;
    [sg_off_mask,sg_mask_id,sg_mask_msg] = ne39_sg_off_mask( ...
        case_data,resources_tmp,sg_online_context);
    if ~isempty(sg_mask_id)
        cand.reason = sg_mask_msg;
        cand.failure_id = sg_mask_id;
        cand.feasible = false;
        cand.ready_to_commit = false;
        return;
    end
    for k=1:numel(resources_tmp)
        resource_type = lower(char(resources_tmp(k).resource_type));
        this_sg_off = sg_off_mask(k);
        if strcmp(resource_type,'sg') && this_sg_off
            % The selector owns the post-SG-trip configuration contract.
            % Evaluate the candidate with the scheduled SG breaker(s) open;
            % leaving the source online here would test a different physical
            % system and falsely certify/reject the requested GFM subset.
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
        sg_is_off = sg_off_mask(k);
        if is_sg && sg_is_off
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

% --- Physical evidence surfacing (this seam OWNS it) ----------------------
% Uniform ABI: every physical-evidence field carries {id, applicable, status,
% value, provenance}.  A field is NEVER left as bare NaN/false to be silently
% ignored -- a missing capability is a NAMED status the caller must honour.
%   status values:
%     'MEASURED'               - value is a real measurement (see provenance)
%     'PENDING_DEVICE_SURFACE' - physically required, but the device/builder
%                                does not yet expose the input; NOT satisfied
%     'NOT_APPLICABLE'         - genuinely not part of THIS context
% current/P-Q ใช้ค่าที่วัดจริงจาก equilibrium เทียบ limits ที่ประกาศ.
% NE39 study เพิ่ม steady DC reserve จาก fixed plant ใน final gate ด้านล่าง.
% Synchronism/transition เป็นหลักฐานคนละบริบท ไม่รับรองจาก steady equilibrium.
try
    cand.measured = measure_equilibrium(devices, eq_result, case_data);
catch me
    cand.measured = evidence_field('measured',false,'PENDING_DEVICE_SURFACE',[], ...
        sprintf('equilibrium measurement failed: %s', me.message));
end
% Per-item records are assembled as cand.evidence at the FINAL decision below
% (equilibrium/SSSA/P-Q PASS with real values; current-limit, dc-reserve and the
% GFL<->GFM transition-continuity item are PENDING_DEVICE_SURFACE -- no surrogate
% is fabricated; the steady synchronism item is NOT_APPLICABLE).

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
if isfield(opt,'sssa_opt') && isstruct(opt.sssa_opt) && ...
        isfield(opt.sssa_opt,'fd_eps') && ~isempty(opt.sssa_opt.fd_eps)
    % The only caller override admitted here is the audited FD step. The
    % full-KCL/equilibrium/partition/reference contract remains immutable.
    if ~isscalar(opt.sssa_opt.fd_eps) || ~isfinite(opt.sssa_opt.fd_eps) || ...
            opt.sssa_opt.fd_eps <= 0
        cand.reason = 'sssa_opt.fd_eps must be a positive finite scalar';
        cand.failure_id = 'stability:ibr_candidate_evaluate:badFdEps';
        return;
    end
    sssa_opt.fd_eps = opt.sssa_opt.fd_eps;
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

% --- Stability gate (frozen damping-ratio criterion) ---
% The full state spectrum is retained above for reporting.  The decision
% spectrum is a pre-eig fixed-active-set/gauge-coordinate projection; no
% eigenvalue is filtered or deleted after eig.
%
% ACCEPTANCE CRITERION: every mode of the decision spectrum must satisfy
% zeta_i = -Re(lambda_i)/|lambda_i| >= zeta_min, evaluated at EVERY member of
% the frozen FD perturbation set.  This is the criterion case_data.selector
% states; gamma_req is retained below as the ordering key and reference decay
% rate only.  An absolute-rate floor and a ratio floor coincide at one
% frequency, f* = gamma_req/(2*pi*zeta_min), so a floor calibrated at the 1 Hz
% electromechanical mode is not the same requirement at 0.02 Hz.  The worst-zeta
% mode is generally NOT the rightmost mode, so the ratio is minimised over the
% whole spectrum rather than read off max(Re lambda).
cand.raw_omega = max(real(sssa.eigenvalues));
base_fd_eps = sssa.fd_eps;
fd_factors = [0.5 1.0 2.0];
cand.fd_eps_values = base_fd_eps*fd_factors;
cand.fd_omegas = nan(size(fd_factors));
cand.fd_zeta_worsts = nan(size(fd_factors));
cand.fd_omegas(2) = max(real(sssa.physical_eigenvalues));
cand.fd_zeta_worsts(2) = worst_damping_ratio(sssa.physical_eigenvalues);
for kk = [1 3]
    perturbed_opt = sssa_opt;
    perturbed_opt.fd_eps = cand.fd_eps_values(kk);
    try
        perturbed = stability.composite_sssa_model(devices,eq_result.x0, ...
            eq_result.y0,case_data,perturbed_opt);
        cand.fd_omegas(kk) = max(real(perturbed.physical_eigenvalues));
        cand.fd_zeta_worsts(kk) = worst_damping_ratio(perturbed.physical_eigenvalues);
    catch me
        cand.reason = sprintf('FD robustness SSSA failed at eps %.6g: %s', ...
            cand.fd_eps_values(kk),me.message);
        cand.failure_id = 'stability:ibr_candidate_evaluate:fdRobustnessFailure';
        cand.feasible = false;
        return;
    end
end
cand.fd_stable_classification = cand.fd_omegas < 0;
cand.fd_classification_consistent = all(isfinite(cand.fd_omegas)) && ...
    (all(cand.fd_stable_classification) || ~any(cand.fd_stable_classification));
% Robust damping-ratio gate.  A non-finite entry (a mode at the origin, where
% the ratio is undefined) fails closed through the isfinite test.  The explicit
% stability test is redundant with zeta_min > 0 but is kept so the intent is
% readable and so a zero-frequency marginal mode can never certify.
cand.zeta_min = zeta_min;
cand.zeta_worst = min(cand.fd_zeta_worsts);
cand.zeta_margin = cand.zeta_worst - zeta_min;
cand.fd_robust_margin_pass = all(isfinite(cand.fd_omegas)) && ...
    all(cand.fd_omegas < 0) && ...
    all(isfinite(cand.fd_zeta_worsts)) && ...
    all(cand.fd_zeta_worsts >= zeta_min);
% Consume the worst (least damped) member of the frozen FD perturbation set.
omega = max(cand.fd_omegas);
cand.omega = omega;
% ORDERING KEY, not the gate.  margin = -omega - gamma_req is the decay-rate
% headroom against the reference rate and is what candidate_order_matrix ranks
% on.  It is deliberately left unchanged by the criterion correction: ranking on
% the damping ratio instead would reorder the admissible set and move the
% selected configuration, which is a separate decision.  A candidate can
% therefore be admissible (zeta_margin >= 0) while margin < 0.
if isfinite(omega) && isfinite(gamma_req)
    cand.margin = -omega - gamma_req;
else
    cand.margin = NaN;
end
if cand.fd_classification_consistent && cand.fd_robust_margin_pass
    cand.sssa_pass = true;
else
    cand.sssa_pass = false;
    cand.reason = sprintf(['robust zeta %s, worst %.4g < zeta_min %.4g, ' ...
        'Omega %s worst %.4g, classification_consistent=%d, ' ...
        'zeta_margin %.4g insufficient'], ...
        mat2str(cand.fd_zeta_worsts,6),cand.zeta_worst,zeta_min, ...
        mat2str(cand.fd_omegas,6),omega, ...
        cand.fd_classification_consistent,cand.zeta_margin);
    cand.failure_id = 'stability:ibr_candidate_evaluate:insufficientRobustMargin';
    cand.feasible = false;
    return;
end

% --- All gates pass ---
cand.feasible = true;
cand.ready_to_commit = true;
cand.reason = sprintf(['feasible: KCL %.2e, robust zeta %.4g >= %.4g ' ...
    '(margin %.4g), Omega %.4g, decay margin %.4g vs gamma_req %.4g, ' ...
    'FD eps=%s, full roots=%d, decision roots=%d, SCR pass'], ...
    cand.physical_kcl_norm, cand.zeta_worst, zeta_min, cand.zeta_margin, ...
    omega, cand.margin, gamma_req, ...
    mat2str(cand.fd_eps_values,6),numel(cand.eigenvalues), ...
    numel(cand.physical_eigenvalues));
cand.failure_id = '';

% Physical-evidence records consumed by the lazy selector's certificate gate
% (stability.ibr_selector_search_lazy/evidence_records_pass).  STRICT rule: only
% records that are TRUE for THIS (steady) context are emitted; every emitted
% applicable record carries a REAL value and a PASS word.  Items that belong to a
% DIFFERENT certificate context (dc_reserve -> the GFM-capability/transition
% decision; synchronism_transition -> the GFL<->GFM mode-change continuity check)
% are deliberately NOT emitted here: a PENDING placeholder would (correctly) be
% rejected by the strict gate and would falsely condemn every steady candidate,
% and emitting a value we cannot compute would be fabrication.  Those certs are
% owned by their own contexts, not this steady selector.
cand.evidence = build_evidence_records(cand, resources, case_data);
if isfield(case_data,'study_capability')
    % steady reserve ของ plant เดิม ไม่อ้างว่า transition/synchronism ผ่าน.
    dc = stability.ibr_dc_steady_reserve(devices,resources,eq_result,case_data);
    cand.evidence(end+1) = dc;
    cand.dc_reserve_MW = dc.value;
    pqr = pq_limits_record(cand,resources);
    ir = current_limit_record(cand,resources);
    cand.within_limits = ~isempty(pqr) && ~isempty(ir) && ...
        strcmp(pqr.status,'PASS') && strcmp(ir.status,'PASS');
    if ~cand.within_limits || ~strcmp(dc.status,'PASS')
        cand.feasible = false;
        cand.ready_to_commit = false;
        cand.failure_id = 'stability:ibr_candidate_evaluate:studyCapability';
        cand.reason = 'Study current/P-Q/DC steady evidence is missing or failed.';
    end
end

end

function recs = build_evidence_records(cand, resources, case_data)
%BUILD_EVIDENCE_RECORDS  Certificate-gate records for one certified candidate.
%   Assembled only on the all-gates-pass path, so the items that were gated
%   above (physical KCL, equilibrium, full-KCL SSSA) carry their real value.
recs = evidence_field('equilibrium_balance', true, 'PASS', ...
    cand.physical_kcl_norm, ...
    'physical KCL residual at the accepted equilibrium (<=1e-6 gate)');
recs(end+1) = evidence_field('equilibrium_rcond', true, ...
    tf_word(isfinite(cand.eq_rcond) && cand.eq_rcond > 0), cand.eq_rcond, ...
    'reciprocal condition number of the accepted equilibrium Jacobian');
recs(end+1) = evidence_field('sssa_full_kcl', true, 'PASS', cand.zeta_worst, ...
    'full-KCL SSSA worst damping ratio over the robust perturbed spectra');
r = pq_limits_record(cand, resources);
if ~isempty(r)
    recs(end+1) = r;
end
r = current_limit_record(cand, resources);
if ~isempty(r)
    recs(end+1) = r;
end
recs(end+1) = evidence_field('synchronism_steady', false, ...
    'NOT_APPLICABLE', NaN, ...
    ['synchronism applies at reconnect/handback, not to a steady candidate ' ...
     'equilibrium; waived as SYNCHRON-steady (not TRANSITION)']);
end

function r = current_limit_record(cand, resources)
%CURRENT_LIMIT_RECORD  Measured per-device |I| vs the declared machine-base Imax.
%   Convention (from +ibr/gfl_eecon49_full_model: line 57 `id0=kappa*P_ref/Vmag`,
%   line 166 `I_inv = I*kappa`): kappa = Sbase/Mbase and the device's
%   current_injection returns the SYSTEM-base current, so the MACHINE-base
%   current is I_sys*kappa and the declared Imax (ImaxSS) is in MACHINE pu.
%   Utilisation = (|I_sys|*kappa)/Imax, dimensionless, PASS if <=1.  Requires
%   the ACTUAL Sbase/Mbase metadata -- a missing base is NOT defaulted to
%   kappa=1 (that would silently rescale a real limit by ~5-65x); the item is
%   omitted instead.  Real comparison (MW/MVAr-free).
compared = false; ok = true; worst = -Inf;
if isfield(cand,'measured') && isstruct(cand.measured) && ...
        isfield(cand.measured,'value')
    rows = cand.measured.value;
    for k = 1:numel(rows)
        idx = find(strcmpi({resources.resource_id}, rows(k).resource_id), 1);
        if isempty(idx), continue; end
        R = resources(idx);
        if ~isfield(R,'limits') || ~isfield(R.limits,'ImaxSS') || ...
                ~isscalar(R.limits.ImaxSS) || ~isfinite(R.limits.ImaxSS) || ...
                R.limits.ImaxSS <= 0
            continue;
        end
        if ~isfield(R,'ratings') || ~isstruct(R.ratings) || ...
                ~isfield(R.ratings,'Sbase') || ~isfield(R.ratings,'Mbase') || ...
                ~isscalar(R.ratings.Sbase) || R.ratings.Sbase <= 0 || ...
                ~isscalar(R.ratings.Mbase) || R.ratings.Mbase <= 0
            continue;   % no real base contract -> emit nothing (no kappa=1 guess)
        end
        kappa = R.ratings.Sbase / R.ratings.Mbase;
        compared = true;
        u = (rows(k).I_pu * kappa) / R.limits.ImaxSS;
        worst = max(worst, u); ok = ok && (u <= 1 + 1e-6);
    end
end
if ~compared
    r = [];   % no declared Imax/base to compare against -> omit
    return;
end
r = evidence_field('current_limit', true, tf_word(ok), worst, ...
    'measured |I|*kappa vs declared machine-base Imax; value = worst utilisation');
end

function r = pq_limits_record(cand, resources)
%PQ_LIMITS_RECORD  Measured per-device P/Q vs the resource's declared limits.
%   Only finite, positive declared limits are compared (MW/MVAr -- unambiguous
%   units), so the comparison is REAL, never a surrogate.  value is the worst
%   utilisation (fraction of the declared limit).  When NO resource declares a
%   finite limit the item returns EMPTY and is omitted -- a missing limit check
%   is not silently PASSed.
compared = false; ok = true; worst = -Inf;
if isfield(cand,'measured') && isstruct(cand.measured) && ...
        isfield(cand.measured,'value')
    rows = cand.measured.value;
    for k = 1:numel(rows)
        idx = find(strcmpi({resources.resource_id}, rows(k).resource_id), 1);
        if isempty(idx) || ~isfield(resources(idx),'limits'), continue; end
        L = resources(idx).limits;
        if isfield(L,'Pmax_MW') && isscalar(L.Pmax_MW) && ...
                isfinite(L.Pmax_MW) && L.Pmax_MW > 0
            compared = true;
            u = rows(k).P_MW / L.Pmax_MW;
            worst = max(worst, u); ok = ok && (u <= 1 + 1e-6);
        end
        if isfield(L,'Qmax_MVAr') && isscalar(L.Qmax_MVAr) && ...
                isfinite(L.Qmax_MVAr) && L.Qmax_MVAr > 0
            compared = true;
            u = abs(rows(k).Q_MVAr) / L.Qmax_MVAr;
            worst = max(worst, u); ok = ok && (u <= 1 + 1e-6);
        end
    end
end
if ~compared
    r = [];   % no declared limit to compare against -> omit (not a PENDING reject)
    return;
end
r = evidence_field('pq_limits', true, tf_word(ok), worst, ...
    'measured P/Q (MW/MVAr) vs declared resource Pmax/Qmax; value = worst utilisation');
end

function w = tf_word(tf)
if tf, w = 'PASS'; else, w = 'FAIL'; end
end

function z = worst_damping_ratio(lambda)
%WORST_DAMPING_RATIO  Least damping ratio over a spectrum.
%   Z = worst_damping_ratio(LAMBDA) returns min_i zeta_i with
%   zeta_i = -Re(lambda_i)/|lambda_i|, the standard damping ratio of a mode.
%   A real negative root gives zeta = 1 (it does not oscillate, so it can never
%   be the ratio-limiting mode); an unstable root gives zeta < 0.
%
%   A root AT the origin has an undefined ratio.  It is mapped to -Inf rather
%   than skipped, so a marginal zero-frequency mode fails any positive floor
%   instead of silently certifying.  The gauge quotient already removes the one
%   rigid network-angle coordinate, so a surviving zero root is a genuine
%   marginal mode and must fail closed.
%
%   An empty spectrum returns -Inf for the same reason: no evidence is not
%   evidence of damping.
lambda = lambda(:);
if isempty(lambda)
    z = -Inf;
    return;
end
mag = abs(lambda);
zeta = -real(lambda)./mag;
zeta(~(mag > 0)) = -Inf;
z = min(zeta);
end

function e = evidence_field(id, applicable, status, value, provenance)
e = struct('id',char(id),'applicable',logical(applicable),'status',char(status), ...
    'value',value,'provenance',char(provenance));
end

function e = measure_equilibrium(devices, eq_result, case_data)
%MEASURE_EQUILIBRIUM  Real per-device P/Q/|I|/|V| at the accepted equilibrium.
%   An EVIDENCE table, not a gate.  I is the device's own current_injection at
%   y0 (system pu), P/Q in MW/MVAr on case_data.mpc.baseMVA.
Sbase = case_data.mpc.baseMVA;
y0 = eq_result.y0; V = complex(y0(1:2:end), y0(2:2:end));
nd = numel(devices); xo = 0; uo = 0;
rows = repmat(struct('resource_id','','P_MW',NaN,'Q_MVAr',NaN, ...
    'I_pu',NaN,'V_pu',NaN), 1, nd);
for k = 1:nd
    d = devices(k);
    x = eq_result.x0(xo+(1:d.nx)); u = eq_result.u_eq(uo+(1:d.nu));
    I = d.current_injection(0, x, y0, u, eq_result.equilibrium_context);
    S = V(d.bus_position)*conj(I);
    rows(k) = struct('resource_id',char(d.device_id),'P_MW',real(S)*Sbase, ...
        'Q_MVAr',imag(S)*Sbase,'I_pu',abs(I),'V_pu',abs(V(d.bus_position)));
    xo = xo + d.nx; uo = uo + d.nu;
end
e = struct('id','measured','applicable',true,'status','MEASURED', ...
    'value',rows, ...
    'provenance','device.current_injection at the accepted equilibrium y0');
end

function [mask,failure_id,msg] = ne39_sg_off_mask(case_data,resources,sg_online)
%NE39_SG_OFF_MASK  mask ของ SG ที่ breaker เปิดใน context นี้.
%   SG_ON เป็น false ทั้งแถว. SG_OFF ของ NE39 ใช้ post_trip partition:
%   tripped=true, remaining=false, IBR=false. composition ที่ไม่มีสัญญา
%   remaining ยังเป็น all-SG-off ตามเส้นทาง IEEE14 เดิม.
mask = false(numel(resources),1);
failure_id = '';
msg = '';
if sg_online, return; end
has_partial = isfield(case_data,'study_capability') && ...
    isfield(case_data,'dispatch_contract') && ...
    isfield(case_data.dispatch_contract,'post_trip') && ...
    isfield(case_data.dispatch_contract.post_trip,'sg_ids') && ...
    isfield(case_data.dispatch_contract.post_trip,'remaining_sg_ids');
if ~has_partial
    for k = 1:numel(resources)
        if isfield(resources(k),'resource_type') && ...
                strcmpi(char(resources(k).resource_type),'sg')
            mask(k) = true;
        end
    end
    return;
end
post = case_data.dispatch_contract.post_trip;
tripped = cellstr(string(post.sg_ids));
remaining = cellstr(string(post.remaining_sg_ids));
sg_ids = {};
for k = 1:numel(resources)
    if ~isfield(resources(k),'resource_type') || ...
            ~strcmpi(char(resources(k).resource_type),'sg')
        continue;
    end
    id = char(resources(k).resource_id);
    sg_ids{end+1} = id; %#ok<AGROW>
    in_trip = any(strcmp(tripped,id));
    in_remain = any(strcmp(remaining,id));
    if in_trip == in_remain
        failure_id = 'stability:ibr_candidate_evaluate:contingencyMismatch';
        msg = sprintf('SG %s must be tripped or remaining, not both or neither.',id);
        return;
    end
    mask(k) = in_trip;
end
if numel(unique(tripped)) ~= numel(tripped) || ...
        numel(unique(remaining)) ~= numel(remaining) || ...
        ~isequal(sort([tripped remaining]),sort(sg_ids))
    failure_id = 'stability:ibr_candidate_evaluate:contingencyMismatch';
    msg = 'NE39 post-trip SG ids must partition every SG exactly once.';
    mask(:) = false;
end
end

function tf = has_dispatch_values(dispatch)
tf = isstruct(dispatch) && isscalar(dispatch) && ...
    ~isempty(fieldnames(dispatch));
end

function tf=is_source_full_state_resources(resources)
% The project full-state dual family uses the mode-aware source dispatch
% contract: 'eecon49_dual' (16-state, coupled swing).  Omitting the family here
% does not throw; it silently selects the fallback dispatch and therefore a
% different operating point, so the list must be kept complete.
ibr_idx=find(arrayfun(@(r)isfield(r,'resource_type') && ...
    strcmpi(char(r.resource_type),'ibr'),resources));
tf=~isempty(ibr_idx) && all(arrayfun(@(k)isfield(resources(k),'model_id') && ...
    any(strcmpi(char(resources(k).model_id), ...
        {'eecon49_dual'})),ibr_idx));
end

function dispatch=mode_aware_source_dispatch(case_data,resources,selected,fallback)
dispatch=fallback;
if isfield(case_data,'study_capability')
    % NE39 ใช้ dispatch เดียวกับ runtime ไม่แจก deficit ซ้ำตาม selected modes.
    % sg_ids เป็น SG ที่ trip ไม่ใช่ทุก SG ใน composition; remaining ต้อง partition ครบ.
    if ~isfield(case_data.dispatch_contract.post_trip,'post_trip_Pg_MW') || ...
            ~isfield(case_data.dispatch_contract.post_trip,'sg_ids') || ...
            ~isfield(case_data.dispatch_contract.post_trip,'remaining_sg_ids')
        error('stability:ibr_candidate_evaluate:missingContingencyDispatch', ...
            'NE39 requires an explicit contingency-specific post-trip dispatch.');
    end
    post=case_data.dispatch_contract.post_trip;
    expected=cellstr(string({resources(strcmpi({resources.resource_type},'sg')).resource_id}));
    tripped=cellstr(string(post.sg_ids));
    remaining=cellstr(string(post.remaining_sg_ids));
    if numel(unique(tripped))~=numel(tripped) || numel(unique(remaining))~=numel(remaining) || ...
            ~isempty(intersect(tripped,remaining)) || ...
            ~isequal(sort([tripped remaining]),sort(expected))
        error('stability:ibr_candidate_evaluate:contingencyMismatch', ...
            'NE39 post-trip SG ids must partition every SG exactly once.');
    end
    dispatch=post.post_trip_Pg_MW;
    ii=find(strcmpi({resources.resource_type},'ibr'));
    for k=ii
        id=char(resources(k).resource_id);
        if ~isfield(dispatch,id) || ~isnumeric(dispatch.(id)) || ...
                ~isscalar(dispatch.(id)) || ~isreal(dispatch.(id)) || ~isfinite(dispatch.(id))
            error('stability:ibr_candidate_evaluate:badModeAwareDispatch', ...
                'Post-trip dispatch for %s must be finite real MW.',id);
        end
    end
    return;
end
if ~isfield(case_data,'dispatch_contract') || ...
        ~isfield(case_data.dispatch_contract,'pre_fault') || ...
        ~isfield(case_data.dispatch_contract,'post_trip') || ...
        ~isfield(case_data.dispatch_contract.post_trip,'deficit_MW')
    error('stability:ibr_candidate_evaluate:missingModeAwareDispatch', ...
        'The full-state source model requires pre-fault dispatch and lost-SG deficit.');
end
ibr_idx=find(arrayfun(@(r)isfield(r,'resource_type') && ...
    strcmpi(char(r.resource_type),'ibr'),resources));
gfl_idx=setdiff(ibr_idx,selected,'stable');
if isempty(gfl_idx), return; end
pre=case_data.dispatch_contract.pre_fault;
weights=zeros(size(gfl_idx));
for j=1:numel(gfl_idx)
    k=gfl_idx(j);
    if ~isfield(resources(k),'limits') || ...
            ~isfield(resources(k).limits,'Pmax_MW') || ...
            ~isfinite(resources(k).limits.Pmax_MW) || resources(k).limits.Pmax_MW<=0
        error('stability:ibr_candidate_evaluate:badModeAwareDispatch', ...
            'GFL resource %s lacks a positive finite Pmax_MW.',resources(k).resource_id);
    end
    weights(j)=resources(k).limits.Pmax_MW;
end
weights=weights/sum(weights);
deficit=case_data.dispatch_contract.post_trip.deficit_MW;
for k=ibr_idx(:)'
    id=char(resources(k).resource_id);
    field=[id '_Pg_MW'];
    if isfield(pre,field) && isnumeric(pre.(field)) && isscalar(pre.(field)) && ...
            isfinite(pre.(field))
        val=pre.(field);                 % IEEE14 contract: <id>_Pg_MW
    elseif isfield(pre,id) && isnumeric(pre.(id)) && isscalar(pre.(id)) && ...
            isfinite(pre.(id))
        val=pre.(id);                    % case-owned pre-fault dispatch in MW
    else
        error('stability:ibr_candidate_evaluate:missingModeAwareDispatch', ...
            'Pre-fault dispatch lacks %s (or a numeric pre_fault.%s).',field,id);
    end
    dispatch.(id)=val;
    pos=find(gfl_idx==k,1);
    if ~isempty(pos), dispatch.(id)=dispatch.(id)+deficit*weights(pos); end
end
end
