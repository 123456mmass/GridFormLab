function scr = ibr_scr_metrics(case_data, resources, topology, opt)
%IBR_SCR_METRICS  Short-Circuit Ratio metrics for online GFL resources.
%
%   SCR = ibr_scr_metrics(CASE_DATA, RESOURCES, TOPOLOGY, OPT)
%   computes Thevenin impedance at each online GFL bus from project
%   Ybus/branch data only, then S_sc = |V|^2 / |Zth| on system base,
%   SCR = S_sc / S_rated. WECC REGC_A GFL with SCR<=3 fails closed.
%
%   Derivation / classification (frozen before results):
%
%   Ybus build (SOURCE_DEFINED, from MATPOWER branch):
%     For each branch k: r=br(k,3), x=br(k,4), b=br(k,5)
%     tap=br(k,9), shift=br(k,10), a=tap*exp(j*shift_deg)
%     yser = 1/(r+j*x)
%     Y(ii,ii) += (yser + j*b/2)/(a*conj(a))   % canonical MATPOWER Yff
%     Y(jj,jj) += yser + j*b/2
%     Y(ii,jj) -= yser/conj(a)
%     Y(jj,ii) -= yser/a
%     + bus shunt: diag((GS+j*BS)/baseMVA)  [bus(:,5), bus(:,6)]
%     The from-side charging j*b/2 is divided by |a|^2 together with the
%     series admittance (MATPOWER makeYbus Yff = (Ys+jBc/2)/|tap|^2, the
%     model with the ideal transformer at the from end), matching the
%     project's own chronology_branch_stamp in ts_simulate_ibr_hybrid.  For
%     IEEE14 this is a no-op: no branch there is both tapped and charged.
%     Units: pu on Sbase (case_data.mpc.baseMVA)
%     No load admittance - pure network strength (PROJECT_DERIVED choice).
%     Source: pf_prepare_case / classical_dae / composite_dae builders.
%
%   Thevenin impedance (PROJECT_DERIVED, audited primitives):
%     Solve Ybus * Vz = e_k  (unit current injection at bus k)
%     using MATLAB \ (or lu) - never inv/pinv.
%     Zth_k = Vz(k) = (e_k' * Ybus^{-1} * e_k)
%     Equivalent to Schur complement elimination of all other buses.
%     If Y singular/island, fail closed.
%
%   S_sc:
%     |V| from opt.bus_voltages (if supplied) else 1.0 pu CASE_DEFINED
%     S_sc_pu = |V|^2 / |Zth|   [pu on Sbase]
%     S_sc_MVA = S_sc_pu * Sbase
%
%   Rating:
%     S_rated = resources(k).ratings.Mbase  [MVA, CASE_DEFINED]
%     If missing, empty, non-finite, <=0 => fail closed, no guessing.
%     Fallback checks: ratings.Sbase, limits.Pmax_MW are NOT accepted.
%
%   SCR:
%     SCR = S_sc_MVA / S_rated  = S_sc_pu / (S_rated/Sbase)
%     threshold = 3.0 frozen (CASE_DEFINED, WECC REGC_A strong-grid contract)
%     pass = SCR > threshold, fail = SCR <= threshold (reject)
%
%   Fail-closed reasons:
%     - island / singular Y: rcond(Y)<1e-12 or \ gives non-finite/residual>1e-6
%     - missing rating
%     - Zth non-finite or |Zth|<eps
%     - bus mapping missing
%
%   Output:
%     scr.Sbase, scr.Ybus, scr.Y_rcond, scr.topology_ok, scr.is_singular,
%     scr.threshold, scr.V_used_default, scr.per_resource (nr entries),
%     scr.overall_pass, scr.fingerprint, scr.failure_id
%
%   per_resource fields:
%     resource_index, resource_id, bus_id, bus_position,
%     online, is_gfl, eligible_for_scr,
%     Zth (complex), absZth, Vmag_used, Ssc_pu, Ssc_MVA, rating_MVA,
%     SCR, threshold, pass, reason, failure_id,
%     classification struct
%
%   No inv/pinv, no external solver.

arguments
    case_data struct = struct()
    resources struct = struct()
    topology struct = struct()
    opt struct = struct()
end

Sbase = 100.0;
threshold = 3.0;
if isfield(opt,'scr_threshold') && ~isempty(opt.scr_threshold)
    threshold = opt.scr_threshold;
end
if ~isscalar(threshold) || ~isfinite(threshold) || threshold <=0
    threshold = 3.0;
end

% --- source model selector (opt-in; ABSENT == legacy, IEEE14 bit-identical) ---
source_model = 'legacy_slack_grounding';
if isfield(opt,'scr_source_model') && ~isempty(opt.scr_source_model)
    source_model = lower(char(opt.scr_source_model));
end
if ~ismember(source_model, {'legacy_slack_grounding','source_aware'})
    error('stability:ibr_scr_metrics:badSourceModel', ...
        ['opt.scr_source_model must be legacy_slack_grounding or source_aware ' ...
         '(got "%s").'], source_model);
end

% --- defaults ---
scr = struct();
scr.Sbase = Sbase;
scr.threshold = threshold;
scr.method = source_model;
scr.validity_scope = legacy_validity_scope();
scr.Ybus = [];
scr.Y_rcond = NaN;
scr.topology_ok = true;
scr.is_singular = true;
scr.failure_id = '';
scr.failure_reason = '';
scr.overall_pass = false;
scr.per_resource = [];
scr.fingerprint = 'scr_v1:uninitialized';
scr.V_used_default = 1.0;
% Source-aware bookkeeping (empty in the legacy path).
scr.source_list = [];
scr.islands = [];
scr.Yaug = [];
scr.n_sources_online = 0;
scr.classification = struct('Ybus','SOURCE_DEFINED','Zth','PROJECT_DERIVED',...
    'Ssc','PROJECT_DERIVED','rating','CASE_DEFINED','threshold','CASE_DEFINED',...
    'source_model','PROJECT_DERIVED');

% Source-aware path is a fully separate branch so the legacy path below stays
% byte-for-byte the behaviour IEEE14 depends on.
if strcmp(source_model,'source_aware')
    scr = source_aware_metrics(case_data, resources, topology, opt, scr, Sbase, threshold);
    return;
end

nr = numel(resources);
if nr==0
    scr.failure_id = 'stability:ibr_scr_metrics:noResources';
    scr.failure_reason = 'Resource table empty.';
    scr.per_resource = repmat(empty_per_resource(),0,1);
    scr.fingerprint = 'scr_v1:noResources';
    return;
end

% --- Extract case_data.mpc ---
mpc = [];
if isfield(case_data,'mpc') && isstruct(case_data.mpc) && isscalar(case_data.mpc)
    mpc = case_data.mpc;
elseif isfield(topology,'case_data') && isstruct(topology.case_data) && isfield(topology.case_data,'mpc')
    mpc = topology.case_data.mpc;
elseif isfield(opt,'case_data') && isstruct(opt.case_data) && isfield(opt.case_data,'mpc')
    mpc = opt.case_data.mpc;
end

if isempty(mpc) || ~isfield(mpc,'bus') || ~isfield(mpc,'branch') || ~isfield(mpc,'baseMVA')
    scr.failure_id = 'stability:ibr_scr_metrics:missingMpc';
    scr.failure_reason = 'case_data.mpc with bus/branch/baseMVA required.';
    scr.per_resource = build_per_resource_empty(resources);
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
end

Sbase = mpc.baseMVA;
scr.Sbase = Sbase;

% --- Build Ybus network only (branch + shunt, no load) ---
try
    [Ybus, bus_ids] = build_ybus_network(mpc);
catch me
    scr.failure_id = 'stability:ibr_scr_metrics:ybusBuild';
    scr.failure_reason = me.message;
    scr.per_resource = build_per_resource_empty(resources);
    scr.is_singular = true;
    scr.topology_ok = false;
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
end
scr.Ybus = Ybus;

% --- SLACK grounding for Thevenin (voltage sources shorted) ---
% For SCR, Thevenin is seen with SLACK buses (type 3) shorted (grounded).
% We therefore reduce Ybus by removing SLACK rows/cols when they exist.
% Classification: PROJECT_DERIVED (Thevenin with SLACK shorted).
nb = numel(bus_ids);
ref_pos = [];
try
    if size(mpc.bus,1)==nb && size(mpc.bus,2)>=2
        ref_pos = find(mpc.bus(:,2)==3);
    end
catch
    ref_pos = [];
end
non_ref_pos = setdiff(1:nb, ref_pos);
if isempty(non_ref_pos)
    % All buses are SLACK – degenerate, treat as singular/island
    scr.Y_rcond = 0;
    scr.is_singular = true;
    scr.topology_ok = false;
    scr.failure_id = 'stability:ibr_scr_metrics:allRef';
    scr.failure_reason = 'All buses are SLACK - no non-SLACK bus for Thevenin.';
    scr.per_resource = build_per_resource_singular(resources, bus_ids, Sbase, threshold, 'allRef');
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
end

Yred = Ybus(non_ref_pos, non_ref_pos);
% rcond on reduced Y (after SLACK grounding) – primary singularity check
try
    Yrcond = rcond(Yred);
catch
    Yrcond = 0;
end
scr.Y_rcond = Yrcond;
scr.Ybus_reduced = Yred;
scr.ref_bus_positions = ref_pos;
scr.non_ref_positions = non_ref_pos;
if ~isfinite(Yrcond) || Yrcond < 1e-12
    scr.is_singular = true;
    scr.topology_ok = false;
    scr.failure_id = 'stability:ibr_scr_metrics:singularY';
    scr.failure_reason = sprintf('Ybus_reduced rcond=%.3e < 1e-12 - island/singular network fail closed.', Yrcond);
    scr.per_resource = build_per_resource_singular(resources, bus_ids, Sbase, threshold, 'singularY');
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
else
    scr.is_singular = false;
end

% --- Bus voltage magnitudes for S_sc ---
Vmag_per_bus = containers.Map('KeyType','double','ValueType','double');
default_Vmag = 1.0;
scr.V_used_default = default_Vmag;
if isfield(opt,'bus_voltages') && ~isempty(opt.bus_voltages)
    if isstruct(opt.bus_voltages)
        fns = fieldnames(opt.bus_voltages);
        for kk=1:numel(fns)
            bid = str2double(fns{kk});
            if ~isnan(bid) && isfinite(opt.bus_voltages.(fns{kk}))
                Vmag_per_bus(bid) = abs(opt.bus_voltages.(fns{kk}));
            end
        end
    elseif isnumeric(opt.bus_voltages) && numel(opt.bus_voltages)==numel(bus_ids)
        for kk=1:numel(bus_ids)
            if isfinite(opt.bus_voltages(kk))
                Vmag_per_bus(bus_ids(kk)) = abs(opt.bus_voltages(kk));
            end
        end
    end
end
if isfield(opt,'V0_per_bus') && ~isempty(opt.V0_per_bus) && isnumeric(opt.V0_per_bus)
    if numel(opt.V0_per_bus)==numel(bus_ids)
        for kk=1:numel(bus_ids)
            if isfinite(opt.V0_per_bus(kk)) && abs(opt.V0_per_bus(kk))>0
                Vmag_per_bus(bus_ids(kk)) = abs(opt.V0_per_bus(kk));
            end
        end
    end
end

% --- Per-resource loop ---
per_res = repmat(empty_per_resource(),0,1);

for k = 1:nr
    r = resources(k);
    pr = empty_per_resource();
    pr.resource_index = k;
    try
        pr.resource_id = char(r.resource_id);
    catch
        pr.resource_id = sprintf('idx%d',k);
    end
    pr.threshold = threshold;
    try
        pr.bus_id = double(r.bus_id);
    catch
        pr.bus_id = NaN;
    end
    pr.classification = struct('Zth','PROJECT_DERIVED','Ssc','PROJECT_DERIVED',...
        'rating','CASE_DEFINED','threshold','CASE_DEFINED','V','CASE_DEFINED',...
        'Ybus','SOURCE_DEFINED','decision','PROJECT_DERIVED');

    on = false;
    if isfield(r,'initial_online')
        on = logical(r.initial_online);
    elseif isfield(r,'online')
        on = logical(r.online);
    end
    pr.online = on;

    is_gfl = false;
    if isfield(r,'initial_mode')
        is_gfl = strcmpi(char(r.initial_mode),'gfl');
    elseif isfield(r,'mode')
        is_gfl = strcmpi(char(r.mode),'gfl');
    elseif isfield(r,'supported_modes')
        is_gfl = any(strcmpi(string(r.supported_modes),'gfl'));
    end
    is_ibr = true;
    if isfield(r,'resource_type')
        is_ibr = strcmpi(char(r.resource_type),'ibr');
    end
    pr.is_gfl = is_gfl && is_ibr;
    scr_profile='wecc_regca_strong_grid';
    % The project full-state dual family models the plant explicitly, so the
    % WECC strong-grid SCR screening profile does not apply to it.  A family
    % missing from this list silently becomes SCR-eligible and changes the gate.
    if isfield(r,'model_id') && ...
            any(strcmpi(char(r.model_id),{'eecon49_dual'}))
        scr_profile='not_applicable_full_state_source_model';
    end
    pr.scr_profile=scr_profile;
    pr.eligible_for_scr = on && is_ibr && ...
        strcmp(scr_profile,'wecc_regca_strong_grid');

    bp = find(bus_ids==pr.bus_id,1);
    pr.bus_position = bp;

    if ~on || ~is_ibr
        pr.reason = 'offline or not IBR - not evaluated';
        pr.pass = true;
        per_res(end+1,1)=pr;
        continue;
    end
    if ~pr.eligible_for_scr
        pr.reason=['SCR threshold not applicable to this full-state model; ' ...
            'equilibrium, limits and full-KCL SSSA remain mandatory'];
        pr.pass=true;
        per_res(end+1,1)=pr;
        continue;
    end
    if isempty(bp)
        pr.reason = sprintf('bus_id %g not in Ybus bus_ids', pr.bus_id);
        pr.failure_id = 'stability:ibr_scr_metrics:badBusMapping';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end

    rating = NaN;
    rating_found = false;
    if isfield(r,'ratings') && isstruct(r.ratings)
        if isfield(r.ratings,'Mbase') && ~isempty(r.ratings.Mbase) && isfinite(r.ratings.Mbase)
            rating = double(r.ratings.Mbase);
            rating_found = true;
        end
    end
    if ~rating_found
        pr.rating_MVA = NaN;
        pr.reason = 'missing rating Mbase - fail closed';
        pr.failure_id = 'stability:ibr_scr_metrics:missingRating';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end
    pr.rating_MVA = rating;
    if ~isfinite(rating) || rating <= 0
        pr.reason = 'invalid rating <=0 - fail closed';
        pr.failure_id = 'stability:ibr_scr_metrics:badRating';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end

    Vmag = default_Vmag;
    if Vmag_per_bus.isKey(pr.bus_id)
        Vmag = Vmag_per_bus(pr.bus_id);
    else
        try
            brow = find(mpc.bus(:,1)==pr.bus_id,1);
            if ~isempty(brow) && size(mpc.bus,2)>=8 && isfinite(mpc.bus(brow,8)) && mpc.bus(brow,8)>0
                Vmag = mpc.bus(brow,8);
            end
        catch
        end
    end
    if ~isfinite(Vmag) || Vmag <=0
        Vmag = default_Vmag;
    end
    pr.Vmag_used = Vmag;

    % If bus is SLACK (grounded), Zth = 0 => S_sc infinite => pass strong
    if ismember(bp, ref_pos)
        Zth = 0.0 + 0.0i;
        pr.Zth = Zth;
        pr.absZth = 0.0;
        % Infinite S_sc => pass
        pr.Ssc_pu = Inf;
        pr.Ssc_MVA = Inf;
        pr.SCR = Inf;
        pr.pass = true;
        pr.reason = sprintf('Bus %g is SLACK (grounded) => Zth=0, SCR=Inf pass', pr.bus_id);
        per_res(end+1,1)=pr;
        continue;
    end

    % Find reduced index
    idx_red = find(non_ref_pos==bp,1);
    if isempty(idx_red)
        pr.reason = sprintf('Bus %g not in non-SLACK set', pr.bus_id);
        pr.failure_id = 'stability:ibr_scr_metrics:badBusMapping';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end
    ek_red = zeros(numel(non_ref_pos),1);
    ek_red(idx_red) = 1.0;
    try
        % Audited primitive \ on reduced Y
        Vz_red = Yred \ ek_red;
    catch me
        pr.reason = sprintf('Yred\\ek failed: %s', me.message);
        pr.failure_id = 'stability:ibr_scr_metrics:linearSolveFail';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end
    if any(~isfinite(Vz_red))
        pr.reason = 'Vz_red non-finite - singular/island fail closed';
        pr.failure_id = 'stability:ibr_scr_metrics:nonFiniteZth';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end
    try
        res_norm = norm(Yred*Vz_red - ek_red, inf);
    catch
        res_norm = Inf;
    end
    if ~isfinite(res_norm) || res_norm > 1e-6
        pr.reason = sprintf('Yred*Vz - ek residual %.3e >1e-6 - singular/island', res_norm);
        pr.failure_id = 'stability:ibr_scr_metrics:largeResidual';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end

    Zth = Vz_red(idx_red);
    pr.Zth = Zth;
    pr.absZth = abs(Zth);
    if ~isfinite(Zth) || abs(Zth) < eps
        pr.reason = 'Zth non-finite or near zero - fail closed';
        pr.failure_id = 'stability:ibr_scr_metrics:badZth';
        pr.pass = false;
        per_res(end+1,1)=pr;
        continue;
    end

    Ssc_pu = (Vmag^2) / abs(Zth);
    Ssc_MVA = Ssc_pu * Sbase;
    SCR = Ssc_MVA / rating;
    pr.Ssc_pu = Ssc_pu;
    pr.Ssc_MVA = Ssc_MVA;
    pr.SCR = SCR;

    if SCR > threshold
        pr.pass = true;
        pr.reason = sprintf('SCR %.3f > %.1f pass', SCR, threshold);
    else
        pr.pass = false;
        pr.reason = sprintf('SCR %.3f <= %.1f fail closed (WECC REGC_A strong-grid)', SCR, threshold);
        pr.failure_id = 'stability:ibr_scr_metrics:weakGrid';
    end
    per_res(end+1,1)=pr;
end

scr.per_resource = per_res;
overall = true;
for k=1:numel(per_res)
    if per_res(k).eligible_for_scr && per_res(k).online
        if ~per_res(k).pass
            overall = false;
            break;
        end
    end
end
scr.overall_pass = overall;
if scr.is_singular
    scr.overall_pass = false;
end
scr.failure_id = '';
scr.failure_reason = '';
if ~overall
    scr.failure_id = 'stability:ibr_scr_metrics:weakGridOrMissing';
    scr.failure_reason = 'At least one online IBR fails SCR>3 or missing rating or singular Y.';
end
scr.fingerprint = fingerprint_struct(scr, resources);
end

% =========================================================================
function pr = empty_per_resource()
pr = struct('resource_index',[],'resource_id','', 'bus_id',NaN,'bus_position',[],...
    'online',false,'is_gfl',false,'eligible_for_scr',false,...
    'Zth',complex(NaN,NaN),'absZth',NaN,'Vmag_used',NaN,'Ssc_pu',NaN,'Ssc_MVA',NaN,...
    'rating_MVA',NaN,'SCR',NaN,'threshold',3.0,'pass',false,'reason','',...
    'failure_id','','classification',struct(),'scr_profile','',...
    'pcc_bus',NaN,'source_available',false,'status','', ...
    'prefault_V_pu',NaN,'threshold_applicable',logical(false));
end

function s = legacy_validity_scope()
%LEGACY_VALIDITY_SCOPE  What the legacy slack-grounded number is and is not.
%   The legacy path grounds every POWER-FLOW SLACK bus (mpc.bus col2 == 3), so
%   Zth = 0 there and SCR = Inf.  That models the slack as an ideal infinite
%   reactive source and deliberately ignores finite SG impedance.  It is a
%   screening metric only.
s = ['Legacy slack-grounded Thevenin (PROJECT_DERIVED): POWER-FLOW slack buses ' ...
    'are short-circuited (grounded), so Zth=0 and SCR=Inf at those buses; every ' ...
    'other source is ignored. This assumes an ideal infinite source at the slack ' ...
    'and does not model finite generator impedance. Screening only; not an IEC ' ...
    '60909 fault level and not a multi-infeed stability certificate (that is the ' ...
    'full-KCL SSSA). Does not apply to the eecon49_dual family.'];
end

function per_res = build_per_resource_empty(resources)
nr = numel(resources);
per_res = repmat(empty_per_resource(),0,1);
for k=1:nr
    pr = empty_per_resource();
    pr.resource_index = k;
    try, pr.resource_id = char(resources(k).resource_id); catch, pr.resource_id = sprintf('idx%d',k); end
    try, pr.bus_id = double(resources(k).bus_id); catch, pr.bus_id = NaN; end
    pr.reason = 'no mpc - not evaluated';
    pr.failure_id = 'stability:ibr_scr_metrics:missingMpc';
    per_res(end+1,1)=pr;
end
end

function per_res = build_per_resource_singular(resources, bus_ids, Sbase, thr, reason_tag)
if nargin<5, reason_tag='singularY'; end
nr = numel(resources);
per_res = repmat(empty_per_resource(),0,1);
for k=1:nr
    pr = empty_per_resource();
    pr.resource_index = k;
    try, pr.resource_id = char(resources(k).resource_id); catch, pr.resource_id = sprintf('idx%d',k); end
    try, pr.bus_id = double(resources(k).bus_id); catch, pr.bus_id = NaN; end
    pr.threshold = thr;
    pr.reason = sprintf('Ybus singular/island - fail closed (%s)', reason_tag);
    pr.failure_id = 'stability:ibr_scr_metrics:singularY';
    pr.pass = false;
    per_res(end+1,1)=pr;
end
end

function scr = source_aware_metrics(case_data, resources, topology, opt, scr, Sbase, threshold) %#ok<INUSD>
%SOURCE_AWARE_METRICS  Opt-in finite-source (transient-reactance) Thevenin SCR.
%   Called only when opt.scr_source_model == 'source_aware'.  Replaces slack
%   grounding with an explicit source model: each ONLINE synchronous machine
%   becomes a shunt 1/(1i*Xdp) at its bus (the SAME convention the classical
%   machine uses in its own network solve, stability.classical_dae ->
%   yg = 1/(1i*Xdp)), and no bus is an ideal infinite source.  A GFL converter
%   is a current source and is NOT a Thevenin voltage source; a GFM converter
%   enters only when the caller supplies opt.ibr_source_impedance for its
%   model_id.  PCCs are the online IBR buses.  A PCC whose ISLAND (physical
%   branch connectivity) holds no online modelled source fails closed
%   (status 'no_source_island'), never certifies strong.  The metric is
%   MEASURED for every eligible IBR, including the eecon49_dual family; the
%   WECC SCR>3 threshold is reported as APPLICABILITY, separate from the
%   measurement, and is not asserted for that family.
%
%   The heavy lifting is stability.scr_source_thevenin (pure, hand-checkable).
%   This function only marshals the project resource table, case mpc, prefault
%   voltage and ratings in and maps the result back onto the legacy
%   per_resource contract so existing consumers keep working.

nr = numel(resources);
scr.method = 'source_aware';
scr.validity_scope = ['Source-aware transient-reactance (X''d) Thevenin. ' ...
    'NOT an IEC 60909 subtransient fault level. Current-limited converters are ' ...
    'not modelled as ideal voltage sources; no-source islands fail closed. ' ...
    'Screening metric only; multi-infeed stability remains the full-KCL SSSA.'];
scr.per_resource = build_per_resource_empty(resources);

mpc = extract_mpc(case_data, topology, opt);
if isempty(mpc)
    scr.failure_id = 'stability:ibr_scr_metrics:missingMpc';
    scr.failure_reason = 'case_data.mpc with bus/branch/baseMVA required.';
    scr.is_singular = true;
    scr.topology_ok = false;
    sc = build_per_resource_empty(resources);
    for k = 1:numel(sc)
        sc(k).reason = 'no mpc - not evaluated';
        sc(k).failure_id = 'stability:ibr_scr_metrics:missingMpc';
    end
    scr.per_resource = sc;
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
end

Sbase = mpc.baseMVA;
scr.Sbase = Sbase;

% --- Network admittance (branches + shunts; NO machine, NO load) ------------
try
    [Ybus, bus_ids] = build_ybus_network(mpc);
catch me
    scr.failure_id = 'stability:ibr_scr_metrics:ybusBuild';
    scr.failure_reason = me.message;
    scr.is_singular = true;
    scr.topology_ok = false;
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
end
scr.Ybus = Ybus;
scr.Y_rcond = rcond(Ybus);
% Islands are handled per-resource (physical source availability), so the
% global singular flag is NOT set here; it would fail-close every candidate.
scr.is_singular = false;
scr.topology_ok = true;

% --- Sources: online SGs behind Xdp; GFM IBR only if coupling Z supplied ---
sources = build_sources(resources, case_data, opt);
scr.source_list = sources;

% --- PCCs: the online IBR buses --------------------------------------------
pcc_buses = [];
pcc_res_index = [];
for k = 1:nr
    if is_ibr_resource(resources(k)) && resource_online(resources(k))
        pcc_buses(end+1) = double(resources(k).bus_id); %#ok<AGROW>
        pcc_res_index(end+1) = k; %#ok<AGROW>
    end
end

% --- Prefault |V| per bus and rated MVA per bus ----------------------------
V_pu = build_prefault_V_per_bus(opt, mpc, bus_ids);
S_rated = nan(numel(bus_ids),1);
for k = 1:nr
    if is_ibr_resource(resources(k))
        bp = find(bus_ids==double(resources(k).bus_id),1);
        if ~isempty(bp)
            S_rated(bp) = rating_of(resources(k));
        end
    end
end

o = struct('V_pu', V_pu, 'Sbase', Sbase, 'S_rated', S_rated, ...
    'scr_threshold', threshold);
res = stability.scr_source_thevenin(Ybus, bus_ids, sources, pcc_buses, o);
scr.islands = res.islands;
scr.Yaug = res.Yaug;
scr.n_sources_online = res.n_sources_online;
scr.validity_scope = res.validity_scope;   % authoritative scope string
% Adopt the helper's source echo (it carries the modelled flag the raw
% build_sources list does not), so source_list and the fingerprint agree.
scr.source_list = res.source_list;

% --- Map onto the per_resource contract ------------------------------------
per_res = repmat(empty_per_resource(),0,1);
for k = 1:nr
    r = resources(k);
    pr = empty_per_resource();
    pr.resource_index = k;
    try, pr.resource_id = char(r.resource_id); catch, pr.resource_id = sprintf('idx%d',k); end
    try, pr.bus_id = double(r.bus_id); catch, pr.bus_id = NaN; end
    pr.threshold = threshold;
    pr.online = resource_online(r);
    is_ibr = is_ibr_resource(r);
    pr.is_gfl = resource_is_gfl(r);
    pr.scr_profile = scr_profile_of(r);
    pr.threshold_applicable = strcmp(pr.scr_profile,'wecc_regca_strong_grid');
    bp = find(bus_ids==pr.bus_id,1);
    pr.bus_position = bp;
    pr.classification = struct('Zth','PROJECT_DERIVED','Ssc','PROJECT_DERIVED',...
        'rating','CASE_DEFINED','threshold','CASE_DEFINED','V','CASE_DEFINED',...
        'Ybus','SOURCE_DEFINED','source_model','PROJECT_DERIVED','decision','PROJECT_DERIVED');

    if ~pr.online || ~is_ibr
        pr.eligible_for_scr = false;
        pr.reason = 'offline or not IBR - not evaluated';
        pr.pass = true;
        per_res(end+1,1) = pr; %#ok<AGROW>
        continue;
    end
    pr.eligible_for_scr = true;

    q = find(pcc_res_index==k, 1);
    if isempty(q)
        pr.reason = 'no PCC entry - internal error';
        pr.failure_id = 'stability:ibr_scr_metrics:noPccEntry';
        pr.pass = false;
        per_res(end+1,1) = pr; %#ok<AGROW>
        continue;
    end
    rp = res.per_pcc(q);
    pr.pcc_bus = rp.pcc_bus;
    pr.Zth = rp.Zth;
    pr.absZth = rp.absZth;
    pr.Vmag_used = rp.V_pu;
    pr.prefault_V_pu = rp.V_pu;
    pr.Ssc_pu = rp.Ssc_pu;
    pr.Ssc_MVA = rp.Ssc_MVA;
    pr.rating_MVA = rp.rating_MVA;
    pr.SCR = rp.SCR;
    pr.source_available = rp.source_available;
    pr.status = rp.status;
    pr.pass = rp.pass;                     % helper's threshold decision
    pr.reason = rp.reason;
    pr.failure_id = rp.failure_id;

    if ~pr.threshold_applicable && strcmp(rp.status,'valid') && isfinite(rp.SCR)
        % Measure, but do NOT borrow the WECC strong-grid threshold as a
        % requirement of a family it was never written for.  Measurement is
        % reported; applicability is separate (see docs/project contract).
        pr.pass = true;
        pr.reason = sprintf(['SCR %.4g measured (source-aware transient ' ...
            'Thevenin); WECC SCR>3 applicability not asserted for %s'], ...
            rp.SCR, pr.scr_profile);
    end
    per_res(end+1,1) = pr; %#ok<AGROW>
end
scr.per_resource = per_res;

% --- Overall pass: every evaluated online IBR must pass ---------------------
overall = true;
for k = 1:numel(per_res)
    if per_res(k).eligible_for_scr
        if ~per_res(k).pass
            overall = false;
            break;
        end
    end
end
scr.overall_pass = overall;
if ~overall
    scr.failure_id = 'stability:ibr_scr_metrics:weakGridOrMissing';
    scr.failure_reason = ['At least one online IBR fails source-aware SCR or ' ...
        'sits in a no-source island or lacks a rating.'];
end
scr.fingerprint = fingerprint_struct(scr, resources);
end

% =========================================================================
function mpc = extract_mpc(case_data, topology, opt)
mpc = [];
if isfield(case_data,'mpc') && isstruct(case_data.mpc) && isscalar(case_data.mpc)
    mpc = case_data.mpc;
elseif isfield(topology,'case_data') && isstruct(topology.case_data) && ...
        isfield(topology.case_data,'mpc')
    mpc = topology.case_data.mpc;
elseif isfield(opt,'case_data') && isstruct(opt.case_data) && ...
        isfield(opt.case_data,'mpc')
    mpc = opt.case_data.mpc;
end
if ~isempty(mpc) && (~isfield(mpc,'bus') || ~isfield(mpc,'branch') || ~isfield(mpc,'baseMVA'))
    mpc = [];
end
end

function tf = is_ibr_resource(r)
tf = true;
if isfield(r,'resource_type') && ~isempty(r.resource_type)
    tf = strcmpi(char(r.resource_type),'ibr');
end
end

function tf = is_sg_resource(r)
tf = false;
if isfield(r,'resource_type') && ~isempty(r.resource_type)
    tf = strcmpi(char(r.resource_type),'sg');
end
end

function tf = resource_online(r)
tf = false;
if isfield(r,'initial_online') && ~isempty(r.initial_online)
    tf = logical(r.initial_online);
elseif isfield(r,'online') && ~isempty(r.online)
    tf = logical(r.online);
end
end

function tf = resource_is_gfl(r)
is_gfl = false;
if isfield(r,'initial_mode') && ~isempty(r.initial_mode)
    is_gfl = strcmpi(char(r.initial_mode),'gfl');
elseif isfield(r,'mode') && ~isempty(r.mode)
    is_gfl = strcmpi(char(r.mode),'gfl');
elseif isfield(r,'supported_modes') && ~isempty(r.supported_modes)
    is_gfl = any(strcmpi(string(r.supported_modes),'gfl'));
end
tf = is_gfl && is_ibr_resource(r);
end

function p = scr_profile_of(r)
p = 'wecc_regca_strong_grid';
if isfield(r,'model_id') && ~isempty(r.model_id) && ...
        any(strcmpi(char(r.model_id),{'eecon49_dual'}))
    p = 'not_applicable_full_state_source_model';
end
end

function rating = rating_of(r)
rating = NaN;
if isfield(r,'ratings') && isstruct(r.ratings) && isfield(r.ratings,'Mbase') && ...
        ~isempty(r.ratings.Mbase) && isscalar(r.ratings.Mbase) && isfinite(r.ratings.Mbase)
    rating = double(r.ratings.Mbase);
end
end

function Xd = sg_xdp(r, case_data)
%SG_XDP  A synchronous machine's transient reactance on the system base (pu).
%   Order (all three NE39 sources are the SAME system-base number): explicit
%   resource dynamic_params.Xdp, else case_data.machines.units(bus).Xdp.  H and
%   D are NOT impedances and are never read here.
Xd = NaN;
if isfield(r,'dynamic_params') && isstruct(r.dynamic_params) && ...
        isfield(r.dynamic_params,'Xdp')
    v = r.dynamic_params.Xdp;
    if isscalar(v) && isfinite(v) && v > 0
        Xd = double(v);
        return;
    end
end
if isfield(case_data,'machines') && isstruct(case_data.machines) && ...
        isfield(case_data.machines,'units') && ~isempty(case_data.machines.units)
    u = case_data.machines.units;
    for j = 1:numel(u)
        if isfield(u(j),'bus') && isfield(u(j),'Xdp') && ...
                double(u(j).bus)==double(r.bus_id)
            v = u(j).Xdp;
            if isscalar(v) && isfinite(v) && v > 0
                Xd = double(v);
                return;
            end
        end
    end
end
end

function sources = build_sources(resources, case_data, opt)
%BUILD_SOURCES  Voltage sources to place behind their impedance.
%   Synchronous machines: prefer an explicit opt.sg_sources list (authoritative,
%   carries its own online flag); else derive one per SG resource, its Xdp read
%   by sg_xdp and its online flag from the resource table.
%   Converters: a GFM IBR enters ONLY when opt.ibr_source_impedance supplies a
%   coupling impedance for its model_id.  A GFL converter (and any converter not
%   opted in) is a current source and is NOT a Thevenin voltage source.
sources = repmat(struct('bus_id',NaN,'Z_pu',complex(NaN,NaN),'kind','','online',false),0,1);

used_explicit_sg = false;
if isfield(opt,'sg_sources') && ~isempty(opt.sg_sources) && isstruct(opt.sg_sources)
    ss = opt.sg_sources;
    for s = 1:numel(ss)
        e = struct('bus_id',NaN,'Z_pu',complex(NaN,NaN),'kind','sg','online',true);
        try, e.bus_id = double(ss(s).bus_id); catch, e.bus_id = NaN; end
        Xd = NaN;
        if isfield(ss(s),'Xdp_pu') && isscalar(ss(s).Xdp_pu)
            Xd = double(ss(s).Xdp_pu);
        elseif isfield(ss(s),'Xdp') && isscalar(ss(s).Xdp)
            Xd = double(ss(s).Xdp);
        end
        if isfield(ss(s),'online')
            try, e.online = logical(ss(s).online); catch, e.online = true; end
        end
        if isfinite(Xd) && Xd > 0
            e.Z_pu = 1i*Xd;
        end
        sources(end+1,1) = e; %#ok<AGROW>
    end
    used_explicit_sg = true;
end
if ~used_explicit_sg
    for k = 1:numel(resources)
        if ~is_sg_resource(resources(k))
            continue;
        end
        Xd = sg_xdp(resources(k), case_data);
        e = struct('bus_id', double(resources(k).bus_id), 'kind','sg', ...
            'online', resource_online(resources(k)), 'Z_pu', complex(NaN,NaN));
        if isfinite(Xd) && Xd > 0
            e.Z_pu = 1i*Xd;
        end
        sources(end+1,1) = e; %#ok<AGROW>
    end
end

if isfield(opt,'ibr_source_impedance') && isstruct(opt.ibr_source_impedance) && ...
        ~isempty(fieldnames(opt.ibr_source_impedance))
    for k = 1:numel(resources)
        if ~is_ibr_resource(resources(k)) || ~resource_online(resources(k))
            continue;
        end
        mid = '';
        if isfield(resources(k),'model_id') && ~isempty(resources(k).model_id)
            mid = char(resources(k).model_id);
        end
        if isempty(mid) || ~isfield(opt.ibr_source_impedance, mid)
            continue;
        end
        Zc = opt.ibr_source_impedance.(mid);
        if isscalar(Zc) && isfinite(real(Zc)) && isfinite(imag(Zc)) && abs(Zc) > 0
            sources(end+1,1) = struct('bus_id', double(resources(k).bus_id), ...
                'Z_pu', Zc, 'kind','gfm_ibr','online',true); %#ok<AGROW>
        end
    end
end
end

function V = build_prefault_V_per_bus(opt, mpc, bus_ids)
%BUILD_PREFAULT_V_PER_BUS  Prefault |V| per bus, bus_ids order.
%   Priority: opt.bus_voltages (struct keyed by bus-id string, or a length-nb
%   vector) then opt.V0_per_bus (vector), with the case's own mpc.bus col 8 as
%   the per-bus fallback and 1.0 pu last.  Mirrors the legacy marshalling.
nb = numel(bus_ids);
V = ones(nb,1);
provided = false(nb,1);

if isfield(opt,'bus_voltages') && ~isempty(opt.bus_voltages)
    if isstruct(opt.bus_voltages)
        fns = fieldnames(opt.bus_voltages);
        for kk = 1:numel(fns)
            bid = str2double(fns{kk});
            bp = find(bus_ids==bid,1);
            if ~isempty(bp) && isfinite(opt.bus_voltages.(fns{kk}))
                V(bp) = abs(opt.bus_voltages.(fns{kk}));
                provided(bp) = true;
            end
        end
    elseif isnumeric(opt.bus_voltages) && numel(opt.bus_voltages)==nb
        for kk = 1:nb
            if isfinite(opt.bus_voltages(kk))
                V(kk) = abs(opt.bus_voltages(kk));
                provided(kk) = true;
            end
        end
    end
end
if isfield(opt,'V0_per_bus') && ~isempty(opt.V0_per_bus) && ...
        isnumeric(opt.V0_per_bus) && numel(opt.V0_per_bus)==nb
    for kk = 1:nb
        if isfinite(opt.V0_per_bus(kk)) && abs(opt.V0_per_bus(kk))>0
            V(kk) = abs(opt.V0_per_bus(kk));
            provided(kk) = true;
        end
    end
end

if ~isempty(mpc) && isfield(mpc,'bus') && size(mpc.bus,2)>=8 && size(mpc.bus,1)==nb
    for kk = 1:nb
        if ~provided(kk) && isfinite(mpc.bus(kk,8)) && mpc.bus(kk,8)>0
            V(kk) = mpc.bus(kk,8);
        end
    end
end
V(~isfinite(V) | V<=0) = 1.0;
end

function [Ybus, bus_ids] = build_ybus_network(mpc)
bus = mpc.bus;
br = mpc.branch;
nb = size(bus,1);
bus_ids = bus(:,1);
Ybus = zeros(nb, nb);
for k=1:size(br,1)
    if br(k,11)==0, continue; end
    from_id = br(k,1);
    to_id = br(k,2);
    i = find(bus_ids==from_id,1);
    j = find(bus_ids==to_id,1);
    if isempty(i) || isempty(j), continue; end
    r = br(k,3); x = br(k,4); b = br(k,5);
    tap = br(k,9); shift = br(k,10);
    if tap==0, tap=1; end
    a = tap * exp(1i*deg2rad(shift));
    yser = 1/(r+1i*x);
    Ybus(i,i) = Ybus(i,i) + (yser + 1i*b/2)/(a*conj(a));
    Ybus(j,j) = Ybus(j,j) + yser + 1i*b/2;
    Ybus(i,j) = Ybus(i,j) - yser/conj(a);
    Ybus(j,i) = Ybus(j,i) - yser/a;
end
if size(bus,2)>=6
    Ybus = Ybus + diag((bus(:,5) + 1i*bus(:,6))/mpc.baseMVA);
end
end

function fp = fingerprint_struct(scr, resources)
%FINGERPRINT_STRUCT  Deterministic cache key for a metric result.
%   Legacy results keep the historical 'scr_v1' string verbatim (cache
%   compatibility).  A source-aware result uses 'scr_v2_source_aware' and a
%   digest that covers the METHOD, the source impedances and their
%   online/modelled status, the island membership, the rated MVA, the
%   validity scope and the actual network/source matrices.  Any change in
%   those flips the key even when the scalar SCR is unchanged.
method = 'legacy_slack_grounding';
if isfield(scr,'method') && ~isempty(scr.method)
    method = char(scr.method);
end
try
    ids = arrayfun(@(r) char(r.resource_id), resources, 'UniformOutput', false);
    id_str = strjoin(ids, ',');
    scr_vals = '';
    if ~isempty(scr.per_resource)
        for k=1:numel(scr.per_resource)
            pr = scr.per_resource(k);
            if isfinite(pr.SCR)
                scr_vals = [scr_vals sprintf(';%s:%.6g', pr.resource_id, pr.SCR)]; %#ok<AGROW>
            else
                scr_vals = [scr_vals sprintf(';%s:NaN', pr.resource_id)]; %#ok<AGROW>
            end
        end
    end
    if strcmp(method,'source_aware')
        fp = sprintf(['scr_v2_source_aware|%s|Sbase=%.0f|thr=%.6g|' ...
            'rcond=%.3e|ids=%s|scr=%s'], ...
            digest_of(source_aware_fingerprint_vector(scr,resources)), ...
            scr.Sbase, scr.threshold, scr.Y_rcond, id_str, scr_vals);
    else
        fp = sprintf('scr_v1|Sbase=%.0f|thr=%.1f|rcond=%.3e|ids=%s|scr=%s', ...
            scr.Sbase, scr.threshold, scr.Y_rcond, id_str, scr_vals);
    end
catch
    if strcmp(method,'source_aware')
        fp = sprintf('scr_v2_source_aware|degraded|thr=%.6g|rcond=%.3e', ...
            scr.threshold, scr.Y_rcond);
    else
        fp = sprintf('scr_v1|thr=%.1f|rcond=%.3e', scr.threshold, scr.Y_rcond);
    end
end
end

function v = source_aware_fingerprint_vector(scr, resources)
%SOURCE_AWARE_FINGERPRINT_VECTOR  Numeric encoding of every input that
%   determines a source-aware metric: validity scope, network and augmented
%   matrices, source impedances/status, island membership, and each
%   resource's identity/bus/rating/online flag.
v = 2;                              % source-aware schema tag
sc = '';
if isfield(scr,'validity_scope') && ~isempty(scr.validity_scope)
    sc = char(scr.validity_scope);
end
v = [v; double(sc(:))];
v(end+1,1) = num_or_nan(scr,'Sbase');
v(end+1,1) = num_or_nan(scr,'threshold');
if isfield(scr,'Ybus') && ~isempty(scr.Ybus)
    v = [v; real(scr.Ybus(:)); imag(scr.Ybus(:))];
end
if isfield(scr,'Yaug') && ~isempty(scr.Yaug)
    v = [v; real(scr.Yaug(:)); imag(scr.Yaug(:))];
end
if isfield(scr,'source_list') && ~isempty(scr.source_list)
    for s = 1:numel(scr.source_list)
        sl = scr.source_list(s);
        v(end+1,1) = num_or_nan(sl,'bus_id');
        v(end+1,1) = real(sl.Z_pu);
        v(end+1,1) = imag(sl.Z_pu);
        v(end+1,1) = double(logical(sl.online));
        v(end+1,1) = double(logical(sl.modeled));
    end
end
if isfield(scr,'islands') && ~isempty(scr.islands)
    for ii = 1:numel(scr.islands)
        isl = scr.islands(ii);
        v(end+1,1) = isl.id;
        m = isl.members(:);
        v(end+1,1) = numel(m);
        v = [v; m];
        v(end+1,1) = double(logical(isl.has_source));
    end
end
for k = 1:numel(resources)
    r = resources(k);
    rid = '';
    try, rid = char(r.resource_id); catch, end
    v = [v; double(rid(:))];
    v(end+1,1) = num_or_nan(r,'bus_id');
    v(end+1,1) = num_or_nan(r,'ratings','Mbase');
    v(end+1,1) = double(resource_online(r));
end
end

function h = digest_of(v)
%DIGEST_OF  Short deterministic digest of a numeric vector.
%   SHA-256 over the IEEE-754 bytes when a JVM is present; otherwise a
%   deterministic sum-based signature.  Non-finite values get fixed
%   sentinels so the byte stream is always well defined.
v = double(v(:));
v(isnan(v)) = -realmax;
v(isinf(v)) = realmax;
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    d = md.digest(typecast(v,'int8'));
    u = typecast(d,'uint8');
    h = lower(reshape(dec2hex(u,2)',1,[]));
catch
    if isempty(v), v = 0; end
    h = sprintf('d_%.12g_%.12g_%.12g_%d', sum(v), sum(v.^2), sum(abs(v).^3), numel(v));
end
end

function x = num_or_nan(s, f1, f2)
x = NaN;
if nargin < 3
    if isfield(s,f1) && isnumeric(s.(f1)) && isscalar(s.(f1))
        x = double(s.(f1));
    end
else
    if isfield(s,f1) && isstruct(s.(f1)) && isfield(s.(f1),f2) && ...
            isnumeric(s.(f1).(f2)) && isscalar(s.(f1).(f2))
        x = double(s.(f1).(f2));
    end
end
end
