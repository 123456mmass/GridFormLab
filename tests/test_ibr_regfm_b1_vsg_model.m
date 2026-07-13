function tests = test_ibr_regfm_b1_vsg_model()
%TEST_IBR_REGFM_B1_VSG_MODEL  Phase 6 GFM model structural tests (STRUCTURAL_ONLY).
%   Verifies the +ibr/regfm_b1_vsg_model device: REGFM_B1 (NREL/TP-5D00-90260)
%   equation structure (Eqs.1-13 + Table 1), composite_dae ABI conformance,
%   sign/base/frame conventions, inverter-base swing contract (kappa=Sbase/Mbase,
%   no double conversion), predeclared pole oracles, FD Jacobian agreement,
%   kappa~=1 equilibrium falsification, and source guards.
%
%   Source: docs/project/IEEE14_IBR_GFM_PHASE6_PROVENANCE.md;
%           docs/project/IEEE14_IBR_DECISION_LEDGER.md (Item 2).
%   Phase 6 is STRUCTURAL_ONLY: limiters/FRT deferred to Phase 14. NO
%   ASSUMED_DIAGNOSTIC parameters (all SOURCE_VERBATIM from REGFM_B1 Table 1).
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
% Shared fixture: minimal 2-bus infinite-bus mpc + a GFM device at bus 2.
% =========================================================================
function [mpc, dev, y0, u0, V0, theta0, Y] = local_gfm_fixture(P_ref, V_ref, theta0, Mbase)
%LOCAL_GFM_FIXTURE  2-bus infinite-bus: bus1 REF (V=1.06), bus2 PQ (GFM).
%   Branch r=0, x=0.1 pu. The GFM connects at bus 2 (bus_position=2).
%   theta0 (optional, default 0) sets the bus-2 angle. V0 = 1.0*exp(j*theta0).
%   Mbase (optional, default 100) sets the inverter-rating nameplate proxy.
if nargin < 3 || isempty(theta0), theta0 = 0.0; end
if nargin < 4 || isempty(Mbase), Mbase = 100.0; end
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = [ ...
    1, 3, 0, 0, 0, 0, 1, 1.06, 0, 69, 1, 1.1, 0.9; ...
    2, 1, 0, 0, 0, 0, 1, 1.00, 0, 69, 1, 1.1, 0.9];
mpc.gen = [1, 0, 0, 0, -0, 1.06, 100, 1, 0, -0];
mpc.branch = [1, 2, 0.0, 0.1, 0.0, 0, 0, 0, 1.0, 0, 1];
mpc.gencost = [];
mpc.case_name = 'gfm_infinite_bus_2bus';

V0 = 1.0 * exp(1i * theta0);
bus_ids = [1; 2];
params = struct('Mbase', Mbase);
dev = ibr.regfm_b1_vsg_model('IBR_test', 2, 2, bus_ids, V0, params, P_ref, V_ref);
u0 = dev.u0;

y0 = zeros(4,1);
y0(1:2) = [1.06; 0.0];
y0(3:4) = [real(V0); imag(V0)];

Y = local_ybus(mpc);
end

function Y = local_ybus(mpc)
%LOCAL_YBUS  2-bus Ybus with a STIFF slack admittance at bus 1 (Yslack=1e3).
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
Yslack = 1e3;
Y(1,1) = Y(1,1) + Yslack;
end

% =========================================================================
% 1. State count and ABI conformance
% =========================================================================
function test_gfm_state_count(testCase)
[~, dev, ~, ~, ~, ~, ~] = local_gfm_fixture(0.4, 1.0);
testCase.verifyEqual(dev.nx, 11, 'AbsTol', 0, 'nx == 11.');
testCase.verifyEqual(dev.nu, 2, 'AbsTol', 0, 'nu == 2.');
testCase.verifyEqual(numel(dev.state_names), 11, 'AbsTol', 0, '11 state names.');
testCase.verifyEqual(dev.mode, 'GFM', 'mode == GFM.');
testCase.verifyEqual(dev.device_type, 'ibr_gfm', 'device_type == ibr_gfm.');
testCase.verifyEqual(dev.provenance.readiness, 'STRUCTURAL_ONLY', 'STRUCTURAL_ONLY.');
end

% =========================================================================
% 2. P/Q sign (S = V*conj(I), generator convention) at warm-start
% =========================================================================
function test_gfm_pq_sign(testCase)
[~, dev, y0, u0, ~, ~, ~] = local_gfm_fixture(0.4, 1.0);
x = dev.x0;
I = dev.current_injection(0, x, y0, u0, struct());
V_bus = complex(y0(3), y0(4));
S = V_bus * conj(I);
% At warm-start delta_VSM = theta0 = 0, EVSM = V_ref (Qinv_f=0, x_Eint=0, kpv=0).
% I = (EVSM - V_bus)/(Re + j*XL). With V_ref=1.0, V_bus=1.0, I=0 => P=0, Q=0.
% This is the warm-start (not the true equilibrium); the sign convention is
% verified by the equilibrium test (T4) where P_meas = P_ref.
testCase.verifyTrue(isfinite(real(S)), 'P finite at warm-start.');
testCase.verifyTrue(isfinite(imag(S)), 'Q finite at warm-start.');
end

% =========================================================================
% 3. Current into network (positive injection for P_ref>0 at equilibrium)
% =========================================================================
function test_gfm_current_into_network(testCase)
[~, dev, y0, u0, ~, ~, Y] = local_gfm_fixture(0.4, 1.0);
[x_eq, y_eq, res_norm] = solve_coupled_equilibrium(dev, y0, u0, Y);
testCase.verifyLessThan(res_norm, 1e-6, 'equilibrium residual < 1e-6.');
I = dev.current_injection(0, x_eq, y_eq, u0, struct());
V_bus = complex(y_eq(3), y_eq(4));
S = V_bus * conj(I);
P = real(S);
% At equilibrium P_meas (system base) = P_ref = 0.4 (kappa=1 here).
testCase.verifyEqual(P, 0.4, 'AbsTol', 1e-6, 'P = P_ref at equilibrium (system base).');
% Positive active-power injection into network for P_ref>0.
testCase.verifyGreaterThan(P, 0, 'P > 0 for P_ref > 0 (into network).');
end

% =========================================================================
% 4. Equilibrium residual (standalone coupled Newton, NOT mixed_equilibrium_solve)
% =========================================================================
function test_gfm_equilibrium_residual(testCase)
[~, dev, y0, u0, ~, ~, Y] = local_gfm_fixture(0.4, 1.0);
[x_eq, y_eq, res_norm] = solve_coupled_equilibrium(dev, y0, u0, Y);
testCase.verifyLessThan(res_norm, 1e-6, 'coupled residual < 1e-6 at solved equilibrium.');
% omega_m = 0 at equilibrium (no drift).
testCase.verifyEqual(x_eq(1), 0, 'AbsTol', 1e-6, 'omega_m = 0 at equilibrium.');
% P_meas (system base) = P_ref at equilibrium.
I = dev.current_injection(0, x_eq, y_eq, u0, struct());
V_bus = complex(y_eq(3), y_eq(4));
P_meas = real(V_bus * conj(I));
testCase.verifyEqual(P_meas, 0.4, 'AbsTol', 1e-6, 'P_meas = P_ref (system base).');
end

% =========================================================================
% 5. Jacobian FD agreement (FD self-consistency; no analytic Jacobian)
%   Uses the SOLVED equilibrium and the FULL coupled Jacobian J = d[f;g]/d[x;y]
%   (not Jxx alone). Jxx is structurally rank-deficient at equilibrium because
%   REGFM_B1 Eqs.1-2 (Pinv_f, Idinv_f) are both driven by Id with the same TIf,
%   and Eqs.3,5 (Qinv_f, Iqinv_f) both driven by Iq with the same TIf; at
%   constant V these row pairs are linearly dependent. The coupled (x,y)
%   Jacobian is full-rank because the algebraic network variables y break the
%   dependency. This mirrors mixed_equilibrium_solve, which solves the coupled
%   (x, y_free) system.
% =========================================================================
function test_gfm_jacobian_fd_agreement(testCase)
[~, dev, y0, u0, ~, ~, Y] = local_gfm_fixture(0.4, 1.0);
[x_eq, y_eq, res_norm] = solve_coupled_equilibrium(dev, y0, u0, Y);
testCase.verifyLessThan(res_norm, 1e-6, 'equilibrium solved before Jacobian test.');
fd_eps = 3e-6;
nx = dev.nx; ny = numel(y_eq);
z = [x_eq; y_eq];
nz = numel(z);
% Full coupled Jacobian d[f;g]/d[x;y].
J = zeros(nz, nz);
r0 = coupled_r(dev, x_eq, y_eq, Y, u0);
for j = 1:nz
    zp = z; zm = z;
    zp(j) = zp(j) + fd_eps;
    zm(j) = zm(j) - fd_eps;
    rp = coupled_r(dev, zp(1:nx), zp(nx+1:nz), Y, u0);
    rm = coupled_r(dev, zm(1:nx), zm(nx+1:nz), Y, u0);
    J(:,j) = (rp - rm) / (2*fd_eps);
end
testCase.verifyTrue(all(isfinite(J(:))), 'coupled FD Jacobian finite.');
testCase.verifyGreaterThan(rcond(J), 1e-10, 'coupled Jacobian well-conditioned (rcond>1e-10).');
% h-vs-h/2 Richardson stability.
J2 = zeros(nz, nz);
for j = 1:nz
    zp = z; zm = z;
    zp(j) = zp(j) + fd_eps/2;
    zm(j) = zm(j) - fd_eps/2;
    rp = coupled_r(dev, zp(1:nx), zp(nx+1:nz), Y, u0);
    rm = coupled_r(dev, zm(1:nx), zm(nx+1:nz), Y, u0);
    J2(:,j) = (rp - rm) / (2*(fd_eps/2));
end
rel = max(abs(J - J2), [], 'all') / (max(abs(J), [], 'all') + max(abs(J2), [], 'all') + 1e-12);
testCase.verifyLessThan(rel, 1e-4, 'coupled FD Jacobian h-vs-h/2 stable (rel<1e-4).');
end

function r = coupled_r(dev, x, y, Y, u)
f = dev.f(0, x, y, u, struct());
g = network_g(dev, x, y, Y, u);
r = [f(:); g];
end

% =========================================================================
% 6. PLL pole oracle at V0=1: {-11.27, -88.63} s^-1 (same kpPLL/kiPLL as GFL)
% =========================================================================
function test_gfm_pll_poles(testCase)
[~, dev, ~, ~, ~, ~, ~] = local_gfm_fixture(0.4, 1.0);
p = dev.provenance.params;
V0 = 1.0;
b = p.omega0 * V0 * p.kpPLL;
c = p.omega0 * V0 * p.kiPLL;
poles = roots([1, b, c]);
expected = sort([-11.27; -88.63]);
got = sort(real(poles));
testCase.verifyEqual(got, expected, 'RelTol', 1e-3, 'PLL poles {-11.27,-88.63}@V0=1.');
end

% =========================================================================
% 7. VSM swing + washout pole oracle (frozen params, inverter base)
%   Swing: 2H*s^2 + (1/mp + D1 + D2)*s + D2*wD = 0  (washout coupled)
%   With D1=0, H=0.5, mp=0.02, D2=100, wD=50.
% =========================================================================
function test_gfm_vsm_poles(testCase)
[~, dev, ~, ~, ~, ~, ~] = local_gfm_fixture(0.4, 1.0);
p = dev.provenance.params;
% Linearized swing+washout about omega_m=0, x_washout=0:
%   2H d(omega_m)/dt = -(1/mp + D1)*omega_m - D2*(omega_m - x_washout) + (P_ref_inv - Pinv_f)
%   d(x_washout)/dt = wD*(omega_m - x_washout)
% State [omega_m; x_washout]. A = [-(1/mp+D1+D2)/(2H), D2/(2H); wD, -wD].
A = [-(1/p.mp + p.D1 + p.D2)/(2*p.H), p.D2/(2*p.H); p.wD, -p.wD];
poles = eig(A);
% Predeclared: both real, negative (stable). With these params the swing pole
% is fast (~ -1/mp/(2H) = -50) and the washout pole ~ -wD = -50 region.
testCase.verifyTrue(all(real(poles) < 0), 'VSM swing poles stable (Re<0).');
% The dominant (slowest) pole must be negative and finite.
slowest = max(real(poles));
testCase.verifyLessThan(slowest, 0, 'slowest VSM pole < 0.');
testCase.verifyTrue(all(isfinite(poles)), 'VSM poles finite.');
end

% =========================================================================
% 8. No external solver (grep guard)
% =========================================================================
function test_gfm_no_external_solver(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'regfm_b1_vsg_model.m');
src = fileread(src_path);
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src, fn{1}), ['no ' fn{1} ' in regfm_b1_vsg_model.']);
end
end

% =========================================================================
% 9. Provenance complete (all params classified; NO ASSUMED_DIAGNOSTIC)
%   Uses params=struct() (no overrides) so all params keep their frozen
%   default classification (Mbase=CASE_DEFINED, others=SOURCE_VERBATIM).
% =========================================================================
function test_gfm_provenance_complete(testCase)
bus_ids = [1; 2];
dev = ibr.regfm_b1_vsg_model('IBR_test', 2, 2, bus_ids, 1.0+0i, struct(), 0.4, 1.0);
cls = dev.provenance.param_classifications;
fields = fieldnames(cls);
allowed = {'SOURCE_VERBATIM','CASE_DEFINED','DIAGNOSTIC_ONLY', ...
    'SOURCE_VERBATIM_value_CASE_DEFINED_PROJECT_MAPPED_application'};
for k = 1:numel(fields)
    v = cls.(fields{k});
    testCase.verifyTrue(any(strcmp(v, allowed)), ...
        ['param ' fields{k} ' has valid classification: ' v]);
    testCase.verifyFalse(contains(v, 'ASSUMED_DIAGNOSTIC'), ...
        ['param ' fields{k} ' must NOT be ASSUMED_DIAGNOSTIC (GFM is source-closed).']);
end
% Mbase must be CASE_DEFINED (nameplate proxy).
testCase.verifyEqual(cls.Mbase, 'CASE_DEFINED', 'Mbase = CASE_DEFINED.');
% Input classifications.
testCase.verifyEqual(dev.provenance.input_classifications.P_ref, ...
    'SOURCE_TRANSFORMED_PROJECT_MAPPED', 'P_ref input classification.');
testCase.verifyEqual(dev.provenance.input_classifications.V_ref, ...
    'SOURCE_TRANSFORMED_PROJECT_MAPPED', 'V_ref input classification.');
end

% =========================================================================
% 10. Source guards (omega0 multiplier, Eq.13 form, droop 1/mp present)
% =========================================================================
function test_gfm_source_guards(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'regfm_b1_vsg_model.m');
src = fileread(src_path);
% omega0 multiplier in swing (d_delta_VSM = omega0*omega_m).
testCase.verifyTrue(contains(src, 'omega0*omega_m'), 'omega0 multiplier in swing.');
% Eq.13 output stage form.
testCase.verifyTrue(contains(src, 'EVSM*exp(1i*delta_VSM) - V_bus'), 'Eq.13 output stage.');
% Droop 1/mp effective damping present.
testCase.verifyTrue(contains(src, '1/mp'), '1/mp droop damping present.');
% kappa boundary mapping present.
testCase.verifyTrue(contains(src, 'kappa = Sbase / Mbase'), 'kappa boundary mapping.');
% No double conversion guard: P_ref_inv computed once.
testCase.verifyTrue(contains(src, 'P_ref_inv = kappa * P_ref'), 'P_ref converted once.');
end

% =========================================================================
% 11. Fail-closed: bad V0
% =========================================================================
function test_gfm_fail_closed_v0(testCase)
bus_ids = [1; 2];
try
    ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, 0, struct(), 0.4, 1.0);
    testCase.verifyFail('bad V0 (zero) must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badV0', 'badV0 id.');
end
try
    ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, NaN, struct(), 0.4, 1.0);
    testCase.verifyFail('NaN V0 must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badV0', 'NaN V0 id.');
end
end

% =========================================================================
% 12. Fail-closed: bus mapping
% =========================================================================
function test_gfm_fail_closed_bus_mapping(testCase)
bus_ids = [1; 5; 9];
try
    ibr.regfm_b1_vsg_model('T', 5, 1, bus_ids, 1.0, struct(), 0.4, 1.0);
    testCase.verifyFail('bus_position/bus_id mismatch must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:busMappingMismatch', ...
        'busMappingMismatch id.');
end
try
    ibr.regfm_b1_vsg_model('T', 5, 4, bus_ids, 1.0, struct(), 0.4, 1.0);
    testCase.verifyFail('out-of-range bus_position must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:busMappingMismatch', ...
        'out-of-range id.');
end
try
    ibr.regfm_b1_vsg_model('T', 5, 1.5, bus_ids, 1.0, struct(), 0.4, 1.0);
    testCase.verifyFail('fractional bus_position must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:busMappingMismatch', ...
        'fractional id.');
end
end

% =========================================================================
% 13. Fail-closed: bad params (incl. Mbase)
% =========================================================================
function test_gfm_fail_closed_params(testCase)
bus_ids = [1; 2];
try
    ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, 1.0, struct('XL',-0.1), 0.4, 1.0);
    testCase.verifyFail('negative XL must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badParam', 'bad XL id.');
end
try
    ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, 1.0, struct('Mbase',0), 0.4, 1.0);
    testCase.verifyFail('zero Mbase must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badParam', 'bad Mbase id.');
end
try
    ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, 1.0, struct('Mbase',NaN), 0.4, 1.0);
    testCase.verifyFail('NaN Mbase must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badParam', 'NaN Mbase id.');
end
try
    ibr.regfm_b1_vsg_model('T', 2, 2, bus_ids, 1.0, struct(), NaN, 1.0);
    testCase.verifyFail('NaN P_ref must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badRef', 'NaN P_ref id.');
end
end

% =========================================================================
% 14. Fail-closed: bad input u_dev
% =========================================================================
function test_gfm_fail_closed_u(testCase)
[~, dev, y0, ~, ~, ~, ~] = local_gfm_fixture(0.4, 1.0);
x = dev.x0;
try
    dev.f(0, x, y0, [], struct());
    testCase.verifyFail('empty u must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:missingInput', 'empty u id.');
end
try
    dev.f(0, x, y0, [0.4], struct());
    testCase.verifyFail('1-element u must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badInput', '1-elem u id.');
end
try
    dev.f(0, x, y0, [0.4; 1.0; 0.0], struct());
    testCase.verifyFail('3-element u must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badInput', '3-elem u id.');
end
try
    dev.f(0, x, y0, [NaN; 1.0], struct());
    testCase.verifyFail('NaN u must error.');
catch e
    testCase.verifyEqual(e.identifier, 'ibr:regfm_b1_vsg_model:badInput', 'NaN u id.');
end
end

% =========================================================================
% 15. Numerical linearization vs analytic PLL oracle
% =========================================================================
function test_gfm_numerical_linearization(testCase)
[~, dev, y0, u0, ~, ~, ~] = local_gfm_fixture(0.4, 1.0);
x = dev.x0;
fd_eps = 1e-6;
nx = dev.nx;
J = zeros(nx, nx);
f0 = dev.f(0, x, y0, u0, struct());
for j = 1:nx
    xp = x; xm = x;
    xp(j) = xp(j) + fd_eps;
    xm(j) = xm(j) - fd_eps;
    J(:,j) = (dev.f(0, xp, y0, u0, struct()) - dev.f(0, xm, y0, u0, struct())) / (2*fd_eps);
end
% PLL block is states 5 (delta_PLL) and 6 (x_PLL_int). Extract 2x2 sub-block.
Jpll = J(5:6, 5:6);
eig_num = eig(Jpll);
% Analytic PLL poles at V0=1: {-11.27, -88.63}.
p = dev.provenance.params;
b = p.omega0 * 1.0 * p.kpPLL;
c = p.omega0 * 1.0 * p.kiPLL;
eig_an = roots([1, b, c]);
testCase.verifyEqual(sort(real(eig_num)), sort(real(eig_an)), 'AbsTol', 5e-2, ...
    'numerical PLL eigenvalues match analytic oracle.');
end

% =========================================================================
% 16. Mbase validation + kappa conversion test
% =========================================================================
function test_gfm_mbase_validation(testCase)
[~, dev, ~, ~, ~, ~, ~] = local_gfm_fixture(0.4, 1.0, 0, 140.0);
% kappa = Sbase/Mbase = 100/140.
testCase.verifyEqual(dev.provenance.params.Mbase, 140, 'AbsTol', 0, 'Mbase=140.');
r = dev.reconstruct(0, dev.x0, [1.06;0;1.0;0;1.0;0;1.0;0;1.0;0], dev.u0, struct());
testCase.verifyEqual(r.kappa, 100/140, 'AbsTol', 1e-12, 'kappa = Sbase/Mbase.');
% P_ref_inv = kappa * P_ref_sys = (100/140)*0.4.
testCase.verifyEqual(r.P_ref_inv, (100/140)*0.4, 'AbsTol', 1e-12, 'P_ref_inv = kappa*P_ref.');
end

% =========================================================================
% 17. kappa ~= 1 equilibrium falsification (IBR2 kappa=100/140, IBR3/6/8 kappa=1)
% =========================================================================
function test_gfm_kappa_neq1_equilibrium(testCase)
% IBR2: Mbase=140 => kappa=100/140 ~= 0.714.
[~, dev2, y0, u0, ~, ~, Y] = local_gfm_fixture(0.4, 1.0, 0, 140.0);
[x_eq2, y_eq2, res2] = solve_coupled_equilibrium(dev2, y0, u0, Y);
testCase.verifyLessThan(res2, 1e-6, 'IBR2 (kappa~=0.714) equilibrium residual < 1e-6.');
testCase.verifyEqual(x_eq2(1), 0, 'AbsTol', 1e-6, 'IBR2 omega_m = 0.');
I2 = dev2.current_injection(0, x_eq2, y_eq2, u0, struct());
V2 = complex(y_eq2(3), y_eq2(4));
P2 = real(V2 * conj(I2));
testCase.verifyEqual(P2, 0.4, 'AbsTol', 1e-6, 'IBR2 P_meas = P_ref (system base).');
% IBR3/6/8: Mbase=100 => kappa=1.
[~, dev1, y0b, u0b, ~, ~, Yb] = local_gfm_fixture(0.4, 1.0, 0, 100.0);
[x_eq1, y_eq1, res1] = solve_coupled_equilibrium(dev1, y0b, u0b, Yb);
testCase.verifyLessThan(res1, 1e-6, 'IBR3/6/8 (kappa=1) equilibrium residual < 1e-6.');
testCase.verifyEqual(x_eq1(1), 0, 'AbsTol', 1e-6, 'IBR3/6/8 omega_m = 0.');
I1 = dev1.current_injection(0, x_eq1, y_eq1, u0b, struct());
V1 = complex(y_eq1(3), y_eq1(4));
P1 = real(V1 * conj(I1));
testCase.verifyEqual(P1, 0.4, 'AbsTol', 1e-6, 'IBR3/6/8 P_meas = P_ref (system base).');
end

% =========================================================================
% 18. Flag profile frozen (grep guard)
% =========================================================================
function test_gfm_flag_profile_frozen(testCase)
src_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'regfm_b1_vsg_model.m');
src = fileread(src_path);
testCase.verifyTrue(contains(src, 'omegaFlag = 0'), 'omegaFlag=0 frozen.');
testCase.verifyTrue(contains(src, 'FFlag = 1'), 'FFlag=1 frozen.');
testCase.verifyTrue(contains(src, 'omega_ref = 1.0'), 'omega_ref=1 frozen.');
testCase.verifyTrue(contains(src, 'VdrpFlag = 0'), 'VdrpFlag=0 frozen.');
testCase.verifyTrue(contains(src, 'QVFlag = 1'), 'QVFlag=1 frozen.');
end

% =========================================================================
% Helper: network g for the 2-bus system (g = Y*V - Ibus, stiff slack at bus 1).
% =========================================================================
function g = network_g(dev, x, y, Y, u)
nb = size(Y, 1);
V = complex(y(1:2:2*nb), y(2:2:2*nb));
Ibus = zeros(nb, 1);
Yslack = 1e3;
V1_ref = 1.06 + 0i;
Ibus(1) = Yslack * V1_ref;
Ibus(2) = dev.current_injection(0, x, y, u, struct());
gc = Y*V - Ibus;
g = zeros(2*nb, 1);
g(1:2:2*nb) = real(gc);
g(2:2:2*nb) = imag(gc);
end

% =========================================================================
% Helper: solve the FULL coupled equilibrium (x, y) via damped Newton.
%   Unknowns z = [x(11); y(4)] (15 total). Residual r(z) = [f(x,y,u); g(x,y,Y,u)].
% =========================================================================
function [x_eq, y_eq, res_norm] = solve_coupled_equilibrium(dev, y0, u0, Y)
nx = dev.nx; ny = numel(y0);
z = [dev.x0; y0];
fd_eps = 1e-6;
res_norm = inf;
for iter = 1:200
    x = z(1:nx); y = z(nx+1:nx+ny);
    f = dev.f(0, x, y, u0, struct());
    g = network_g(dev, x, y, Y, u0);
    r = [f(:); g];
    res_norm = norm(r, inf);
    if res_norm < 1e-12, break; end
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
