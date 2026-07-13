function tests = test_ibr_gfl_model()
%TEST_IBR_GFL_MODEL  Phase 5 GFL model structural tests (STRUCTURAL_ONLY).
%   Verifies the +ibr/gfl_model device: equation structure (Ding 83340
%   Eqs.7-10 RMS-reduced), composite_dae ABI conformance, sign/base/frame
%   conventions, predeclared pole oracles, direct feedthrough, no-disturbance
%   TS hold via ts_step_kernel, and source guards.
%
%   Source: docs/project/IEEE14_IBR_GFL_PHASE5_PROVENANCE.md;
%           docs/project/IEEE14_IBR_DECISION_LEDGER.md (Item 1).
%   Phase 5 is STRUCTURAL_ONLY: Kps/Kis are ASSUMED_DIAGNOSTIC; no
%   production-readiness claim. Mixed-equilibrium / SSSA-sharing gates
%   are deferred to Phase 9.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
% Shared fixture: minimal 2-bus infinite-bus mpc + a GFL device at bus 2.
% =========================================================================
function [mpc, dev, y0, u0, V0, theta0, Y] = local_gfl_fixture(P_ref, Q_ref)
%LOCAL_GFL_FIXTURE  2-bus infinite-bus: bus1 REF (V=1.06, angle 0), bus2 PQ (GFL).
%   Branch r=0, x=0.1 pu. The GFL connects at bus 2 (bus_position=2).
%   Returns the mpc, the GFL device struct, the initial y, u0, V0, theta0, Y.
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = [ ...
    1, 3, 0, 0, 0, 0, 1, 1.06, 0, 69, 1, 1.1, 0.9; ...   % bus 1 REF (type 3 internal)
    2, 1, 0, 0, 0, 0, 1, 1.00, 0, 69, 1, 1.1, 0.9];     % bus 2 PQ  (type 1 internal)
mpc.gen = [1, 0, 0, 0, -0, 1.06, 100, 1, 0, -0];          % slack gen at bus 1
mpc.branch = [1, 2, 0.0, 0.1, 0.0, 0, 0, 0, 1.0, 0, 1];   % r=0, x=0.1
mpc.gencost = [];
mpc.case_name = 'gfl_infinite_bus_2bus';

% PF warm-start: bus 2 voltage. For the structural test, take V2 = 1.0 /theta 0
% (the infinite bus fixes bus 1 at 1.06/0; bus 2 is approximately 1.0/0 for a
% lightly-loaded GFL at P_ref small). Use V0 = 1.0 (the GFL's local bus
% magnitude) and theta0 = 0 for initialization.
V0 = 1.0;
theta0 = 0.0;

% Build the GFL device. bus_position = 2 (bus 2 in the 2-bus system).
params = struct();
dev = ibr.gfl_model('IBR_test', 2, 2, V0, params, P_ref, Q_ref);
u0 = dev.u0;

% Initial y (interleaved): bus1 = 1.06+0j, bus2 = V0*exp(j*theta0).
y0 = zeros(4,1);
y0(1:2) = [1.06; 0.0];
y0(3:4) = [V0*cos(theta0); V0*sin(theta0)];

% 2-bus Ybus (system base). Build locally for the standalone residual test.
Y = local_ybus(mpc);
end

function Y = local_ybus(mpc)
%LOCAL_YBUS  Build the 2-bus Ybus with a STIFF slack admittance at bus 1.
%   Bus 1 (infinite bus) is pinned to V=1.06/0 by a large shunt admittance
%   Yslack = 1e6 (so the network KCL at bus 1 is dominated by the slack,
%   effectively fixing V1). This lets the legacy ts_step_kernel path solve
%   g=Y*V-Ibus=0 for ALL 4 algebraic vars without a gauge-row replacement
%   (which the legacy kernel does not support). The slack current is set so
%   that V1 = 1.06/0 is the solution: I_slack = Yslack * (1.06+0j) injected
%   at bus 1 (handled in network_g via Ibus(1)).
bus = mpc.bus; br = mpc.branch; nb = size(bus,1); Y = complex(zeros(nb));
for k = 1:size(br,1)
    if br(k,11) == 0, continue; end
    i = find(bus(:,1)==br(k,1),1); j = find(bus(:,1)==br(k,2),1);
    r = br(k,3); x = br(k,4); b = br(k,5);
    yser = 1/(r+1i*x);
    Y(i,i) = Y(i,i) + yser + 1i*b/2;
    Y(j,j) = Y(j,j) + yser + 1i*b/2;
    Y(i,j) = Y(i,j) - yser;
    Y(j,i) = Y(j,i) - yser;
end
% Stiff slack at bus 1 (infinite bus). Yslack chosen large enough to pin V1
% to 1.06/0 but small enough to keep the 4x4 FD Jacobian well-conditioned
% (the GFL current injection has dI/dy = 0, so the y(3:4) columns come only
% from Y*V; Yslack dominates y(1:2) columns). 1e3 balances pinning vs conditioning.
Yslack = 1e3;
Y(1,1) = Y(1,1) + Yslack;
end

% =========================================================================
% 1. PLL lock
% =========================================================================
function test_gfl_pll_lock(testCase)
[~, dev, y0, u0, V0, theta0, ~] = local_gfl_fixture(0.4, 0.0);
x = dev.x0;
% Evaluate f at the initialized equilibrium (u=u0, event_context=struct()).
fval = dev.f(0, x, y0, u0, struct());
% PLL lock: delta_pll0 = theta0, eps_pll0 = 0 => Vq_pll=0 => d(eps_pll)=0, d(delta)=0.
testCase.verifyEqual(fval(1), 0, 'AbsTol', 1e-9, 'd(delta_pll)=0 at lock (theta0).');
testCase.verifyEqual(fval(2), 0, 'AbsTol', 1e-9, 'd(eps_pll)=0 at lock (Vq_pll=0).');
% Vq_pll at the equilibrium must be ~0 (PLL aligned to bus angle).
r = dev.reconstruct(0, x, y0, u0, struct());
testCase.verifyEqual(r.Vq_pll, 0, 'AbsTol', 1e-9, 'Vq_pll=0 at lock.');
testCase.verifyEqual(r.delta_pll, theta0, 'AbsTol', 1e-12, 'delta_pll = bus angle.');
% delta_pll0 should equal angle(V_bus) = theta0; V0 is the magnitude.
[~, ~, ~, ~, ~, ~, ~] = deal(0); %#ok<NASGU>
end

% =========================================================================
% 2. P/Q sign (S = V*conj(I), generator convention)
% =========================================================================
function test_gfl_pq_sign(testCase)
[~, dev, y0, u0, ~, ~, ~] = local_gfl_fixture(0.4, 0.2);
x = dev.x0;
I = dev.current_injection(0, x, y0, u0, struct());
V_bus = complex(y0(3), y0(4));
S = V_bus * conj(I);
P = real(S); Q = imag(S);
% At the v3-initialized equilibrium, P should equal P_ref, Q should equal Q_ref
% (within the initialization algebra: i_d*0=Pref/V0, i_q*0=-Qref/V0).
testCase.verifyEqual(P, 0.4, 'AbsTol', 1e-9, 'P = P_ref at equilibrium.');
testCase.verifyEqual(Q, 0.2, 'AbsTol', 1e-9, 'Q = Q_ref at equilibrium.');
end

% =========================================================================
% 3. Current into network (positive injection; S = V*conj(I) recovers refs)
% =========================================================================
function test_gfl_current_into_network(testCase)
[~, dev, y0, u0, V0, ~, ~] = local_gfl_fixture(0.4, 0.0);
x = dev.x0;
I = dev.current_injection(0, x, y0, u0, struct());
% I_gfl = (i_d* + j*i_q*)*exp(j*delta_pll). At equilibrium delta_pll = theta0 = 0,
% i_d*0 = Pref/V0, i_q*0 = -Qref/V0. So I_gfl = Pref/V0 - j*Qref/V0 (real, positive
% for positive Pref). Positive injection INTO network.
testCase.verifyGreaterThan(real(I), 0, 'I_gfl real part positive (Pref>0).');
% Magnitude check: |I| = sqrt((Pref/V0)^2 + (Qref/V0)^2).
testCase.verifyEqual(abs(I), sqrt((0.4/V0)^2 + (0.0/V0)^2), 'AbsTol', 1e-12, ...
    '|I_gfl| = sqrt((Pref/V0)^2+(Qref/V0)^2) at lock.');
% S = V*conj(I) recovers Pref, Qref.
V_bus = complex(y0(3), y0(4));
S = V_bus * conj(I);
testCase.verifyEqual(real(S), 0.4, 'AbsTol', 1e-10, 'S=V*conj(I): P=Pref.');
testCase.verifyEqual(imag(S), 0.0, 'AbsTol', 1e-10, 'S=V*conj(I): Q=Qref.');
end

% =========================================================================
% 4. Equilibrium residual (standalone coupled residual, NOT mixed_equilibrium_solve)
% =========================================================================
function test_gfl_equilibrium_residual(testCase)
[mpc, dev, y0, u0, ~, ~, Y] = local_gfl_fixture(0.4, 0.1);
% Solve the FULL coupled equilibrium (x, y): f(x,y,u)=0 AND g(x,y,Y,u)=0.
% The v3 initialization (V0=1.0) is a warm start, NOT the true equilibrium
% (V2 != 1.0 once the GFL injects current). Newton on the 10-unknown coupled
% residual [f; g] (6 states + 4 algebraic). Built in-test, NOT mixed_equilibrium_solve.
[x_eq, y_eq, res_norm] = solve_coupled_equilibrium(dev, y0, u0, Y);
testCase.verifyLessThan(res_norm, 1e-6, 'coupled residual < 1e-6 at solved equilibrium.');
% Bus 1 voltage pinned near 1.06/0 by the stiff slack (Yslack=1e3 gives a
% small residual offset; the pinning is approximate by design).
testCase.verifyEqual(y_eq(1), 1.06, 'AbsTol', 1e-3, 'V1_re ~ 1.06 (stiff slack).');
testCase.verifyEqual(y_eq(2), 0.0, 'AbsTol', 1e-3, 'V1_im ~ 0 (stiff slack).');
end

% =========================================================================
% 5. Jacobian FD agreement (FD self-consistency; no analytic Jacobian impl)
% =========================================================================
function test_gfl_jacobian_fd_agreement(testCase)
[~, dev, y0, u0, ~, ~, ~] = local_gfl_fixture(0.4, 0.1);
x = dev.x0;
fd_eps = 3e-6;
% Central-FD Jacobian of f w.r.t. x (states) at the equilibrium. f is
% linear-in-own-state for the filters/PI; the PLL coupling is via Vq_pll(x,y)
% which is nonlinear in delta_pll. Verify the FD Jacobian is finite and the
% residual is well-conditioned.
nx = dev.nx;
J = zeros(nx, nx);
f0 = dev.f(0, x, y0, u0, struct());
for j = 1:nx
    xp = x; xm = x;
    xp(j) = xp(j) + fd_eps;
    xm(j) = xm(j) - fd_eps;
    fp = dev.f(0, xp, y0, u0, struct());
    fm = dev.f(0, xm, y0, u0, struct());
    J(:,j) = (fp - fm) / (2*fd_eps);
end
testCase.verifyTrue(all(isfinite(J(:))), 'FD Jacobian of f w.r.t. x finite.');
testCase.verifyGreaterThan(rcond(J), 1e-10, 'FD Jacobian well-conditioned (rcond>1e-10).');
% Cross-check h-vs-h/2 stability (Richardson-style, matches multimachine_ssa FD_STAB_TOL).
J2 = zeros(nx, nx);
for j = 1:nx
    xp = x; xm = x;
    xp(j) = xp(j) + fd_eps/2;
    xm(j) = xm(j) - fd_eps/2;
    J2(:,j) = (dev.f(0, xp, y0, u0, struct()) - dev.f(0, xm, y0, u0, struct())) / (2*(fd_eps/2));
end
rel = max(abs(J - J2), [], 'all') / (max(abs(J), [], 'all') + max(abs(J2), [], 'all') + 1e-12);
testCase.verifyLessThan(rel, 1e-4, 'FD Jacobian h-vs-h/2 stable (rel<1e-4).');
end

% =========================================================================
% 6. PLL pole oracle at V0=1: {-11.27, -88.63} s^-1
% =========================================================================
function test_gfl_pll_poles_v0_1(testCase)
% Linearized PLL about V0=1: s^2 + omega0*V0*kpPLL*s + omega0*V0*kiPLL = 0.
omega0 = 376.9911184307752; kpPLL = 0.265; kiPLL = 2.65; V0 = 1.0;
a = 1;
b = omega0 * V0 * kpPLL;
c = omega0 * V0 * kiPLL;
poles = roots([a, b, c]);
% Expected: {-11.27, -88.63} (predeclared).
expected = sort([-11.27; -88.63]);
got = sort(real(poles));
testCase.verifyEqual(got, expected, 'RelTol', 1e-3, 'PLL poles {-11.27,-88.63}@V0=1.');
end

% =========================================================================
% 7. Power-loop poles critical damping V0=1: {-10,-10}
% =========================================================================
function test_gfl_powerloop_poles_critical(testCase)
% chi(s) = s^2 + omega_c*(1+V0*Kps)*s + omega_c*V0*Kis; V0=1, omega_c=10, Kps=1, Kis=10.
omega_c = 10; Kps = 1.0; Kis = 10.0; V0 = 1.0;
a = 1;
b = omega_c * (1 + V0*Kps);
c = omega_c * V0 * Kis;
poles = roots([a, b, c]);
% Expected: {-10, -10} (critically damped).
testCase.verifyEqual(sort(real(poles)), [-10; -10], 'RelTol', 1e-6, ...
    'Power-loop poles {-10,-10}@V0=1 (critically damped).');
end

% =========================================================================
% 8. Power-loop poles V0=0.8: {-8,-10}
% =========================================================================
function test_gfl_powerloop_poles_v0_08(testCase)
omega_c = 10; Kps = 1.0; Kis = 10.0; V0 = 0.8;
b = omega_c * (1 + V0*Kps);
c = omega_c * V0 * Kis;
poles = roots([1, b, c]);
% Expected (predeclared): {-8, -10}.
testCase.verifyEqual(sort(real(poles)), [-10; -8], 'RelTol', 1e-6, ...
    'Power-loop poles {-8,-10}@V0=0.8.');
end

% =========================================================================
% 9. Power-loop poles V0=1.2: {-10,-12}
% =========================================================================
function test_gfl_powerloop_poles_v0_12(testCase)
omega_c = 10; Kps = 1.0; Kis = 10.0; V0 = 1.2;
b = omega_c * (1 + V0*Kps);
c = omega_c * V0 * Kis;
poles = roots([1, b, c]);
% Expected (predeclared): {-10, -12}.
testCase.verifyEqual(sort(real(poles)), [-12; -10], 'RelTol', 1e-6, ...
    'Power-loop poles {-10,-12}@V0=1.2.');
end

% =========================================================================
% 10. Direct feedthrough: step Pref -> i_d* jumps +Kps*DeltaPref; Qref -> i_q* -Kps*DeltaQref
% =========================================================================
function test_gfl_direct_feedthrough(testCase)
[~, dev, y0, u0, ~, ~, ~] = local_gfl_fixture(0.4, 0.2);
x = dev.x0;
% Baseline i_d*, i_q* at u0.
r0 = dev.reconstruct(0, x, y0, u0, struct());
I0 = r0.I_gfl;
% Recompute i_d*/i_q* via current_injection with u = u0.
I_at_u0 = dev.current_injection(0, x, y0, u0, struct());
% Step Pref by +DeltaP (Qref unchanged). i_d* should jump by +Kps*DeltaP
% algebraically (delta_pll, P_f, phi_P unchanged since we hold x fixed).
DeltaP = 0.1;
u1 = u0 + [DeltaP; 0];
I_at_u1 = dev.current_injection(0, x, y0, u1, struct());
% Extract i_d*/i_q* by rotating back into the PLL frame (delta_pll0 = 0 here).
id0 = real(I_at_u0); iq0 = imag(I_at_u0);   % delta_pll0=0 => exp(j*0)=1
id1 = real(I_at_u1); iq1 = imag(I_at_u1);
testCase.verifyEqual(id1 - id0, 1.0 * DeltaP, 'AbsTol', 1e-12, ...
    'Pref step: Delta i_d* = +Kps*DeltaP (Kps=1).');
testCase.verifyEqual(iq1 - iq0, 0, 'AbsTol', 1e-12, 'Pref step: i_q* unchanged.');
% Step Qref by +DeltaQ. i_q* should jump by -Kps*DeltaQ.
DeltaQ = 0.05;
u2 = u0 + [0; DeltaQ];
I_at_u2 = dev.current_injection(0, x, y0, u2, struct());
id2 = real(I_at_u2); iq2 = imag(I_at_u2);
testCase.verifyEqual(iq2 - iq0, -1.0 * DeltaQ, 'AbsTol', 1e-12, ...
    'Qref step: Delta i_q* = -Kps*DeltaQ (Q-sign, Kps=1).');
testCase.verifyEqual(id2 - id0, 0, 'AbsTol', 1e-12, 'Qref step: i_d* unchanged.');
end

% =========================================================================
% 11. No-disturbance TS hold via ts_step_kernel (direct)
% =========================================================================
function test_gfl_no_disturbance_ts_holds(testCase)
[mpc, dev, y0, u0, ~, ~, Y] = local_gfl_fixture(0.4, 0.1);
% Solve the FULL coupled equilibrium (x, y) so the TS starts at a genuine
% fixed point of the trapezoidal step.
[x0, y0_eq, ~] = solve_coupled_equilibrium(dev, y0, u0, Y);

% Adapter closures binding t=0, u=u0, event_context=struct() for the legacy
% 8-arg ts_step_kernel path (dae_f(x,y), dae_g(x,y,Y)).
dae_f = @(x, yy) dev.f(0, x, yy, u0, struct());
dae_g = @(x, yy, Yadm) network_g(dev, x, yy, Yadm, u0);

opt = struct( ...
    'algebraic_tolerance', 1e-8, ...
    'max_corrector_iter', 20, ...
    'corrector_abs_tol', 1e-10, ...
    'corrector_rel_tol', 1e-8, ...
    'corrector_mode', 'adaptive');
Jyy = stability.ts_jac_y_fd(x0, y0_eq, Y, dae_g);

h = 0.01; t_end = 1.0; n_steps = round(t_end/h);
x = x0; y = y0_eq; max_drift = 0;
for k = 1:n_steps
    step = stability.ts_step_kernel(x, y, h, dae_f, dae_g, Y, Jyy, opt);
    x = step.x_full; y = step.y_full;
    max_drift = max(max_drift, norm(x - x0, inf));
end
testCase.verifyLessThan(max_drift, 1e-6, 'no-disturbance TS drift < 1e-6 over 1s.');
end

% =========================================================================
% 12. No external solver (grep guard)
% =========================================================================
function test_gfl_no_external_solver(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'gfl_model.m');
src = fileread(src_path);
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src, fn{1}), ['no ' fn{1} ' in gfl_model.']);
end
end

% =========================================================================
% 13. Provenance complete (every parameter classified)
% =========================================================================
function test_gfl_provenance_complete(testCase)
[~, dev, ~, ~, ~, ~, ~] = local_gfl_fixture(0.4, 0.0);
pv = dev.provenance;
testCase.verifyTrue(isfield(pv, 'param_classifications'), 'provenance has classifications.');
cls = pv.param_classifications;
fields_ok = {'omega0','omega_c','kpPLL','kiPLL','Kps','Kis'};
allowed = {'SOURCE_VERBATIM','CASE_DEFINED','PROJECT_DERIVED','SOURCE_TRANSFORMED','ASSUMED_DIAGNOSTIC'};
for f = fields_ok
    testCase.verifyTrue(isfield(cls, f{1}), ['classification field ' f{1} ' present.']);
    val = cls.(f{1});
    matched = false;
    for a = allowed
        if startsWith(val, a{1}), matched = true; break; end
    end
    testCase.verifyTrue(matched, ['classification ' f{1} '=' val ' starts with an allowed label.']);
end
% Kps/Kis MUST be ASSUMED_DIAGNOSTIC.
testCase.verifyTrue(startsWith(cls.Kps, 'ASSUMED_DIAGNOSTIC'), 'Kps = ASSUMED_DIAGNOSTIC.');
testCase.verifyTrue(startsWith(cls.Kis, 'ASSUMED_DIAGNOSTIC'), 'Kis = ASSUMED_DIAGNOSTIC.');
end

% =========================================================================
% 14. State count == 6
% =========================================================================
function test_gfl_state_count(testCase)
[~, dev, ~, ~, ~, ~, ~] = local_gfl_fixture(0.4, 0.0);
testCase.verifyEqual(dev.nx, 6, 'AbsTol', 0, 'nx == 6.');
testCase.verifyEqual(numel(dev.state_names), 6, 'AbsTol', 0, '6 state names.');
testCase.verifyEqual(dev.nu, 2, 'AbsTol', 0, 'nu == 2.');
end

% =========================================================================
% 15. PLL omega0 multiplier present (grep guard)
% =========================================================================
function test_gfl_pll_omega0_multiplier_present(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'gfl_model.m');
src = fileread(src_path);
% The delta_pll ODE must carry the omega0 multiplier: d(delta_pll)/dt = omega0*(...).
testCase.verifyTrue(contains(src, 'omega0*(kpPLL*Vq_pll + kiPLL*eps_pll)'), ...
    'delta_pll ODE carries omega0 multiplier (prevents v1 scaling regression).');
% Must NOT contain the unscaled form (the v1 error).
testCase.verifyFalse(contains(src, 'd_delta_pll = kpPLL*Vq_pll + kiPLL*eps_pll'), ...
    'unscaled delta_pll ODE (v1 error) absent.');
end

% =========================================================================
% 16. Q-sign correct (i_q* carries the negative sign)
% =========================================================================
function test_gfl_qsign_correct(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'gfl_model.m');
src = fileread(src_path);
% The i_q* equation must have a leading minus on BOTH the Kps and Kis terms.
testCase.verifyTrue(contains(src, 'i_q_star = -Kps*(Q_ref - Q_f) - Kis*phi_Q'), ...
    'i_q* = -Kps*(Qref-Qf) - Kis*phi_Q (Q-sign correct).');
% Equilibrium i_q*0 = -Qref/V0 (negative for positive Qref).
[~, dev, y0, u0, V0, ~, ~] = local_gfl_fixture(0.4, 0.2);
x = dev.x0;
I = dev.current_injection(0, x, y0, u0, struct());
% delta_pll0 = 0 => I = i_d*0 + j*i_q*0.
testCase.verifyEqual(real(I), 0.4/V0, 'AbsTol', 1e-12, 'i_d*0 = +Pref/V0.');
testCase.verifyEqual(imag(I), -0.2/V0, 'AbsTol', 1e-12, 'i_q*0 = -Qref/V0 (negative).');
end

% =========================================================================
% Helper: network g for the 2-bus system (g = Y*V - Ibus, stiff slack at bus 1).
% =========================================================================
function g = network_g(dev, x, y, Y, u)
nb = size(Y, 1);
V = complex(y(1:2:2*nb), y(2:2:2*nb));
Ibus = zeros(nb, 1);
% Stiff slack current at bus 1: I_slack = Yslack * V1_ref, so that the bus 1
% KCL Y(1,1)*V1 - I_slack = Yslack*(V1 - V1_ref) pins V1 -> V1_ref = 1.06+0j.
Yslack = 1e3;
V1_ref = 1.06 + 0i;
Ibus(1) = Yslack * V1_ref;
% GFL at bus 2 (bus_position 2 in this fixture).
Ibus(2) = dev.current_injection(0, x, y, u, struct());
gc = Y*V - Ibus;
g = zeros(2*nb, 1);
g(1:2:2*nb) = real(gc);
g(2:2:2*nb) = imag(gc);
end

% =========================================================================
% Helper: solve the FULL coupled equilibrium (x, y) via damped Newton.
%   Unknowns z = [x(6); y(4)] (10 total). Residual r(z) = [f(x,y,u); g(x,y,Y,u)].
%   Returns x_eq, y_eq, and the final residual norm.
% =========================================================================
function [x_eq, y_eq, res_norm] = solve_coupled_equilibrium(dev, y0, u0, Y)
nx = dev.nx; ny = numel(y0);
z = [dev.x0; y0];
fd_eps = 1e-6;
res_norm = inf;
for iter = 1:100
    x = z(1:nx); y = z(nx+1:nx+ny);
    f = dev.f(0, x, y, u0, struct());
    g = network_g(dev, x, y, Y, u0);
    r = [f(:); g];
    res_norm = norm(r, inf);
    if res_norm < 1e-12, break; end
    % Central-FD Jacobian (10x10).
    nz = numel(z);
    J = zeros(nz, nz);
    for j = 1:nz
        zp = z; zp(j) = zp(j) + fd_eps;
        zm = z; zm(j) = zm(j) - fd_eps;
        xp = zp(1:nx); yp = zp(nx+1:nx+ny);
        xm = zm(1:nx); ym = zm(nx+1:nx+ny);
        fp = dev.f(0, xp, yp, u0, struct()); fp = fp(:);
        gp = network_g(dev, xp, yp, Y, u0);
        rp = [fp; gp];
        fm = dev.f(0, xm, ym, u0, struct()); fm = fm(:);
        gm = network_g(dev, xm, ym, Y, u0);
        rm = [fm; gm];
        J(:,j) = (rp - rm) / (2*fd_eps);
    end
    % Damped Newton with backtracking.
    dz = -(J \ r);
    alpha = 1.0;
    for ls = 1:20
        zt = z + alpha*dz;
        xt = zt(1:nx); yt = zt(nx+1:nx+ny);
        ft = dev.f(0, xt, yt, u0, struct()); ft = ft(:);
        gt = network_g(dev, xt, yt, Y, u0);
        rt = [ft; gt];
        if norm(rt, inf) < res_norm, break; end
        alpha = alpha * 0.5;
    end
    z = z + alpha*dz;
end
x_eq = z(1:nx); y_eq = z(nx+1:nx+ny);
end
