function tests = test_ne39_dynamics_sensitivity
%TEST_NE39_DYNAMICS_SENSITIVITY  H-sensitivity of the derived NE39 dynamics.
%
%   The 10 machines of cases.case_ne39 carry PROJECT_DERIVED inertia: H is the
%   published IEEE RTS-1996 Table 15 row of the machine's CLASS, scaled by the
%   machine's own Pg (cases.ne39_machine_parameters carries the derivation and
%   the class mapping).  The class mapping is the only step of that derivation
%   that is not arithmetic, so a stability claim on this case is licensed ONLY
%   together with this test: the classical SSSA is re-run with H scaled on
%   EVERY machine and the reported conclusion is checked for invariance.
%
%   SCALES, AND WHY THESE ONES.  H is scaled by {0.5, 1.0, 2.0} on every
%   machine -- a 4x span, because the ENTIRE spread of published Table 15
%   inertia constants is only 2.8 s (U12/U20/U100/U197) to 5.0 s (U400), a
%   5.0/2.8 = 1.79x span.  The three rows this case's mapping actually uses are
%   narrower still: 3.0 s (U350), 3.5 s (U50), 5.0 s (U400), a 5.0/3.0 = 1.67x
%   span.  So the declared band strictly contains the worst case of the class
%   mapping having chosen a different published row, even if it did so for
%   every machine at once.  It does NOT cover a re-mapping that also changes
%   X'd, and it does not cover D ~= 0.
%
%   WHAT IS ASSERTED, AND THE TOLERANCES -- ALL DECLARED BEFORE ANY RESULT.
%     (a) Verdict invariance.  multicase_sssa's own result.stability_status
%         must be IDENTICAL at every scale.
%     (b) No damping may appear from the scaling.  Table 15 publishes D = 0.0
%         for every unit group and the project carries it as published, so the
%         classical state matrix carries no damping term at all and every mode
%         is oscillatory with Re(lambda) = 0 to within eigensolver round-off.
%         'zeta_roundoff_band = 1e-9' declares a mode effectively undamped when
%         |zeta| <= 1e-9: six orders above the double-precision round-off
%         measured on this 20x20 matrix, and far below any physical damping
%         claim (the repo's own acceptance floor is zeta_min = 0.05,
%         +cases/case_ieee14_1sg_4ibr_auto_vsg.m:169).  Minimum zeta must stay
%         inside +-band at EVERY scale.
%     (c) Below-floor count invariance.  'zeta_floor = 0.05', the same repo
%         convention.  The number of reduced modes below the floor must be
%         identical at every scale -- and, because D = 0, equal to the whole
%         reduced set.  A count that moved would mean the H scaling had
%         manufactured or destroyed damping, which is the failure this test
%         exists to catch.
%     (d) Real-part sign invariance.  Every mode's real part must stay inside
%         the round-off band at every scale, i.e. no scale may produce a mode
%         whose sign is decided by anything other than round-off.  With D = 0
%         the eigenvalues of the classical A matrix are either purely imaginary
%         or a real +- pair; a real pair puts |Re| far outside the band and
%         FAILS here, which is the correct outcome for a genuinely unstable
%         mode.
%     (e) Frequency law -- the quantitative spread.  Scaling H by s scales the
%         synchronising torque by 1/s, so every mode frequency must obey
%         f(s) = f(1)/sqrt(s).  'freq_law_rel_tol = 1e-6' is declared from the
%         analytic law, not from a measurement.  The spread is printed so a
%         reader sees how far the answer actually moves: over this sweep the
%         mode frequencies run 0.5368..2.4620 Hz against a nominal
%         0.7591..1.7409 Hz, i.e. +41.4 % at the 0.5x edge and -29.3 % at the
%         2.0x edge -- the honest size of the uncertainty a report must quote
%         alongside any mode frequency from this case.
%
%   THE TEST CHECKS ITS OWN FALSIFIABILITY.  test_the_invariant_check_can_fail
%   runs the SAME checker on a deliberately poisoned run (one machine given
%   D = 20 at one scale) and asserts it reports violations.  A guard that
%   cannot fail is not a guard.
%
%   THE ROUTE IS THE CLASSICAL ONE.  +stability/multicase_sssa.m:52-63 gates
%   its EMF6 branch on isfield(case_data.machines,'reactances').  This case has
%   no such field (the double-conversion trap, +stability/ts_simulate.m:462-476),
%   so 'classical' is what runs and the 20-state classical model is what is
%   being sensitised here.  That is asserted, not assumed.
%
%   See also cases.ne39_machine_parameters, cases.case_ne39, tests.test_ne39_case.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function test_damping_conclusion_is_invariant_under_h_scaling(testCase)
% The headline contract.  Runs the classical SSSA at every declared scale and
% requires the invariant checker to come back empty -- i.e. the verdict, the
% absence of damping, the below-floor mode count and the real-part signs are
% all unchanged by a factor-of-two move in every machine's inertia.
cfg = sens_config();
c0 = cases.case_ne39();
testCase.verifyTrue(isfield(c0, 'machines'), ...
    'This test sensitises the derived machine data; the case must carry it.');

rows = repmat(run_scaled(c0, cfg.scales(1), cfg), 1, numel(cfg.scales));
for i = 1:numel(cfg.scales)
    rows(i) = run_scaled(c0, cfg.scales(i), cfg);
    fprintf(['[sensitivity] H x%.2f: states=%d reduced=%d verdict=%s ' ...
        'min_zeta=%+.3e max|Re|(full)=%.3e below_floor(%g)=%d/%d ' ...
        'freq=%.4f..%.4f Hz\n'], ...
        rows(i).factor, rows(i).n_states, rows(i).n_reduced, rows(i).status, ...
        rows(i).min_zeta, rows(i).max_abs_real_full, cfg.zeta_floor, ...
        rows(i).n_below_floor, rows(i).n_reduced, ...
        min(rows(i).freq_below_floor), max(rows(i).freq_below_floor));
end

v = invariant_violations(rows, cfg);
testCase.verifyEmpty(v, ['The derived NE39 dynamics do not support a scaling-' ...
    'invariant conclusion. Violations: ' strjoin(v, ' | ')]);

% The spread the reader is entitled to see, stated as a number.  f_all is
% 18x3 (one column per scale), so the extremes are taken over all elements --
% min() alone would return a 1x3 row and consume the format slots one by one.
z = [rows.min_zeta];
f_all = [rows.freq_below_floor];
f0 = rows([rows.factor] == 1).freq_below_floor;
move_lo = 100*(sqrt(1/min(cfg.scales)) - 1);   % +41.4 % at x0.5
move_hi = 100*(sqrt(1/max(cfg.scales)) - 1);   % -29.3 % at x2.0
fprintf(['[sensitivity] SPREAD over H x0.5..x2.0: min_zeta %.3e..%.3e ' ...
    '(spread %.3e, round-off band %.0e); nominal mode band %.4f..%.4f Hz; ' ...
    'over the whole sweep %.4f..%.4f Hz; by the analytic law every mode ' ...
    'frequency moves %+.1f %% at x0.5 and %+.1f %% at x2.0.\n'], ...
    min(z), max(z), max(z) - min(z), cfg.zeta_roundoff_band, ...
    min(f0), max(f0), min(f_all(:)), max(f_all(:)), move_lo, move_hi);

% The conclusion that may be quoted, in the words it may be quoted in.
testCase.verifyEqual(rows(1).status, 'MARGINAL', ...
    ['With D = 0 as published the case has no damping at any scale, so the ' ...
     'honest verdict is MARGINAL (undamped), never "stable".']);
end

% =========================================================================
function test_the_scaling_actually_reached_the_model(testCase)
% A sensitivity test whose lever silently did nothing passes everything.  The
% H vector must differ at every scale, X'd must NOT move (this test sensitises
% inertia only), and the mode frequencies must follow the analytic law -- which
% they cannot do if the scaling never reached ts_simulate.
cfg = sens_config();
c0 = cases.case_ne39();
r05 = run_scaled(c0, 0.5, cfg);
r10 = run_scaled(c0, 1.0, cfg);
r20 = run_scaled(c0, 2.0, cfg);

% Element-wise, not min/max across the set: the ten derived H values span
% 8.75..50 s, so the SCALED SETS interleave even though each machine's own H
% moves strictly.  Comparing set extremes would be a test of the table's spread,
% not of the scaling.
testCase.verifyTrue(all(r05.units_H < r10.units_H), ...
    'x0.5 H must be strictly below x1.0 H on every machine.');
testCase.verifyTrue(all(r20.units_H > r10.units_H), ...
    'x2.0 H must be strictly above x1.0 H on every machine.');
testCase.verifyEqual(r05.units_Xdp, r10.units_Xdp, 'AbsTol', 0, ...
    'The sensitivity is on inertia; X''d must not move with it.');

% Frequencies rise as H falls, and they do so MODE BY MODE: uniform scaling
% cannot reorder the spectrum, so the sorted below-floor sets must compare
% element-wise against the analytic f(s) = f(1)/sqrt(s).  Measured deviation
% from that law is 1.9e-15, so the strict inequalities below are safe.
testCase.verifyTrue(all(r05.freq_below_floor > r10.freq_below_floor), ...
    'Halving H must raise every mode frequency above its nominal value.');
testCase.verifyTrue(all(r20.freq_below_floor < r10.freq_below_floor), ...
    'Doubling H must lower every mode frequency below its nominal value.');
end

% =========================================================================
function test_the_route_is_classical_and_the_emf6_trap_is_not_triggered(testCase)
% +stability/multicase_sssa.m:52-63 gates the EMF6 branch on
% isfield(case_data.machines,'reactances'), and +stability/ts_simulate.m:462-476
% would then scale H and D a SECOND time and hand all ten machines one shared
% X'd.  This case supplies .base and .units and NO .reactances, so classical is
% the model under test.  If that ever changed, the sensitivity above would be
% sensitising the wrong model -- so it is asserted here.
c = cases.case_ne39();
testCase.verifyFalse(isfield(c.machines, 'reactances'), ...
    ['machines must NOT carry .reactances: ts_simulate.m:462-476 would scale ' ...
     'H and D a second time and give all 10 machines one shared Xdp.']);

s = stability.multicase_sssa(c, struct('model', 'classical'));
testCase.verifyEqual(s.metadata.plugin, 'classical_network_linearization');
testCase.verifyEqual(numel(s.eigenvalues), 20, ...
    '10 machines x 2 classical states (delta, omega).');
testCase.verifyEqual(numel(s.reduced_eigenvalues), 18, ...
    'COI reduction removes the two global angle/speed modes.');

% One shared X'd would mean the trap had fired.  The derived table has one
% value per RTS class, so three distinct values for these ten machines.
xdp = unique([c.machines.units.Xdp]);
testCase.verifyEqual(numel(xdp), 3, ...
    ['Ten machines with per-machine X''d must show one value per RTS class ' ...
     '(U50, U350, U400). A single value would mean a shared reactance.']);
testCase.verifyFalse(any(abs(xdp - 0.3) < 1e-12), ...
    'X''d must not be the project classical default 0.3 pu.');

% Requesting emf6 must still fall through to classical: pre-existing behaviour
% for every case without a .reactances field, pinned here so it stays visible.
s6 = stability.multicase_sssa(c, struct('model', 'emf6'));
testCase.verifyEqual(s6.metadata.plugin, 'classical_network_linearization');
end

% =========================================================================
function test_the_invariant_check_can_fail(testCase)
% The guard's own falsification test.  A clean run must pass the checker and a
% run carrying damping the published table does not have must fail it, on the
% minimum-damping invariant specifically.  Without this, test 1 could be an
% assertion that is incapable of firing.
cfg = sens_config();
c0 = cases.case_ne39();
clean = run_scaled(c0, 1.0, cfg);
testCase.verifyEmpty(invariant_violations(clean, cfg), ...
    'A single clean scale must satisfy the invariants.');

poisoned = run_scaled_damped(c0, 2.0, 1, 20.0, cfg);
testCase.verifyGreaterThan(abs(poisoned.min_zeta), cfg.zeta_roundoff_band, ...
    'The poison must actually damp a mode, or this self-check proves nothing.');

v = invariant_violations([clean poisoned], cfg);
testCase.verifyNotEmpty(v, 'The checker must reject a run with manufactured damping.');
testCase.verifyTrue(any(startsWith(v, '(b)')), ...
    ['The minimum-damping invariant must be among the violations reported; got: ' ...
     strjoin(v, ' | ')]);
end

% =========================================================================
% Local helpers
% =========================================================================
function cfg = sens_config()
%SENS_CONFIG  The declared scales, floor and tolerances.  See the file header.
cfg = struct();
cfg.scales = [0.5 1.0 2.0];        % factor-of-two band, wider than the RTS H span
cfg.zeta_floor = 0.05;             % repo acceptance floor (+cases/case_ieee14_1sg_4ibr_auto_vsg.m:169)
cfg.zeta_roundoff_band = 1e-9;     % |zeta| <= band means "undamped to round-off"
cfg.freq_law_rel_tol = 1e-6;       % analytic f(s) = f(1)/sqrt(s), declared a priori
end

function r = run_scaled(c0, factor, cfg)
%RUN_SCALED  Classical SSSA with every machine's derived H multiplied by factor.
c = c0;
for k = 1:numel(c.machines.units)
    c.machines.units(k).H = c.machines.units(k).H * factor;
end
r = summarise(stability.multicase_sssa(c, struct('model', 'classical')), factor, c, cfg);
end

function r = run_scaled_damped(c0, factor, machine_idx, damp, cfg)
%RUN_SCALED_DAMPED  As RUN_SCALED, plus damping the published table does not
%   have on one machine.  Used only by the checker's own falsification test.
c = c0;
for k = 1:numel(c.machines.units)
    c.machines.units(k).H = c.machines.units(k).H * factor;
end
c.machines.units(machine_idx).D = damp;
r = summarise(stability.multicase_sssa(c, struct('model', 'classical')), factor, c, cfg);
end

function r = summarise(s, factor, c, cfg)
%SUMMARISE  The quantities the invariants are stated on, from one SSSA result.
lam_full = s.eigenvalues(:);
lam = s.reduced_eigenvalues(:);
r = struct();
r.factor = factor;
r.n_states = numel(lam_full);
r.n_reduced = numel(lam);
r.status = s.stability_status;
r.plugin = s.metadata.plugin;
r.dynamic_data_source = s.metadata.dynamic_data_source;
r.max_abs_real_full = max(abs(real(lam_full)));
r.zeta = -real(lam)./(abs(lam)+eps);
r.freq = abs(imag(lam))/(2*pi);
r.min_zeta = min(r.zeta);
r.max_zeta = max(r.zeta);
r.n_below_floor = sum(r.zeta < cfg.zeta_floor);
r.sign_partition = [sum(real(lam) > cfg.zeta_roundoff_band), ...
                    sum(real(lam) < -cfg.zeta_roundoff_band), ...
                    sum(abs(real(lam)) <= cfg.zeta_roundoff_band)];
r.freq_below_floor = sort(r.freq(r.zeta < cfg.zeta_floor));
r.units_H = [c.machines.units.H];
r.units_Xdp = [c.machines.units.Xdp];
end

function v = invariant_violations(rows, cfg)
%INVARIANT_VIOLATIONS  Empty when the scaling-invariance conclusion holds.
%   (a) verdict, (b) minimum damping ratio, (c) below-floor count, (d) real-part
%   signs, (e) the analytic frequency law.  One message per violation.  The cell
%   is preallocated to a fixed bound: at most one message per check, plus one per
%   scale for (b) and one per scale for (e).
v = cell(4 + 2*numel(rows), 1);
nv = 0;

statuses = unique({rows.status});
if numel(statuses) ~= 1
    nv = nv + 1;
    v{nv} = sprintf('(a) verdict not invariant across H scales: %s', ...
        strjoin(statuses, ' | '));
end

for i = 1:numel(rows)
    if ~(abs(rows(i).min_zeta) <= cfg.zeta_roundoff_band)
        nv = nv + 1;
        v{nv} = sprintf(['(b) H scale %.2fx gives min zeta = %+.6e, outside the ' ...
            'declared round-off band +-%.0e: the H scaling changed the damping ' ...
            'conclusion.'], rows(i).factor, rows(i).min_zeta, cfg.zeta_roundoff_band);
    end
end

counts = [rows.n_below_floor];
if numel(unique(counts)) ~= 1
    nv = nv + 1;
    v{nv} = sprintf('(c) modes below zeta = %.2f are not invariant across scales: %s', ...
        cfg.zeta_floor, mat2str(counts));
elseif counts(1) ~= rows(1).n_reduced
    nv = nv + 1;
    v{nv} = sprintf(['(c) only %d of %d reduced modes sit below zeta = %.2f, but D = 0 ' ...
        'as published leaves no mode damped.'], counts(1), rows(1).n_reduced, cfg.zeta_floor);
end

% [rows.sign_partition] concatenates each scale's 3-vector, and reshape fills
% column-wise, so the result is 3 counters x N scales -- rows are counters,
% columns are scales.  Do NOT transpose: that is what the first draft did, and
% it made a clean single-scale run look like a violated invariant.
sig = reshape([rows.sign_partition], 3, []);
if any(sig(1, :) ~= sig(1, 1)) || any(sig(2, :) ~= sig(2, 1)) || any(sig(3, :) ~= sig(3, 1))
    nv = nv + 1;
    v{nv} = sprintf('(d) real-part sign partition not invariant across scales: %s', ...
        mat2str(sig));
elseif sig(1, 1) ~= 0 || sig(2, 1) ~= 0
    nv = nv + 1;
    v{nv} = sprintf(['(d) %d modes have Re(lambda) > +%.0e and %d have Re(lambda) < ' ...
        '-%.0e: with D = 0 as published every classical mode must be oscillatory with ' ...
        'zero real part to round-off.'], ...
        sig(1, 1), cfg.zeta_roundoff_band, sig(2, 1), cfg.zeta_roundoff_band);
end

ref = find([rows.factor] == 1, 1);
if isempty(ref)
    nv = nv + 1;
    v{nv} = '(e) no unit H scale present; the frequency law cannot be checked.';
else
    f0 = rows(ref).freq_below_floor;
    for i = 1:numel(rows)
        if i == ref, continue; end
        fi = rows(i).freq_below_floor;
        if numel(fi) ~= numel(f0)
            nv = nv + 1;
            v{nv} = sprintf(['(e) H scale %.2fx has %d below-floor modes against %d at ' ...
                '1.0x.'], rows(i).factor, numel(fi), numel(f0));
            continue;
        end
        pred = f0 / sqrt(rows(i).factor);
        dev = max(abs(fi - pred) ./ max(pred, eps));
        if dev > cfg.freq_law_rel_tol
            nv = nv + 1;
            v{nv} = sprintf(['(e) H scale %.2fx deviates from the analytic law ' ...
                'f(s) = f(1)/sqrt(s) by %.3e (declared tolerance %.0e).'], ...
                rows(i).factor, dev, cfg.freq_law_rel_tol);
        end
    end
end
v = v(1:nv);
end
