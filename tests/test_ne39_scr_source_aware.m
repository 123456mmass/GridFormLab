function tests = test_ne39_scr_source_aware()
%TEST_NE39_SCR_SOURCE_AWARE  Source-aware (finite-source) SCR metric tests.
%
%   Covers the opt-in 'source_aware' branch of stability.ibr_scr_metrics and
%   its pure core stability.scr_source_thevenin, independently of the legacy
%   slack-grounded path, which must stay bit-identical:
%     - two-bus and three-bus Zth against closed-form hand values
%     - reference-bus invariance (no slack grounding in source-aware mode)
%     - finite SG impedance gives a FINITE, smaller SCR than slack grounding
%     - rating scaling (SCR proportional to 1/rating)
%     - source outage raises Zth; an island WITHOUT a source fails closed
%     - physical source availability vs a well-conditioned submatrix
%     - branch/tap/shunt stamp re-derived by an independent congruence oracle
%     - fingerprint invalidation on status / rating / topology change
%     - method + validity_scope published on every return path
%     - opt.ibr_source_impedance opt-in for a GFM converter source
%     - legacy default untouched; bad source-model opt rejected
%     - no inv/pinv in the metric or helper source
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
% Hand-checkable Thevenin
% =========================================================================
function test_two_bus_hand_calc(testCase)
% Bus 1: SG behind Xdp=0.2.  Bus 2: PCC.  Line 0.01+j0.1.
% Source-aware Yaug at bus1 has a shunt 1/(j0.2); with no other shunts the
% Thevenin at bus2 is the series path Zline + jXdp exactly.
Xdp = 0.2; Zline = 0.01 + 1i*0.10;
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,Xdp), ibr_resource('IBR2',2,100,'eecon49_dual') ];
scr = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));

pr = entry_for(scr, 2);
Zth_hand = Zline + 1i*Xdp;
testCase.verifyEqual(pr.Zth, Zth_hand, 'AbsTol', 1e-12);
testCase.verifyEqual(pr.absZth, abs(Zth_hand), 'AbsTol', 1e-12);
% Ssc = |V|^2 / |Zth| on Sbase=100; SCR = Ssc / 100 MVA.
Ssc_hand = (1.0^2/abs(Zth_hand))*100;
testCase.verifyEqual(pr.Ssc_MVA, Ssc_hand, 'RelTol', 1e-10);
testCase.verifyEqual(pr.SCR, Ssc_hand/100, 'RelTol', 1e-10);
testCase.verifyTrue(pr.source_available);
testCase.verifyEqual(pr.status, 'valid');
testCase.verifyEqual(scr.method, 'source_aware');
testCase.verifyTrue(isfield(scr,'validity_scope') && ~isempty(scr.validity_scope));
end

function test_three_bus_hand_calc_two_sources(testCase)
% Two finite sources in parallel behind their own reactances, PCC at bus 3.
% Zth3 = (Z13 + jX1) || (Z23 + jX2) - the parallel of the two source paths.
Z13 = 0.02 + 1i*0.12; X1 = 0.25;
Z23 = 0.03 + 1i*0.08; X2 = 0.30;
mpc = ne39_style_mpc([1;2;3], [ ...
    1 3 0.02 0.12 0 100 100 100 0 0 1 1 1; ...
    2 3 0.03 0.08 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,X1), sg_resource('SG2',2,615,X2), ...
        ibr_resource('IBR3',3,100,'eecon49_dual') ];
scr = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));
pr = entry_for(scr, 3);
Z1 = Z13 + 1i*X1; Z2 = Z23 + 1i*X2;
Zth_hand = (Z1*Z2)/(Z1+Z2);
testCase.verifyEqual(pr.Zth, Zth_hand, 'AbsTol', 1e-12);
Ssc_hand = (1.0^2/abs(Zth_hand))*100;
testCase.verifyEqual(pr.SCR, Ssc_hand/100, 'RelTol', 1e-10);
end

% =========================================================================
% Invariance, finiteness, scaling, outage, islands
% =========================================================================
function test_reference_bus_invariance(testCase)
% Source-aware strength depends on the NETWORK and the SOURCES, never on which
% bus the power flow designates slack.  Move the slack designation and the
% measured SCR must be identical.
mpcA = ne39_style_mpc([1;2;3], [ ...
    1 3 0.02 0.12 0 100 100 100 0 0 1 1 1; ...
    2 3 0.03 0.08 0 100 100 100 0 0 1 1 1], []);
mpcB = mpcA; mpcB.bus(1,2) = 1; mpcB.bus(2,2) = 2;  % slack moves 1->2
res = [ sg_resource('SG1',1,615,0.25), sg_resource('SG2',2,615,0.30), ...
        ibr_resource('IBR3',3,100,'eecon49_dual') ];
opt = struct('scr_source_model','source_aware');
sA = stability.ibr_scr_metrics(struct('mpc',mpcA), res, struct(), opt);
sB = stability.ibr_scr_metrics(struct('mpc',mpcB), res, struct(), opt);
testCase.verifyEqual(entry_for(sA,3).SCR, entry_for(sB,3).SCR, 'RelTol', 1e-12);
testCase.verifyEqual(entry_for(sA,3).Zth, entry_for(sB,3).Zth, 'AbsTol', 1e-12);
end

function test_finite_impedance_smaller_than_slack_grounding(testCase)
% The IBR sits at the slack bus.  Legacy grounds the slack -> Zth=0 -> SCR=Inf.
% Source-aware puts the (remote) SG behind jXdp so the SCR is finite and
% strictly smaller.  This is the whole point of the correction and the test
% has teeth against a no-op.
Xdp = 0.25; Zline = 0.01 + 1i*0.10;
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
res = [ ibr_resource('IBR1',1,100,'synthetic_gfl'), sg_resource('SG2',2,615,Xdp) ];
leg = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), struct());
testCase.verifyEqual(leg.method, 'legacy_slack_grounding');
testCase.verifyTrue(isinf(entry_for(leg,1).SCR));   % slack grounded -> Inf
sa = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));
Zth = Zline + 1i*Xdp;                               % series source path
testCase.verifyTrue(isfinite(entry_for(sa,1).SCR));
testCase.verifyEqual(entry_for(sa,1).SCR, ((1.0/abs(Zth))*100)/100, 'RelTol', 1e-10);
testCase.verifyLessThan(entry_for(sa,1).SCR, Inf);
end

function test_rating_scaling(testCase)
% SCR is inversely proportional to the rated MVA.
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
opt = struct('scr_source_model','source_aware');
r100 = [ sg_resource('SG1',1,615,0.2), ibr_resource('IBR2',2,100,'synthetic_gfl') ];
r200 = r100; r200(2).ratings.Mbase = 200;
s100 = stability.ibr_scr_metrics(struct('mpc',mpc), r100, struct(), opt);
s200 = stability.ibr_scr_metrics(struct('mpc',mpc), r200, struct(), opt);
testCase.verifyEqual(entry_for(s200,2).SCR, entry_for(s100,2).SCR/2, 'RelTol', 1e-12);
end

function test_source_outage_raises_zth(testCase)
% Tripping one of two parallel sources must LOSE strength at the PCC.
mpc = ne39_style_mpc([1;2;3], [ ...
    1 3 0.02 0.12 0 100 100 100 0 0 1 1 1; ...
    2 3 0.03 0.08 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.25), sg_resource('SG2',2,615,0.30), ...
        ibr_resource('IBR3',3,100,'synthetic_gfl') ];
res_trip = res; res_trip(2).initial_online = false;
opt = struct('scr_source_model','source_aware');
s_all = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), opt);
s_off = stability.ibr_scr_metrics(struct('mpc',mpc), res_trip, struct(), opt);
testCase.verifyGreaterThan(entry_for(s_off,3).absZth, entry_for(s_all,3).absZth);
testCase.verifyLessThan(entry_for(s_off,3).SCR, entry_for(s_all,3).SCR);
end

function test_island_without_source_fail_closed(testCase)
% Component {1,2} has a source; component {3,4} does not.  The WHOLE Ybus of
% two disconnected, shunt-free lines is singular, yet the sourced island must
% still be solved, and the un-sourced island must fail closed on the PHYSICAL
% source check - not be certified strong because some submatrix looked fine.
mpc = ne39_style_mpc([1;2;3;4], [ ...
    1 2 0.02 0.12 0 100 100 100 0 0 1 1 1; ...
    3 4 0.02 0.12 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.25), ibr_resource('IBR2',2,100,'synthetic_gfl'), ...
        ibr_resource('IBR3',3,100,'synthetic_gfl'), ibr_resource('IBR4',4,100,'synthetic_gfl') ];
scr = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));
pr2 = entry_for(scr,2); pr3 = entry_for(scr,3); pr4 = entry_for(scr,4);
testCase.verifyEqual(pr2.status, 'valid');
testCase.verifyTrue(isfinite(pr2.SCR));
testCase.verifyEqual(pr3.status, 'no_source_island');
testCase.verifyFalse(pr3.pass);
testCase.verifyEqual(pr4.status, 'no_source_island');
testCase.verifyEqual(pr4.failure_id, 'stability:scr_source_thevenin:noSourceIsland');
testCase.verifyFalse(scr.overall_pass);
end

% =========================================================================
% Stamp re-derivation, fingerprint, contract
% =========================================================================
function test_branch_tap_shunt_stamp_independent(testCase)
% Re-derive the network Ybus by a DIFFERENT route: assemble each branch's
% 2x2 primitive in the (V_i,V_j) frame and apply the off-nominal tap as a
% diagonal congruence T = diag(1/conj(a),1), Yb = T*Yprim*T'.  This is
% algebraically distinct from the element-wise stamp in build_ybus_network.
r = 0.02; x = 0.10; b = 0.04; tap = 0.98; shift = 2.0; GS = 0.01; BS = -0.03;
mpc = ne39_style_mpc([1;2;3], [ ...
    1 2 r x b 100 100 100 tap shift 1 1 1; ...
    2 3 0.01 0.05 0.0 100 100 100 0 0 1 1 1], [1 GS BS]);
res = [ sg_resource('SG1',3,615,0.2), ibr_resource('IBR2',2,100,'synthetic_gfl') ];
scr = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));

a = tap*exp(1i*deg2rad(shift));
ys = 1/(r+1i*x);
T = diag([1/conj(a), 1]);
Yprim = [ys+1i*b/2, -ys; -ys, ys+1i*b/2];
Yb = T*Yprim*T';
Yexp = zeros(3);
Yexp([1 2],[1 2]) = Yexp([1 2],[1 2]) + Yb;
% second branch (no tap), buses 2-3
ys2 = 1/(0.01+1i*0.05);
Yexp(2,2) = Yexp(2,2)+ys2; Yexp(3,3)=Yexp(3,3)+ys2;
Yexp(2,3) = Yexp(2,3)-ys2; Yexp(3,2)=Yexp(3,2)-ys2;
% bus shunt on bus 1
Yexp(1,1) = Yexp(1,1) + (GS+1i*BS)/100;
testCase.verifyEqual(scr.Ybus, Yexp, 'AbsTol', 1e-12);
end

function test_fingerprint_invalidation(testCase)
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.2), ibr_resource('IBR2',2,100,'synthetic_gfl') ];
opt = struct('scr_source_model','source_aware');
a1 = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), opt);
a2 = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), opt);
testCase.verifyEqual(a1.fingerprint, a2.fingerprint);        % deterministic
res_trip = res; res_trip(1).initial_online = false;
b = stability.ibr_scr_metrics(struct('mpc',mpc), res_trip, struct(), opt);
testCase.verifyNotEqual(a1.fingerprint, b.fingerprint);      % status change
res_rate = res; res_rate(2).ratings.Mbase = 200;
c = stability.ibr_scr_metrics(struct('mpc',mpc), res_rate, struct(), opt);
testCase.verifyNotEqual(a1.fingerprint, c.fingerprint);      % rating change
mpc2 = mpc; mpc2.branch(1,4) = 0.20;                          % topology change
d = stability.ibr_scr_metrics(struct('mpc',mpc2), res, struct(), opt);
testCase.verifyNotEqual(a1.fingerprint, d.fingerprint);
end

function test_fingerprint_version_and_method(testCase)
% Legacy keeps the historical scr_v1 key; source-aware is scr_v2 and MUST
% differ from legacy on the SAME network (method is part of the key).
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.2), ibr_resource('IBR2',2,100,'synthetic_gfl') ];
leg = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), struct());
sa  = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));
testCase.verifyTrue(startsWith(leg.fingerprint, 'scr_v1'));
testCase.verifyTrue(startsWith(sa.fingerprint, 'scr_v2_source_aware'));
testCase.verifyNotEqual(leg.fingerprint, sa.fingerprint);
sa2 = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), ...
    struct('scr_source_model','source_aware'));
testCase.verifyEqual(sa.fingerprint, sa2.fingerprint);   % deterministic
end

function test_fingerprint_same_scr_different_sources(testCase)
% Two IDENTICAL source paths to the PCC.  Swapping the two source reactances
% between the source buses leaves the parallel Thevenin - and therefore every
% scalar SCR - unchanged, but it IS a different source configuration, so the
% fingerprint must differ.  This is the exact "same SCR, different source"
% case the cache key exists for.
mpc = ne39_style_mpc([1;2;3], [ ...
    1 3 0.02 0.12 0 100 100 100 0 0 1 1 1; ...
    2 3 0.02 0.12 0 100 100 100 0 0 1 1 1], []);
resA = [ sg_resource('SG1',1,615,0.25), sg_resource('SG2',2,615,0.35), ...
         ibr_resource('IBR3',3,100,'synthetic_gfl') ];
resB = resA;
resB(1).dynamic_params.Xdp = 0.35;
resB(2).dynamic_params.Xdp = 0.25;
opt = struct('scr_source_model','source_aware');
a = stability.ibr_scr_metrics(struct('mpc',mpc), resA, struct(), opt);
b = stability.ibr_scr_metrics(struct('mpc',mpc), resB, struct(), opt);
testCase.verifyEqual(entry_for(a,3).SCR, entry_for(b,3).SCR, 'AbsTol', 1e-12);
testCase.verifyEqual(entry_for(a,3).Zth, entry_for(b,3).Zth, 'AbsTol', 1e-12);
testCase.verifyNotEqual(a.fingerprint, b.fingerprint);
end

function test_fingerprint_topology_and_source_sensitivity(testCase)
% Direct input sensitivity of the source-aware key: rating, topology and a
% source impedance each flip it.
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.2), ibr_resource('IBR2',2,100,'synthetic_gfl') ];
opt = struct('scr_source_model','source_aware');
a = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), opt);
res_rate = res; res_rate(2).ratings.Mbase = 200;
r = stability.ibr_scr_metrics(struct('mpc',mpc), res_rate, struct(), opt);
testCase.verifyNotEqual(a.fingerprint, r.fingerprint);   % rating
mpc2 = mpc; mpc2.branch(1,4) = 0.20;
t = stability.ibr_scr_metrics(struct('mpc',mpc2), res, struct(), opt);
testCase.verifyNotEqual(a.fingerprint, t.fingerprint);   % topology
res_z = res; res_z(1).dynamic_params.Xdp = 0.30;
z = stability.ibr_scr_metrics(struct('mpc',mpc), res_z, struct(), opt);
testCase.verifyNotEqual(a.fingerprint, z.fingerprint);   % source impedance
% A shunt change (network) must also flip it even with no branch change.
mpc3 = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], [2 0.0 0.05]);
sh = stability.ibr_scr_metrics(struct('mpc',mpc3), res, struct(), opt);
testCase.verifyNotEqual(a.fingerprint, sh.fingerprint);  % shunt/topology
end

function test_method_and_scope_on_every_path(testCase)
opt = struct('scr_source_model','source_aware');
% missing mpc
s1 = stability.ibr_scr_metrics(struct(), [ibr_resource('IBR1',2,100,'synthetic_gfl')], ...
    struct(), opt);
testCase.verifyEqual(s1.method, 'source_aware');
testCase.verifyTrue(~isempty(s1.validity_scope));
% no-source island
mpc = ne39_style_mpc([1;2], [], []);
s2 = stability.ibr_scr_metrics(struct('mpc',mpc), ...
    [ibr_resource('IBR1',1,100,'synthetic_gfl'), ibr_resource('IBR2',2,100,'synthetic_gfl')], ...
    struct(), opt);
testCase.verifyEqual(s2.method, 'source_aware');
testCase.verifyTrue(~isempty(s2.validity_scope));
end

function test_bad_source_model_rejected(testCase)
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
r = [ sg_resource('SG1',1,615,0.2), ibr_resource('IBR2',2,100,'synthetic_gfl') ];
testCase.verifyError(@() stability.ibr_scr_metrics(struct('mpc',mpc), r, ...
    struct(), struct('scr_source_model','bogus')), ...
    'stability:ibr_scr_metrics:badSourceModel');
end

function test_ibr_source_impedance_optin(testCase)
% A GFM converter enters only when the caller supplies a coupling impedance.
% Adding a second finite source at the PCC must LOWER Zth at its neighbour.
mpc = ne39_style_mpc([1;2;3], [ ...
    1 3 0.02 0.12 0 100 100 100 0 0 1 1 1; ...
    2 3 0.03 0.08 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.25), ...
        ibr_resource('GFM2',2,100,'eecon49_dual'), ...
        ibr_resource('GFL3',3,100,'eecon49_dual') ];
res(2).initial_mode = 'gfm';
base = struct('scr_source_model','source_aware');
s_off = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), base);
optz = base; optz.ibr_source_impedance = struct('eecon49_dual', 0.015+1i*0.15);
s_on = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), optz);
testCase.verifyLessThan(entry_for(s_on,3).absZth, entry_for(s_off,3).absZth);
testCase.verifyGreaterThan(entry_for(s_on,3).SCR, entry_for(s_off,3).SCR);
% the opt-in shows up in the source list
kinds = arrayfun(@(e) string(e.kind), s_on.source_list);
testCase.verifyTrue(any(kinds=="gfm_ibr"));
testCase.verifyFalse(any(arrayfun(@(e) string(e.kind), s_off.source_list)=="gfm_ibr"));
end

function test_legacy_default_unchanged(testCase)
% Absent opt.scr_source_model -> legacy slack-grounded behaviour and profile.
mpc = ne39_style_mpc([1;2], [1 2 0.01 0.10 0 100 100 100 0 0 1 1 1], []);
res = [ sg_resource('SG1',1,615,0.2), ibr_resource('IBR2',2,100,'eecon49_dual') ];
scr = stability.ibr_scr_metrics(struct('mpc',mpc), res, struct(), struct());
testCase.verifyEqual(scr.method, 'legacy_slack_grounding');
pr = entry_for(scr, 2);
testCase.verifyEqual(pr.scr_profile, 'not_applicable_full_state_source_model');
testCase.verifyFalse(pr.eligible_for_scr);
testCase.verifyTrue(pr.pass);
end

function test_no_inv_pinv(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
for f = {'ibr_scr_metrics.m','scr_source_thevenin.m'}
    src = fileread(fullfile(root, '+stability', f{1}));
    testCase.verifyFalse(~isempty(regexp(src,'(^|\W)inv\s*\(','once')), ...
        sprintf('No inv( in %s', f{1}));
    testCase.verifyFalse(~isempty(regexp(src,'(^|\W)pinv\s*\(','once')), ...
        sprintf('No pinv( in %s', f{1}));
end
end

% =========================================================================
% Real NE39 case: 5 SG + 5 IBR, Xdp read from case_data.machines.units
% =========================================================================
function test_ne39_source_aware_uses_machines_units(testCase)
% No opt.sg_sources and no dynamic_params.Xdp on the resources: the SG Xdp
% must come from case_data.machines.units (system base).  5 SG at 31,32,35,38,
% 39 and 5 IBR at 30,33,34,36,37.
c = cases.case_ne39();
sg_buses = [31 32 35 38 39];
ibr_buses = [30 33 34 36 37];
res = repmat(ibr_resource('x',1,100,'eecon49_dual'), 0, 1);
for b = sg_buses
    res(end+1) = sg_resource(sprintf('SG%d',b), b, 615, NaN); %#ok<AGROW>
end
for b = ibr_buses
    res(end+1) = ibr_resource(sprintf('IBR%d',b), b, 100, 'eecon49_dual'); %#ok<AGROW>
end
scr = stability.ibr_scr_metrics(c, res, struct(), ...
    struct('scr_source_model','source_aware'));
testCase.verifyEqual(scr.method, 'source_aware');
testCase.verifyGreaterThan(scr.n_sources_online, 0);
for b = ibr_buses
    pr = entry_for(scr, b);
    testCase.verifyEqual(pr.status, 'valid', sprintf('bus %d', b));
    testCase.verifyTrue(isfinite(pr.SCR), sprintf('bus %d SCR finite', b));
    testCase.verifyGreaterThan(pr.SCR, 0);
    testCase.verifyTrue(pr.source_available);
    testCase.verifyFalse(pr.threshold_applicable);   % eecon49_dual family
    testCase.verifyTrue(pr.pass);                    % measured, not gated
end

% Trip every SG -> the (single) island has no online source -> fail closed.
res_off = res;
for k = 1:numel(res_off)
    if strcmpi(char(res_off(k).resource_type),'sg')
        res_off(k).initial_online = false;
    end
end
scr_off = stability.ibr_scr_metrics(c, res_off, struct(), ...
    struct('scr_source_model','source_aware'));
for b = ibr_buses
    pr = entry_for(scr_off, b);
    testCase.verifyEqual(pr.status, 'no_source_island', sprintf('bus %d', b));
    testCase.verifyFalse(pr.pass);
end
testCase.verifyFalse(scr_off.overall_pass);
end

% =========================================================================
% Helpers
% =========================================================================
function pr = entry_for(scr, bus_id)
pr = [];
for k = 1:numel(scr.per_resource)
    if scr.per_resource(k).bus_id == bus_id
        pr = scr.per_resource(k);
        return;
    end
end
% Fall back: a bus may carry more than one resource; prefer the IBR entry.
for k = 1:numel(scr.per_resource)
    if scr.per_resource(k).bus_id == bus_id && scr.per_resource(k).eligible_for_scr
        pr = scr.per_resource(k);
        return;
    end
end
end

function mpc = ne39_style_mpc(bus_ids, branch_rows, shunt_rows)
nb = numel(bus_ids);
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = zeros(nb, 13);
for k = 1:nb
    mpc.bus(k,1) = bus_ids(k);
    mpc.bus(k,2) = 1;         % PQ by default; tests set slack explicitly
    mpc.bus(k,8) = 1.0;       % Vm = 1.0
end
mpc.bus(1,2) = 3;             % bus 1 defaults to slack (legacy grounding point)
if nargin >= 2 && ~isempty(branch_rows)
    mpc.branch = branch_rows;
else
    mpc.branch = zeros(0,13);
end
if nargin >= 3 && ~isempty(shunt_rows)
    for k = 1:size(shunt_rows,1)
        bb = find(bus_ids==shunt_rows(k,1),1);
        mpc.bus(bb,5) = shunt_rows(k,2);   % GS (MW)
        mpc.bus(bb,6) = shunt_rows(k,3);   % BS (MVAr)
    end
end
mpc.gen = [bus_ids(1) 0 0 10 -10 1.06 100 1 100 0 0 0 0 0 0 0 0 0 0 0 0];
end

function r = sg_resource(id, bus, mbase, xdp)
r = base_resource(id, bus, 'sg', 'sg_classical', mbase);
r.initial_mode = 'synchronous';
r.supported_modes = {'synchronous','breaker_open'};
if nargin >= 4 && isscalar(xdp) && isfinite(xdp) && xdp > 0
    r.dynamic_params = struct('Xdp', xdp);
else
    r.dynamic_params = struct();
end
end

function r = ibr_resource(id, bus, mbase, model_id)
r = base_resource(id, bus, 'ibr', model_id, mbase);
r.initial_mode = 'gfl';
r.supported_modes = {'gfl','gfm','tripped'};
r.dynamic_params = struct('Mbase', mbase);
end

function r = base_resource(id, bus, rtype, model_id, mbase)
r = struct('resource_id', id, 'bus_id', bus, 'resource_type', rtype, ...
    'model_id', model_id, 'supported_modes', {{}}, 'voltage_forming_modes', {{}}, ...
    'initial_mode', '', 'initial_online', true, 'can_switch_mode', true, ...
    'can_switch_online', true, 'has_current_limiter', false, 'has_frt', false, ...
    'can_black_start', false, 'limits', struct(), ...
    'ratings', struct('Mbase', mbase, 'Sbase', mbase), ...
    'dynamic_params', struct(), ...
    'provenance', struct('model','test','source','test fixture', ...
        'classification','CASE_DEFINED','details','test'));
end
