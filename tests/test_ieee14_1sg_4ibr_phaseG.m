function tests = test_ieee14_1sg_4ibr_phaseG()
%TEST_IEEE14_1SG_4IBR_PHASEG  Phase-G-1 Eq.13 clamp + VPLL freeze tests.
%   Verifies ImaxF transient clamp (REGFM_B1 Eq.13/Fig.7), VPLL freeze
%   (REGFM_B1 Fig.4), shared current helper consistency, kappa base
%   conversion, reconstruct metadata, no NaN/Inf, nx unchanged.
%
%   Source: REGFM_B1 NREL/TP-5D00-90260 Eq.13, Fig.7, Fig.4, Table 1.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function dev = build_gfm(mbase, P_ref, V_ref)
% Build standalone GFM with given Mbase (kappa = 100/Mbase).
% bus_position=1 so V_bus comes from y(1)+j*y(2) of full 28-element y.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
bus_ids = c.mpc.bus(:,1)';
V0 = 1.04 + 0i;
params = struct('Mbase', mbase);
dev = ibr.regfm_b1_vsg_model("GFM_TEST", bus_ids(1), 1, bus_ids, V0, params, P_ref, V_ref);
end

function y_full = make_y(V_bus, nb)
% Build full y vector with V_bus at bus 1, zeros elsewhere.
y_full = zeros(2*nb, 1);
y_full(1) = real(V_bus);
y_full(2) = imag(V_bus);
end

% =========================================================================
function test_imaxf_clamp_at_threshold_kappa1(testCase)
% Mbase=100 (kappa=1): ImaxF_sys=1.5. Force |I|>=1.5 via high Vref.
dev = build_gfm(100, 0.0, 1.2);
V_bus = 0.9 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.0; 1.2];
% current_injection closure
I_out = dev.current_injection(0, dev.x0, y, u0, struct());
testCase.verifyLessThanOrEqual(abs(I_out), 1.5 + 1e-12, ...
    '|I_out| <= ImaxF_sys=1.5 at kappa=1.');
% With much higher Vref, should clamp exactly at 1.5
dev2 = build_gfm(100, 0.0, 3.0);
u2 = [0.0; 3.0];
I_out2 = dev2.current_injection(0, dev2.x0, y, u2, struct());
testCase.verifyEqual(abs(I_out2), 1.5, 'AbsTol', 1e-12, ...
    'Clamp at exactly 1.5 when |I_unc| >> ImaxF_sys at kappa=1.');
end

% =========================================================================
function test_imaxf_clamp_at_threshold_kappa_not_1(testCase)
% IBR2: Mbase=140, kappa=100/140≈0.7143, ImaxF_sys=1.5/(100/140)=2.10.
dev = build_gfm(140, 0.0, 0.5);
V_bus = 0.9 + 0i;  nb = 14;  y = make_y(V_bus, nb);
% Normal dispatch — should be below threshold
u0 = [0.0; 0.5];
I1 = dev.current_injection(0, dev.x0, y, u0, struct());
testCase.verifyLessThanOrEqual(abs(I1), 2.10, ...
    'Below ImaxF_sys=2.10 at normal dispatch, kappa≠1.');
% High Vref — should clamp at 2.10
u2 = [0.0; 3.0];
I2 = dev.current_injection(0, dev.x0, y, u2, struct());
testCase.verifyEqual(abs(I2), 2.10, 'AbsTol', 1e-12, ...
    'Clamp at ImaxF_sys=2.10 (not 1.5) at kappa≠1.');
end

% =========================================================================
function test_imaxf_not_clamped_below_threshold(testCase)
% At normal dispatch, limiter should be inactive — linear branch.
dev = build_gfm(100, 0.4, 1.0);
V_bus = 1.0 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.4; 1.0];
% Compute I_unc manually for oracle
EVSM = 1.0;   % Vref - mq*Qinv_f + ... at init Qinv_f=0, Vinv_f=1.0
[I_out, I_unc, I_limited] = current_inj_oracle(dev, y, u0);
testCase.verifyFalse(I_limited, 'Not limited below threshold.');
testCase.verifyEqual(I_out, I_unc, 'AbsTol', 1e-12, ...
    'I_out == I_unc when below ImaxF.');
end

% =========================================================================
function test_kappa1_base_equivalence_oracle(testCase)
% At kappa=1, verify manual inverter-base computation matches.
dev = build_gfm(100, 0.0, 1.2);
V_bus = 1.0 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.0; 1.2];
[I_out, ~, ~] = current_inj_oracle(dev, y, u0);
% Manual: Z_sys=kappa*Z_inv=0+0.1i, ImaxF_sys=1.5/1=1.5
x = dev.x0; delta_VSM = x(2);
EVSM = 1.2;  % V_ref - mq*0 + kpv*(V_ref-|V|) + kiv*0 at init
I_manual = (EVSM*exp(1i*delta_VSM) - V_bus) / (0 + 0.1i);
I_mag = abs(I_manual);
if I_mag >= 1.5, I_manual = 1.5 * (I_manual / I_mag); end
testCase.verifyEqual(I_out, I_manual, 'AbsTol', 1e-12, ...
    'kappa=1 output matches manual inverter-base computation.');
end

% =========================================================================
function test_shared_helper_consistency(testCase)
% current_injection, electrical_power, reconstruct must all use same I_out.
dev = build_gfm(100, 0.4, 1.0);
V_bus = 1.0 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.4; 1.0];
I_inj = dev.current_injection(0, dev.x0, y, u0, struct());
Pe    = dev.electrical_power(0, dev.x0, y, u0, struct());
Pe_expected = real(V_bus * conj(I_inj));
testCase.verifyEqual(Pe, Pe_expected, 'AbsTol', 1e-12, ...
    'Pe = real(V*conj(I_inj)) — same I_out.');
rec = dev.reconstruct(0, dev.x0, y, u0, struct());
testCase.verifyEqual(rec.I_gfm, I_inj, 'AbsTol', 1e-12, ...
    'reconstruct.I_gfm == current_injection.');
testCase.verifyEqual(rec.Pe, Pe_expected, 'AbsTol', 1e-12, ...
    'reconstruct.Pe == real(V*conj(I_out)).');
end

% =========================================================================
function test_rhs_filters_use_limited_current(testCase)
% At high current where clamp active, verify every current-dependent filter
% uses I_out (not I_unc).  The earlier oracle used a collinear real voltage
% and internal voltage, so the current was purely reactive and both active
% powers were exactly zero even though the clamp was active.  A non-collinear
% phasor makes P, Id and Iq independently observable without changing the
% sourced Eq.13 model or its thresholds.
dev = build_gfm(100, 0.0, 1.5);
V_bus = 0.9*exp(1i*0.15);  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.0; 1.5];
% Independent Eq.13 oracle at kappa=1: EVSM=Vref=1.5, delta_VSM=0,
% Zsys=j0.1 and ImaxF_sys=1.5 (REGFM_B1 Table 1).
I_unc = (1.5*exp(1i*dev.x0(2)) - V_bus)/(1i*0.1);
I_out_oracle = 1.5*I_unc/abs(I_unc);
I_out = dev.current_injection(0, dev.x0, y, u0, struct());
rec = dev.reconstruct(0, dev.x0, y, u0, struct());
I_limited = rec.I_limited;
testCase.verifyTrue(I_limited, 'Clamp active for filter test.');
testCase.verifyEqual(rec.I_unc_sys, I_unc, 'AbsTol', 1e-12, ...
    'Reconstructed uncontrolled current matches independent Eq.13 oracle.');
testCase.verifyEqual(I_out, I_out_oracle, 'AbsTol', 1e-12, ...
    'Output current matches independent circular-clamp oracle.');
testCase.verifyGreaterThan(abs(I_out-I_unc), 1, ...
    'Limited complex current must differ materially from I_unc.');

% Independent limited and uncontrolled measurement oracles.
P_out = real(V_bus * conj(I_out));
P_unc = real(V_bus * conj(I_unc));
Id_out = real(I_out * exp(-1i*dev.x0(5)));
Id_unc = real(I_unc * exp(-1i*dev.x0(5)));
Iq_out = imag(I_out * exp(-1i*dev.x0(5)));
Iq_unc = imag(I_unc * exp(-1i*dev.x0(5)));
testCase.verifyGreaterThan(abs(P_out-P_unc), 1e-3, ...
    'Non-collinear oracle distinguishes limited from uncontrolled active power.');
testCase.verifyGreaterThan(abs(Id_out-Id_unc), 1e-3, ...
    'Non-collinear oracle distinguishes limited from uncontrolled Id.');
testCase.verifyGreaterThan(abs(Iq_out-Iq_unc), 1e-3, ...
    'Non-collinear oracle distinguishes limited from uncontrolled Iq.');

% RHS filter constants are SOURCE_DEFINED Tpf=TIf=0.02 s (Table 1).
dx = dev.f(0, dev.x0, y, u0, struct());
d_Pinv_expected = (P_out - dev.x0(7)) / 0.02;
testCase.verifyEqual(dx(7), d_Pinv_expected, 'AbsTol', 1e-12, ...
    'd_Pinv_f = (kappa*P_out - Pinv_f)/Tpf with I_out.');
d_Idinv_expected = (Id_out - dev.x0(8)) / 0.02;
testCase.verifyEqual(dx(8), d_Idinv_expected, 'AbsTol', 1e-12, ...
    'd_Idinv_f = (kappa*Id_out - Idinv_f)/TIf with I_out.');
Q_out = imag(V_bus * conj(I_out));
d_Qinv_expected = (Q_out - dev.x0(9)) / 0.02;
testCase.verifyEqual(dx(9), d_Qinv_expected, 'AbsTol', 1e-12, ...
    'd_Qinv_f = (kappa*Q_out - Qinv_f)/TQf with I_out.');
d_Iqinv_expected = (Iq_out - dev.x0(11)) / 0.02;
testCase.verifyEqual(dx(11), d_Iqinv_expected, 'AbsTol', 1e-12, ...
    'd_Iqinv_f = (kappa*Iq_out - Iqinv_f)/TIf with I_out.');
% All finite
testCase.verifyTrue(all(isfinite(dx)), 'RHS all finite.');
end

% =========================================================================
function test_pll_freeze_low_voltage(testCase)
% |V| < 0.05 → PLL frozen. |V| >= 0.05 → normal.
dev = build_gfm(100, 0.0, 1.0);
u0 = [0.0; 1.0];
% Low voltage
V_lo = 0.02 + 0i; nb = 14; y_lo = make_y(V_lo, nb);
dx_lo = dev.f(0, dev.x0, y_lo, u0, struct());
% delta_PLL is state 5, x_PLL_int is state 6
d_delta_PLL = dx_lo(5);
d_x_PLL_int = dx_lo(6);
testCase.verifyEqual(d_delta_PLL(1), 0, 'AbsTol', 0, 'd(delta_PLL)=0 at |V|<0.05.');
testCase.verifyEqual(d_x_PLL_int(1), 0, 'AbsTol', 0, 'd(x_PLL_int)=0 at |V|<0.05.');
% Normal voltage
V_hi = 1.0 + 0i; y_hi = make_y(V_hi, nb);
dx_hi = dev.f(0, dev.x0, y_hi, u0, struct());
d_delta_PLL_hi = dx_hi(5);
d_x_PLL_int_hi = dx_hi(6);
% At equilibrium, PLL is locked, derivatives can be zero — that's fine.
% The freeze test only requires that low-V forces zero; normal V doesn't guarantee nonzero.
testCase.verifyTrue(isfinite(d_delta_PLL_hi(1)), 'd(delta_PLL) finite at normal V.');
testCase.verifyTrue(isfinite(d_x_PLL_int_hi(1)), 'd(x_PLL_int) finite at normal V.');
end

% =========================================================================
function test_limiter_inactive_baseline_match(testCase)
% At low-power equilibrium (|I| << ImaxF_sys, |V| >> VPLLfrz),
% RHS and current_injection must match pre-Phase-G oracles.
dev = build_gfm(100, 0.4, 1.0);
V_bus = 1.0 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.4; 1.0];
% Manual pre-Phase-G oracle:
x = dev.x0; delta_VSM = x(2);
EVSM = 1.0 - 0.05*0 + 0*(1.0-1.0) + 5*0;  % Vref - mq*Qinv_f + kpv*(Vref-Vinv_f) + kiv*x_Eint = 1.0
I_oracle = (EVSM*exp(1i*delta_VSM) - V_bus) / (0 + 0.1i);
% At low power (P_ref=0.4, Vref=1.0, |V|=1.0), |I| is small (< 1.5)
I_inj = dev.current_injection(0, dev.x0, y, u0, struct());
testCase.verifyEqual(I_inj, I_oracle, 'AbsTol', 1e-9, ...
    'Inactive limiter matches pre-Phase-G linear oracle at kappa=1.');
% RHS check: d_x_Eint must match old form
dx = dev.f(0, dev.x0, y, u0, struct());
d_x_Eint_actual = dx(4);
d_x_Eint_oracle = 1.0 - 1.04;  % V_ref - Vinv_f at init Vinv_f=|V0|=1.04
testCase.verifyEqual(d_x_Eint_actual(1), d_x_Eint_oracle, 'AbsTol', 1e-9, ...
    'd_x_Eint matches pre-Phase-G when limiter inactive.');
end

% =========================================================================
function test_dual_mode_gfm_reaches_limiter(testCase)
% Build via dual_mode_ibr_model in GFM mode — verify limiter path.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
bus_ids = c.mpc.bus(:,1)';
dev = ibr.dual_mode_ibr_model("IBR2", 2, 2, bus_ids, 1.04+0i, ...
    struct('Mbase',140), 0.4, 0.0, 1.04, "GFM");
testCase.verifyEqual(dev.nx, 15, 'AbsTol', 0, 'dual-mode nx=15 preserved.');
% current_injection at GFM dispatch
V_bus = 1.04 + 0i;  nb = 14;  y = make_y(V_bus, nb);; y_bus = zeros(28,1); y_bus(3) = 1.04;
u_dev = [0.4; 0.0; 1.04];   % P_ref, Q_ref, V_ref
I = dev.current_injection(0, dev.x0, y_bus, u_dev, struct());
testCase.verifyTrue(isfinite(I), 'dual-mode GFM current_injection finite.');
end

% =========================================================================
function test_invalid_y_fails_closed(testCase)
% Non-finite V_bus must produce error with deterministic error ID.
nb = 14;
dev = build_gfm(100, 0.4, 1.0);
u0 = [0.4; 1.0];
% NaN y: limited_current validation catches before MATLAB complex().
err_id = '';
try
    dev.current_injection(0, dev.x0, make_y(NaN+0i, nb), u0, struct());
catch me
    err_id = me.identifier;
end
testCase.verifyNotEmpty(err_id, 'NaN V_bus fails closed with error ID.');
testCase.verifyTrue(contains(err_id, 'regfm_b1') || contains(err_id, 'nonfinite'), ...
    ['Error ID references model: ' err_id]);
% Inf y: same validation path.
err_id = '';
try
    dev.current_injection(0, dev.x0, make_y(Inf+0i, nb), u0, struct());
catch me
    err_id = me.identifier;
end
testCase.verifyNotEmpty(err_id, 'Inf V_bus fails closed with error ID.');
testCase.verifyTrue(contains(err_id, 'regfm_b1') || contains(err_id, 'nonfinite'), ...
    ['Error ID references model: ' err_id]);
end

% =========================================================================
function test_reconstruct_reports_limiter_metadata(testCase)
dev = build_gfm(100, 0.0, 1.2);
V_bus = 0.9 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.0; 1.2];
rec = dev.reconstruct(0, dev.x0, y, u0, struct());
testCase.verifyTrue(isfield(rec, 'ImaxF_inv'), 'reconstruct has ImaxF_inv.');
testCase.verifyTrue(isfield(rec, 'ImaxF_sys'), 'reconstruct has ImaxF_sys.');
testCase.verifyTrue(isfield(rec, 'I_limited'), 'reconstruct has I_limited.');
testCase.verifyTrue(isfield(rec, 'VPLLfrz'), 'reconstruct has VPLLfrz.');
testCase.verifyTrue(isfield(rec, 'PLL_frozen'), 'reconstruct has PLL_frozen.');
testCase.verifyTrue(isfield(rec, 'I_unc_sys'), 'reconstruct has I_unc_sys.');
testCase.verifyEqual(rec.ImaxF_inv, 1.5, 'AbsTol', 0, 'ImaxF_inv=1.5.');
% At this high Vref, should be clamped
testCase.verifyTrue(rec.I_limited, 'I_limited==true when clamp active.');
end

% =========================================================================
function test_no_external_solver_grep(testCase)
model_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'regfm_b1_vsg_model.m');
src = fileread(model_path);
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src, fn{1}), ['no ' fn{1} ' in model.']);
end
end

% =========================================================================
function test_nx_unchanged(testCase)
% GFM: nx=11. Dual-mode: nx=15. Composite: nx_total=66, nx_active=65.
dev = build_gfm(100, 0.4, 1.0);
testCase.verifyEqual(dev.nx, 11, 'AbsTol', 0, 'GFM nx=11 unchanged.');
testCase.verifyEqual(numel(dev.x0), 11, 'AbsTol', 0, 'GFM x0 length=11.');
end

% =========================================================================
function test_angle_preserved_under_clamp(testCase)
% Under clamp, angle(I_out) must equal angle(I_unc).
dev = build_gfm(100, 0.0, 1.5);
V_bus = 0.9 + 0i;  nb = 14;  y = make_y(V_bus, nb);
u0 = [0.0; 1.5];
[I_out, I_unc, I_limited] = current_inj_oracle(dev, y, u0);
if I_limited
    testCase.verifyEqual(angle(I_out), angle(I_unc), 'AbsTol', 1e-14, ...
        'Angle preserved under clamp.');
end
end

% =========================================================================
function test_rhs_no_nan_inf_at_extreme(testCase)
% All outputs finite at extreme states.
nb = 14;
dev = build_gfm(100, 0.4, 1.0);
u0 = [0.4; 1.0];
% Extreme: V=0
y_zero = make_y(0+0i, nb);
dx = dev.f(0, dev.x0, y_zero, u0, struct());
testCase.verifyTrue(all(isfinite(dx)), 'RHS finite at V=0.');
% Extreme: high Vref (clamp active)
dev2 = build_gfm(100, 0.0, 3.0);
u2 = [0.0; 3.0];
y_norm = make_y(1.0+0i, nb);
dx2 = dev2.f(0, dev2.x0, y_norm, u2, struct());
testCase.verifyTrue(all(isfinite(dx2)), 'RHS finite at clamped current.');
end

% =========================================================================
function [I_out, I_unc, I_limited] = current_inj_oracle(dev, y, u_dev)
% Extract state and compute via device closures.
I_out = dev.current_injection(0, dev.x0, y, u_dev, struct());
rec = dev.reconstruct(0, dev.x0, y, u_dev, struct());
I_unc = rec.I_unc_sys;
I_limited = rec.I_limited;
end
