function out = scr_source_thevenin(Ynet, bus_ids, sources, pcc_buses, opt)
%SCR_SOURCE_THEVENIN  Source-aware Thevenin strength at PCC buses.
%
%   OUT = stability.scr_source_thevenin(YNET, BUS_IDS, SOURCES, PCC_BUSES, OPT)
%
%   Pure function (no solver, no inv/pinv, no file/global state).  It is the
%   audited core behind the 'source_aware' branch of stability.ibr_scr_metrics
%   and is exercised directly by tests/test_ne39_scr_source_aware.m against
%   hand-computed two- and three-bus networks.
%
%   INPUTS
%     YNET     nb x nb complex.  The NETWORK admittance: branches + bus shunt
%              only.  NO machine source admittance, NO load admittance.  The
%              caller builds it with the project branch/tap/shunt stamp
%              (see stability.ibr_scr_metrics -> build_ybus_network: the
%              MATPOWER-per-unit stamp yser=1/(r+jx), off-nominal tap
%              a = tap*exp(j*shift), (yser + j*b/2)/(a*a') on the from-diagonal
%              (canonical MATPOWER Yff), -yser/a' and -yser/a off-diagonal,
%              +j*b/2 on the to-diagonal, plus the bus shunt
%              (GS+j*BS)/baseMVA).  This function does NOT rebuild it, so the
%              stamp has exactly one definition in the codebase.
%     BUS_IDS  nb x 1 external bus ids (row order matches YNET).
%     SOURCES  1 x ns struct array of voltage sources to be placed BEHIND
%              their own impedance:
%                 .bus_id  double external bus id
%                 .Z_pu    complex series impedance to the internal node, pu
%                 .kind    char 'sg' | 'gfm_ibr'   (label only)
%                 .online  logical; if false the source is NOT modelled
%     PCC_BUSES  vector of external bus ids at which Zth is measured.
%     OPT       struct, all fields optional:
%                 .V_pu          nb x 1 prefault |V| per bus, bus_ids order
%                                (default 1.0).  One scalar per bus; any
%                                per-bus map/vector marshalling is the
%                                caller's job so this stays a pure function.
%                 .Sbase         system MVA base (default 100)
%                 .S_rated       nb x 1 rated MVA per bus (NaN where none).
%                                SCR is NaN where the rating is missing;
%                                the caller decides fail-closed semantics.
%                 .scr_threshold default 3.0
%                 .rcond_floor   island-reduced singularity floor (1e-12)
%
%   MODEL (PROJECT_DERIVED, TRANSIENT-REACTANCE THEVENIN)
%     For a Thevenin strength (all internal EMF sources set to zero, prefault
%     voltage applied at the PCC), a voltage source behind a series Z to its
%     internal node is exactly a shunt admittance 1/Z at its bus.  This is the
%     SAME representation the project classical machine already uses in its own
%     network solve (see stability.classical_dae: yg = 1/(1i*Xdp) is added at
%     the generator bus, and the internal EMF is injected as a current).  The
%     source-aware bus matrix is therefore
%         Yaug = Ynet + diag( sum_{online sources s at bus b} 1/Z_s )
%     No bus is an ideal infinite source: a source contributes only through its
%     DECLARED impedance.  This is the whole difference from legacy slack
%     grounding, which short-circuited SLACK buses so Zth = 0 => SCR = Inf.
%
%     For a PCC on bus k, Zth_k = (Yaug^{-1})_{kk}, computed by solving
%     Yaug * vz = e_k and reading vz(k).  Never inv/pinv.  The solve is
%     restricted to k's ISLAND, so an unreachable part of the network cannot
%     make the island's submatrix singular nor add stiffness across a break.
%
%   ISLANDS AND SOURCE AVAILABILITY (physical, not rcond only)
%     Islands are the connected components of the BRANCH graph: an off-diagonal
%     |Ynet_ij| > 0 is an edge (shunt-only buses, which have no off-diagonal,
%     are singletons).  A PCC's island is a valid source island ONLY if it
%     contains at least one ONLINE source.  A PCC whose island holds no online
%     source is status 'no_source_island' and is NEVER certified strong, no
%     matter how well conditioned some submatrix is.  This is checked from the
%     topology, in addition to the numerical rcond/residual checks.
%
%   SCOPE OF THE NUMBER (what this metric is and is NOT)
%     This is a TRANSIENT-reactance (X'd) network-strength screening number.
%     It is NOT an IEC 60909 subtransient fault level: there is no
%     subtransient (X''d) data, no DC offset, no fault shunt, and no network
%     capacitance in the calculation.  A fault shunt or a line capacitance must
%     never be allowed to masquerade as source strength, so neither is included.
%     A current-limited converter is NOT replaced by an ideal voltage source;
%     a GFM converter enters only through an explicitly supplied coupling
%     impedance, and a GFL converter (a current source) is not a Thevenin
%     voltage source at all.  The number is a screening metric; it is not a
%     certification of multi-infeed stability, which remains the job of the
%     full-KCL SSSA.
%
%   OUTPUT (struct)
%     .method               'source_aware_transient_xdp'
%     .validity_scope       char
%     .bus_ids, .Sbase, .threshold
%     .Yaug                 source-aware bus matrix
%     .per_pcc              1 x np struct:
%         pcc_bus, pcc_position, island_id, Zth, absZth, V_pu,
%         Ssc_pu, Ssc_MVA, rating_MVA, SCR, threshold, pass,
%         source_available, status, reason, failure_id
%     .islands              1 x ni struct: id, members (bus ids), has_source
%     .n_sources_online
%     .source_list          1 x ns echo: bus_id, kind, Z_pu, online, modeled
%     .all_pcc_have_source  logical
%
%   See also stability.ibr_scr_metrics, tests.test_ne39_scr_source_aware.

arguments
    Ynet double
    bus_ids double
    sources struct = struct([])
    pcc_buses double = []
    opt struct = struct()
end

Sbase = 100.0;
threshold = 3.0;
rcond_floor = 1e-12;
if isfield(opt,'Sbase') && ~isempty(opt.Sbase) && isscalar(opt.Sbase) && opt.Sbase > 0
    Sbase = opt.Sbase;
end
if isfield(opt,'scr_threshold') && ~isempty(opt.scr_threshold) && ...
        isscalar(opt.scr_threshold) && isfinite(opt.scr_threshold) && opt.scr_threshold > 0
    threshold = opt.scr_threshold;
end
if isfield(opt,'rcond_floor') && ~isempty(opt.rcond_floor) && ...
        isscalar(opt.rcond_floor) && isfinite(opt.rcond_floor) && opt.rcond_floor > 0
    rcond_floor = opt.rcond_floor;
end

bus_ids = bus_ids(:);
nb = numel(bus_ids);

out = struct();
out.method = 'source_aware_transient_xdp';
out.validity_scope = [ ...
    'Transient-reactance (X''d) network-strength Thevenin. NOT an IEC 60909 ' ...
    'subtransient fault level: no X''''d, no DC offset, no fault shunt, no ' ...
    'network capacitance. Current-limited converters are not modelled as ' ...
    'ideal voltage sources. Screening metric only; multi-infeed stability ' ...
    'remains the full-KCL SSSA.'];
out.bus_ids = bus_ids;
out.Sbase = Sbase;
out.threshold = threshold;
out.Yaug = [];
out.per_pcc = empty_per_pcc();
out.islands = empty_island();
out.n_sources_online = 0;
out.source_list = echo_sources(sources);
out.all_pcc_have_source = false;

if nb == 0 || isempty(Ynet)
    out.per_pcc = repmat(empty_per_pcc(), 0, 1);
    return;
end
if size(Ynet,1) ~= nb || size(Ynet,2) ~= nb
    error('stability:scr_source_thevenin:sizeMismatch', ...
        'Ynet must be %d x %d to match bus_ids.', nb, nb);
end

% --- Islands: connected components of the branch graph --------------------
% Off-diagonal nonzero => a branch couples the two buses.  Shunt-only buses
% (no off-diagonal) are singletons.  Physical connectivity, not rcond.
adj = (abs(Ynet) > 0);
adj(1:nb+1:end) = false;                 % drop the diagonal
island_id = connected_components(adj, nb);

% --- Model offline sources as absent and place online sources as shunts ----
Yaug = Ynet;
n_online = 0;
sl = out.source_list;
for s = 1:numel(sl)
    if ~sl(s).modeled
        continue;
    end
    b = sl(s).bus_id;
    bp = find(bus_ids == b, 1);
    if isempty(bp)
        continue;                        % source on a bus outside this network
    end
    Z = sl(s).Z_pu;
    Yaug(bp,bp) = Yaug(bp,bp) + 1/Z;
    n_online = n_online + 1;
end
out.n_sources_online = n_online;
out.Yaug = Yaug;

% --- Island table with source availability --------------------------------
has_source_per_island = false(1, max(island_id));
% A bus with an explicitly modelled source counts; membership is by bus.
aug_diag_source = false(nb,1);
for s = 1:numel(sl)
    if ~sl(s).modeled, continue; end
    bp = find(bus_ids == sl(s).bus_id, 1);
    if ~isempty(bp), aug_diag_source(bp) = true; end
end
islands = repmat(empty_island(), 0, 1);
for ii = 1:max(island_id)
    members = find(island_id == ii);
    has_src = any(aug_diag_source(members));
    has_source_per_island(ii) = has_src; %#ok<AGROW>
    isl = empty_island();
    isl.id = ii;
    isl.members = bus_ids(members).';
    isl.has_source = has_src;
    islands(end+1,1) = isl; %#ok<AGROW>
end
out.islands = islands;

% --- Prefault voltage per bus ---------------------------------------------
V_pu = ones(nb,1);
if isfield(opt,'V_pu') && ~isempty(opt.V_pu)
    if isnumeric(opt.V_pu) && numel(opt.V_pu) == nb
        V_pu = abs(opt.V_pu(:));
        V_pu(~isfinite(V_pu) | V_pu <= 0) = 1.0;
    else
        error('stability:scr_source_thevenin:badVpu', ...
            'opt.V_pu must have one finite entry per bus (numel %d).', nb);
    end
end

% --- Rated MVA per bus -----------------------------------------------------
S_rated = nan(nb,1);
if isfield(opt,'S_rated') && ~isempty(opt.S_rated)
    if isnumeric(opt.S_rated) && numel(opt.S_rated) == nb
        S_rated = double(opt.S_rated(:));
    else
        error('stability:scr_source_thevenin:badSRated', ...
            'opt.S_rated must have one entry per bus (numel %d).', nb);
    end
end

% --- Per-PCC Thevenin ------------------------------------------------------
pcc_buses = pcc_buses(:).';
per = repmat(empty_per_pcc(), 0, 1);
all_have_source = true;
for q = 1:numel(pcc_buses)
    pr = empty_per_pcc();
    pr.pcc_bus = pcc_buses(q);
    pr.threshold = threshold;
    pos = find(bus_ids == pr.pcc_bus, 1);
    pr.pcc_position = pos;
    if isempty(pos)
        pr.status = 'invalid';
        pr.source_available = false;
        pr.reason = sprintf('PCC bus %g not in network bus_ids', pr.pcc_bus);
        pr.failure_id = 'stability:scr_source_thevenin:badPcc';
        per(end+1,1) = pr; %#ok<AGROW>
        all_have_source = false;
        continue;
    end
    iid = island_id(pos);
    pr.island_id = iid;
    pr.source_available = has_source_per_island(iid);
    if ~pr.source_available
        pr.status = 'no_source_island';
        pr.reason = sprintf(['PCC bus %g island %d has no online modelled ' ...
            'source - fail closed (physical source availability, not rcond)'], ...
            pr.pcc_bus, iid);
        pr.failure_id = 'stability:scr_source_thevenin:noSourceIsland';
        per(end+1,1) = pr; %#ok<AGROW>
        all_have_source = false;
        continue;
    end

    members = find(island_id == iid);
    Yii = Yaug(members, members);
    local = find(members == pos, 1);
    e = zeros(numel(members),1);
    e(local) = 1.0;

    rc = rcond(Yii);
    if ~isfinite(rc) || rc < rcond_floor
        pr.status = 'invalid';
        pr.reason = sprintf('island %d rcond %.3e < %.1e - singular fail closed', ...
            iid, rc, rcond_floor);
        pr.failure_id = 'stability:scr_source_thevenin:singularIsland';
        per(end+1,1) = pr; %#ok<AGROW>
        continue;
    end
    try
        vz = Yii \ e;
    catch me
        pr.status = 'invalid';
        pr.reason = sprintf('island solve failed: %s', me.message);
        pr.failure_id = 'stability:scr_source_thevenin:linearSolveFail';
        per(end+1,1) = pr; %#ok<AGROW>
        continue;
    end
    res_norm = norm(Yii*vz - e, inf);
    if any(~isfinite(vz)) || ~isfinite(res_norm) || res_norm > 1e-6
        pr.status = 'invalid';
        pr.reason = sprintf('island solve residual %.3e nonfinite/nonconverged', res_norm);
        pr.failure_id = 'stability:scr_source_thevenin:largeResidual';
        per(end+1,1) = pr; %#ok<AGROW>
        continue;
    end
    Zth = vz(local);
    pr.Zth = Zth;
    pr.absZth = abs(Zth);
    pr.V_pu = V_pu(pos);
    if ~isfinite(Zth) || abs(Zth) < eps
        pr.status = 'invalid';
        pr.reason = 'Zth non-finite or near zero - fail closed';
        pr.failure_id = 'stability:scr_source_thevenin:badZth';
        per(end+1,1) = pr; %#ok<AGROW>
        continue;
    end

    pr.Ssc_pu = (pr.V_pu^2)/pr.absZth;
    pr.Ssc_MVA = pr.Ssc_pu * Sbase;
    pr.rating_MVA = S_rated(pos);
    if isfinite(pr.rating_MVA) && pr.rating_MVA > 0
        pr.SCR = pr.Ssc_MVA / pr.rating_MVA;
        if pr.SCR > threshold
            pr.pass = true;
            pr.status = 'valid';
            pr.reason = sprintf('SCR %.4g > %.1f (source-aware transient Thevenin)', ...
                pr.SCR, threshold);
        else
            pr.pass = false;
            pr.status = 'valid';
            pr.reason = sprintf('SCR %.4g <= %.1f (source-aware transient Thevenin)', ...
                pr.SCR, threshold);
            pr.failure_id = 'stability:scr_source_thevenin:weakGrid';
        end
    else
        pr.status = 'valid';
        pr.SCR = NaN;
        pr.pass = false;
        pr.reason = 'no rated MVA at PCC bus - SCR undefined, fail closed';
        pr.failure_id = 'stability:scr_source_thevenin:missingRating';
    end
    per(end+1,1) = pr; %#ok<AGROW>
end

out.per_pcc = per;
out.all_pcc_have_source = all_have_source;
end

% =========================================================================
function cc = connected_components(adj, nb)
%CONNECTED_COMPONENTS  Union-find labels for a symmetric logical adjacency.
parent = 1:nb;
for i = 1:nb
    nbrs = find(adj(i,:));
    for j = nbrs
        if j > i
            ra = find_root(parent, i);
            rb = find_root(parent, j);
            if ra ~= rb
                parent(rb) = ra;
            end
        end
    end
end
cc = zeros(1, nb);
next = 0;
for i = 1:nb
    r = find_root(parent, i);
    if cc(r) == 0
        next = next + 1;
        cc(r) = next;
    end
end
lab = zeros(1, nb);
for i = 1:nb
    lab(i) = cc(find_root(parent, i));
end
cc = lab;
end

function r = find_root(parent, i)
r = i;
while parent(r) ~= r
    r = parent(r);
end
end

function pr = empty_per_pcc()
pr = struct('pcc_bus', NaN, 'pcc_position', [], 'island_id', NaN, ...
    'Zth', complex(NaN,NaN), 'absZth', NaN, 'V_pu', NaN, ...
    'Ssc_pu', NaN, 'Ssc_MVA', NaN, 'rating_MVA', NaN, 'SCR', NaN, ...
    'threshold', 3.0, 'pass', false, 'source_available', false, ...
    'status', 'invalid', 'reason', '', 'failure_id', '');
end

function isl = empty_island()
isl = struct('id', NaN, 'members', [], 'has_source', false);
end

function sl = echo_sources(sources)
sl = repmat(struct('bus_id', NaN, 'kind', '', 'Z_pu', complex(NaN,NaN), ...
    'online', false, 'modeled', false), 0, 1);
if isempty(sources)
    return;
end
for s = 1:numel(sources)
    e = struct('bus_id', NaN, 'kind', '', 'Z_pu', complex(NaN,NaN), ...
        'online', false, 'modeled', false);
    try, e.bus_id = double(sources(s).bus_id); catch, e.bus_id = NaN; end
    try, e.kind = char(sources(s).kind); catch, e.kind = ''; end
    try, e.Z_pu = sources(s).Z_pu; catch, e.Z_pu = complex(NaN,NaN); end
    on = true;
    if isfield(sources(s),'online')
        try, on = logical(sources(s).online); catch, on = false; end
    end
    e.online = on;
    % Modelled only if online, on a bus, and behind a finite nonzero impedance.
    Z = e.Z_pu;
    e.modeled = on && isfinite(e.bus_id) && ...
        isscalar(Z) && isfinite(real(Z)) && isfinite(imag(Z)) && abs(Z) > 0;
    sl(end+1,1) = e; %#ok<AGROW>
end
end
