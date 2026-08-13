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
%     Y(ii,ii) += yser/(a*conj(a)) + j*b/2
%     Y(jj,jj) += yser + j*b/2
%     Y(ii,jj) -= yser/conj(a)
%     Y(jj,ii) -= yser/a
%     + bus shunt: diag((GS+j*BS)/baseMVA)  [bus(:,5), bus(:,6)]
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

% --- defaults ---
scr = struct();
scr.Sbase = Sbase;
scr.threshold = threshold;
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
scr.classification = struct('Ybus','SOURCE_DEFINED','Zth','PROJECT_DERIVED',...
    'Ssc','PROJECT_DERIVED','rating','CASE_DEFINED','threshold','CASE_DEFINED');

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

% --- REF grounding for Thevenin (voltage sources shorted) ---
% For SCR, Thevenin is seen with REF buses (type 3) shorted (grounded).
% We therefore reduce Ybus by removing REF rows/cols when they exist.
% Classification: PROJECT_DERIVED (Thevenin with REF shorted).
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
    % All buses are REF – degenerate, treat as singular/island
    scr.Y_rcond = 0;
    scr.is_singular = true;
    scr.topology_ok = false;
    scr.failure_id = 'stability:ibr_scr_metrics:allRef';
    scr.failure_reason = 'All buses are REF - no non-REF bus for Thevenin.';
    scr.per_resource = build_per_resource_singular(resources, bus_ids, Sbase, threshold, 'allRef');
    scr.fingerprint = fingerprint_struct(scr, resources);
    return;
end

Yred = Ybus(non_ref_pos, non_ref_pos);
% rcond on reduced Y (after REF grounding) – primary singularity check
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
    % Both project full-state dual families model the plant explicitly, so the
    % WECC strong-grid SCR screening profile does not apply to them.  A family
    % missing from this list silently becomes SCR-eligible and changes the gate.
    if isfield(r,'model_id') && ...
            any(strcmpi(char(r.model_id),{'eecon49_dual','decoupled_dual'}))
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

    % If bus is REF (grounded), Zth = 0 => S_sc infinite => pass strong
    if ismember(bp, ref_pos)
        Zth = 0.0 + 0.0i;
        pr.Zth = Zth;
        pr.absZth = 0.0;
        % Infinite S_sc => pass
        pr.Ssc_pu = Inf;
        pr.Ssc_MVA = Inf;
        pr.SCR = Inf;
        pr.pass = true;
        pr.reason = sprintf('Bus %g is REF (grounded) => Zth=0, SCR=Inf pass', pr.bus_id);
        per_res(end+1,1)=pr;
        continue;
    end

    % Find reduced index
    idx_red = find(non_ref_pos==bp,1);
    if isempty(idx_red)
        pr.reason = sprintf('Bus %g not in non-REF set', pr.bus_id);
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
    'failure_id','','classification',struct(),'scr_profile','');
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
    Ybus(i,i) = Ybus(i,i) + yser/(a*conj(a)) + 1i*b/2;
    Ybus(j,j) = Ybus(j,j) + yser + 1i*b/2;
    Ybus(i,j) = Ybus(i,j) - yser/conj(a);
    Ybus(j,i) = Ybus(j,i) - yser/a;
end
if size(bus,2)>=6
    Ybus = Ybus + diag((bus(:,5) + 1i*bus(:,6))/mpc.baseMVA);
end
end

function fp = fingerprint_struct(scr, resources)
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
    fp = sprintf('scr_v1|Sbase=%.0f|thr=%.1f|rcond=%.3e|ids=%s|scr=%s', ...
        scr.Sbase, scr.threshold, scr.Y_rcond, id_str, scr_vals);
catch
    fp = sprintf('scr_v1|thr=%.1f|rcond=%.3e', scr.threshold, scr.Y_rcond);
end
end
