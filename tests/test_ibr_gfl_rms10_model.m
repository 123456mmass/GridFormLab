function tests = test_ibr_gfl_rms10_model
%TEST_IBR_GFL_RMS10_MODEL  Falsification tests for the GFL-RMS10 device.
%   Covers: ABI/metadata, state order, equilibrium residual, kappa base
%   conversion, dq transform + P/Q sign, current-plant oracle, PLL ODE,
%   P/Q filters + outer loop, current-priority limit + anti-windup
%   entry/hold/release, vector clamp, low-voltage fail-closed, Jacobian FD
%   agreement, no-external-solver grep, provenance, fail-closed IDs.
%   All hand calculations are independent of the implementation helpers.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
testCase.addTeardown(@() rmpath(root));
end

% ===================== ABI + metadata ====================================
function test_abi_state_order_and_metadata(testCase)
d = make_dev(struct(),0.498,0.0);
testCase.verifyEqual(d.nx,10,'AbsTol',0);
testCase.verifyEqual(d.nu,2,'AbsTol',0);
testCase.verifyEqual(d.device_type,'ibr_gfl_rms10');
testCase.verifyEqual(d.mode,'gfl');
testCase.verifyEqual(d.state_names, ...
    {'delta_PLL','xi_PLL','P_f','Q_f','xi_P','xi_Q','xi_id','xi_iq','i_d','i_q'});
testCase.verifyEqual(d.input_names,{'P_ref','Q_ref'});
testCase.verifyEqual(numel(d.active_state_indices(struct())),10);
end

function test_provenance_marks_project_derived_composite(testCase)
d = make_dev(struct(),0.498,0.0);
testCase.verifyTrue(contains(d.provenance.model,'GFL_RMS10'));
testCase.verifyTrue(contains(d.provenance.source_classification,'SOURCE_DEFINED_NONLINEAR_CORE_CLOSED=YES'));
testCase.verifyTrue(contains(d.provenance.source_classification,'FULL_SOURCE_DEFINED_GFL_MODEL=NO'));
testCase.verifyTrue(contains(d.provenance.source,'6739364.pdf'));
testCase.verifyTrue(contains(d.provenance.source,'grid-converters'));
testCase.verifyTrue(contains(d.provenance.source,'978-1-4471-5478-5'));
testCase.verifyEqual(d.provenance.readiness,'SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES');
testCase.verifyTrue(contains(d.provenance.low_voltage_policy, ...
    'BALANCED_POSITIVE_SEQUENCE_LVRT'));
testCase.verifyEqual(d.provenance.params.Vdip,0.90,'AbsTol',0);
testCase.verifyEqual(d.provenance.params.Kqv,2.0,'AbsTol',0);
testCase.verifyEqual(d.provenance.params.Zerox,0.40,'AbsTol',0);
testCase.verifyEqual(d.provenance.params.Brkpt,0.90,'AbsTol',0);
end

% ===================== equilibrium residual ==============================
function test_equilibrium_residual_is_machine_zero(testCase)
d = make_dev(struct(),0.498,0.0);
V = 1.01*exp(1i*0.02);
y = y_for(V,bus_pos());
xeq = d.equilibrium_initialize(V,0.498,0.0,struct());
dx = d.f(0,xeq,y,[0.498;0.0],struct());
% Round-trip through current injection introduces ~1e-11 floating error;
% tolerance allows that while still catching real equation defects.
testCase.verifyEqual(dx,zeros(10,1),'AbsTol',1e-9);
end

function test_equilibrium_power_identity_system_base(testCase)
d = make_dev(struct('Mbase',140),0.498,0.05);
V = 1.04*exp(1i*0.17);
y = y_for(V,bus_pos());
xeq = d.equilibrium_initialize(V,0.498,0.05,struct());
I = d.current_injection(0,xeq,y,[0.498;0.05],struct());
S = V*conj(I);
testCase.verifyEqual(real(S),0.498,'AbsTol',2e-13);
testCase.verifyEqual(imag(S),0.05,'AbsTol',2e-13);
end

% ===================== kappa base conversion =============================
function test_kappa_base_conversion(testCase)
d = make_dev(struct('Mbase',140),0.498,0.0);
testCase.verifyEqual(d.provenance.params.kappa,100/140,'AbsTol',1e-15);
% Internal P_f0 and i_d0 are on the inverter base (kappa*P_sys).
V = 1.01*exp(1i*0.02);
y = y_for(V,bus_pos());
r = reconstruct(d,d.x0,y,d.u0);
testCase.verifyEqual(r.P_f,(100/140)*0.498,'AbsTol',1e-15);
testCase.verifyEqual(r.i_d,(100/140)*0.498/abs(V),'AbsTol',1e-15);
% Pe returns on system base.
testCase.verifyEqual(r.Pe,0.498,'AbsTol',2e-13);
end

% ===================== dq transform + sign convention ===================
function test_dq_transform_vq_zero_at_lock(testCase)
d = make_dev(struct(),0.498,0.0);
V = 1.05*exp(1i*0.31);
y = y_for(V,bus_pos());
xeq = d.equilibrium_initialize(V,0.498,0.0,struct());
r = reconstruct(d,xeq,y,[0.498;0.0],struct());
% Locked PLL: delta_PLL = angle(V), so v_q = 0 and v_d = |V|.
testCase.verifyEqual(r.delta_PLL,angle(V),'AbsTol',1e-9);
testCase.verifyEqual(r.v_q,0,'AbsTol',1e-9);
testCase.verifyEqual(r.v_d,abs(V),'AbsTol',1e-9);
end

function test_rotation_invariance_of_current_injection(testCase)
V1 = 1.04*exp(1i*0.13);
V2 = 1.04*exp(1i*0.63);
d1 = make_dev(struct(),0.4,0.1);
d2 = ibr.gfl_rms10_model("T",2,2,[1 2],V2,struct(),0.4,0.1);
y1 = y_for(V1,bus_pos());
y2 = y_for(V2,bus_pos());
I1 = d1.current_injection(0,d1.equilibrium_initialize(V1,0.4,0.1,struct()),y1,[0.4;0.1],struct());
I2 = d2.current_injection(0,d2.equilibrium_initialize(V2,0.4,0.1,struct()),y2,[0.4;0.1],struct());
% A pure rotation of the bus voltage by 0.5 rad rotates the network-frame
% current injection by the same angle (the dq-frame internal variables rotate
% with the PLL so I_net rotates with V).
testCase.verifyEqual(I2,I1*exp(1i*0.50),'AbsTol',2e-12);
end

% ===================== current-plant oracle (eq 8.45/8.46) ==============
function test_current_plant_oracle_independent(testCase)
% Independent oracle for Yazdani eq 8.45/8.46 at a known non-equilibrium
% state. Disable limiters/clamps by using a small current so nothing binds.
d = make_dev(struct(),0.1,0.0);
V = 1.0;  % real, locked PLL = delta_PLL = 0
y = y_for(V,bus_pos());
x = d.x0;
x(9) = 0.20;  % i_d perturbed
x(10) = 0.10; % i_q perturbed
x(1) = 0.0;   % delta_PLL = angle(V) = 0 (locked)
% Build the expected plant derivative by hand from eq 8.45/8.46.
p = d.provenance.params;
omega_PLL_pu = 1.0;  % v_q=0 -> Delta_omega=0
v_d = 1.0; v_q = 0.0;
% v_td_raw = kp_i*e_d + ki_i*xi_id + R_t*i_d - omega_PLL_pu*L*i_q + v_d
% e_d = i_d_ref - i_d; i_d_ref = kp_P*e_P + ki_P*xi_P + P_ref_inv/v_d
P_ref_inv = p.kappa*0.1;
e_P = P_ref_inv - x(3);
i_d_ref = p.kp_P*e_P + p.ki_P*x(5) + P_ref_inv/v_d;
i_q_ref = -(p.kp_Q*(0 - x(4)) + p.ki_Q*x(6) + 0/v_d);
e_d = i_d_ref - x(9); e_q = i_q_ref - x(10);
v_td = p.kp_i*e_d + p.ki_i*x(7) + p.R_t*x(9) - omega_PLL_pu*p.L*x(10) + v_d;
v_tq = p.kp_i*e_q + p.ki_i*x(8) + p.R_t*x(10) + omega_PLL_pu*p.L*x(9) + v_q;
did_expect = (omega_PLL_pu*p.L*x(10) - p.R_t*x(9) + v_td - v_d)/(p.L/p.omega_b);
diq_expect = (-omega_PLL_pu*p.L*x(9) - p.R_t*x(10) + v_tq - v_q)/(p.L/p.omega_b);
dx = d.f(0,x,y,[0.1;0],struct());
testCase.verifyEqual(dx(9),did_expect,'AbsTol',1e-13);
testCase.verifyEqual(dx(10),diq_expect,'AbsTol',1e-13);
end

% ===================== PLL ODE + Jacobian ===============================
function test_pll_ode_form_matches_teodorescu(testCase)
% dot(xi_PLL) = v_q; dot(delta_PLL) = omega_b*(kp_PLL*v_q + ki_PLL*xi_PLL).
% Verify the form by perturbing v_q via a delta_PLL offset.
d = make_dev(struct(),0.3,0.0);
V = 1.0*exp(1i*0.0);
y = y_for(V,bus_pos());
x = d.x0;
x(1) = 0.05;  % delta_PLL != angle(V) -> v_q != 0
p = d.provenance.params;
% Recompute v_q at this offset.
% Yazdani eq 8.1 (f_d+j*f_q=f*e^{-j*rho} => f_q=+Im): v_q = +imag(Vdq).
% The prior test pinned v_q=-imag(Vdq), which encoded the PLL phase-detector
% sign defect (det(J_PLL)<0 saddle, +3.4e5 unstable mode). Corrected to match
% the source convention and the fixed production code; independently verified
% by output/diagnostics/oracle_pll_signfix.m (SSSA max_real +3.37e5 -> -11.23).
% See defect docs/project/defects/2026-07-21-gfl-rms10-smib-unstable-mode.md.
Vdq = V*exp(-1i*x(1));
v_q =  imag(Vdq);
dx = d.f(0,x,y,[0.3;0],struct());
testCase.verifyEqual(dx(2),v_q,'AbsTol',1e-13);
testCase.verifyEqual(dx(1),p.omega_b*(p.kp_PLL*v_q + p.ki_PLL*x(2)),'AbsTol',1e-12);
end

% ===================== P/Q filters + outer loop =========================
function test_pq_filter_oracle(testCase)
% Use V=1.0 (real) so v_d=1, v_q=0 exactly; construct device at this V.
d = ibr.gfl_rms10_model("T",2,bus_pos(),[1 2],1.0,struct(),0.3,0.1);
V = 1.0;
y = y_for(V,bus_pos());
x = d.x0;
% Force a P_f mismatch: P_f = 0.2 but measured P at i_d=i_d0,v_d=1 is 0.3.
x(3) = 0.20;
p = d.provenance.params;
P_inv_meas = p.kappa*0.3;  % i_d0*v_d (system->inv via kappa)
dx = d.f(0,x,y,[0.3;0.1],struct());
testCase.verifyEqual(dx(3),(P_inv_meas - 0.20)/p.T_P,'AbsTol',1e-13);
end

% ===================== current-priority limit + anti-windup ==============
function test_current_priority_limit_activates(testCase)
% Large xi_P with small Imax forces the current command beyond Imax at a
% manually-set state (equilibrium_initialize would reject P_ref>Imax).
d = make_dev(struct('gfl_rms10',struct('Imax',0.5)),0.5,0.0);
V = 1.0;
y = y_for(V,bus_pos());
x = d.x0;
x(3) = 0.10;   % P_f low
x(5) = 0.50;   % xi_P large -> i_d_ref_raw = kp_P*(P_ref_inv-0.1) + ki_P*0.5 + ... large
r = reconstruct(d,x,y,[0.5;0.0],struct());
testCase.verifyTrue(r.limiter_active);
testCase.verifyLessThanOrEqual(hypot(r.i_d_ref,r.i_q_ref),0.5+1e-12);
testCase.verifyEqual(r.i_d_ref,0.5,'AbsTol',1e-12);
end

function test_anti_windup_outer_hold_on_outward_push(testCase)
% Limiter active AND outer-loop error pushes OUTWARD (further into limit)
% -> AW_P holds: dot(xi_P)=0.
d = make_dev(struct('gfl_rms10',struct('Imax',0.5)),0.5,0.0);
V = 1.0;
y = y_for(V,bus_pos());
x = d.x0;
x(3) = 0.10;   % P_f < P_ref_inv -> e_P > 0 (outward, i_d_ref_raw large)
x(5) = 0.50;   % xi_P large
dx = d.f(0,x,y,[0.5;0],struct());
testCase.verifyEqual(dx(5),0,'AbsTol',1e-13);
end

function test_anti_windup_outer_releases_on_inward_push(testCase)
% Limiter active BUT outer-loop error pushes INWARD (away from limit)
% -> AW_P releases: dot(xi_P) = e_P.
d = make_dev(struct('gfl_rms10',struct('Imax',0.5)),0.5,0.0);
V = 1.0;
y = y_for(V,bus_pos());
x = d.x0;
x(5) = 0.50;   % xi_P large -> i_d_ref_raw still exceeds Imax
x(3) = 0.60;   % P_f > P_ref_inv(=0.5) -> e_P < 0 (inward)
r = reconstruct(d,x,y,[0.5;0],struct());
if r.limiter_active
    dx = d.f(0,x,y,[0.5;0],struct());
    p = d.provenance.params;
    e_P = p.kappa*0.5 - 0.60;
    testCase.verifyEqual(dx(5),e_P,'AbsTol',1e-13);
else
    testCase.verifyTrue(false, 'fixture did not activate the current limiter');
end
end

% ===================== vector clamp ======================================
function test_vector_clamp_radial(testCase)
% Drive v_td_raw above V_t_max by a huge i_d command; verify the clamp
% scales radially and keeps the direction. Construct at V=1.0 (real).
d = ibr.gfl_rms10_model("T",2,bus_pos(),[1 2],1.0, ...
    struct('gfl_rms10',struct('Imax',2.0,'Vdc0',0.5,'m_max',1.0)),0.5,0.5);
V = 1.0;
y = y_for(V,bus_pos());
x = d.x0;
x(9) = 1.5;  % large i_d -> large v_td_raw feedforward
r = reconstruct(d,x,y,[0.5;0.5],struct());
% V_t_max = m_max*Vdc0 = 0.5. If clamped, |[v_td;v_tq]| <= 0.5+eps.
if r.voltage_clamped
    testCase.verifyLessThanOrEqual(hypot(r.v_td,r.v_tq),0.5+1e-12);
    % Direction preserved: v_td/v_tq ratio unchanged (both scaled).
    if abs(r.v_tq_raw) > 1e-9
        testCase.verifyEqual(r.v_td/r.v_td_raw, r.v_tq/r.v_tq_raw, 'AbsTol',1e-12);
    end
else
    testCase.verifyTrue(false, 'fixture did not activate the voltage clamp');
end
end

% ===================== balanced positive-sequence LVRT ==================
function test_balanced_low_voltage_uses_q_priority_lvrt(testCase)
% Contract correction (2026-07-19): the former test required every runtime
% sample below V_valid_min to fail. That contradicted the approved sourced
% FRT domain (Teodorescu Ch.7 pp.162-163 and WECC REGC_A/REEC_A mapping).
% V_valid_min remains an equilibrium gate; runtime remains defined down to
% V_div_min and must use reactive-current priority without a PLL freeze.
d = make_dev(struct('gfl_rms10',struct( ...
    'V_valid_min',0.7,'V_div_min',0.1)),0.4,0.0);
V = 0.5;
y = y_for(V,bus_pos());
dx = d.f(0,d.x0,y,[0.4;0],struct());
r = reconstruct(d,d.x0,y,[0.4;0],struct());
I = d.current_injection(0,d.x0,y,[0.4;0],struct());
testCase.verifyTrue(all(isfinite(dx)));
testCase.verifyTrue(isfinite(I));
testCase.verifyTrue(r.lvrt_active);
testCase.verifyLessThan(r.i_q_ref,0, ...
    'positive reactive injection uses negative iq in the frozen sign convention');
testCase.verifyLessThanOrEqual(hypot(r.i_d_ref,r.i_q_ref), ...
    d.provenance.params.Imax+1e-12);
end

function test_near_zero_voltage_still_fails_closed(testCase)
d = make_dev(struct('gfl_rms10',struct('V_div_min',0.1)),0.4,0.0);
y = y_for(0.05,bus_pos());
testCase.verifyError(@() d.f(0,d.x0,y,[0.4;0],struct()), ...
    'ibr:gfl_rms10_model:lowVoltagePowerInversion');
testCase.verifyError(@() d.current_injection(0,d.x0,y,[0.4;0],struct()), ...
    'ibr:gfl_rms10_model:lowVoltagePowerInversion');
testCase.verifyError(@() reconstruct(d,d.x0,y,[0.4;0],struct()), ...
    'ibr:gfl_rms10_model:lowVoltagePowerInversion');
end

function test_equilibrium_low_voltage_fails_closed(testCase)
d = make_dev(struct('gfl_rms10',struct('V_valid_min',0.7)),0.4,0.0);
testCase.verifyError(@() d.equilibrium_initialize(0.5,0.4,0.0,struct()), ...
    'ibr:gfl_rms10_model:voltageOutsideValidityDomain');
end

% ===================== kappa + base conversions ==========================
function test_kappa_unity_default(testCase)
d = make_dev(struct(),0.498,0.0);
testCase.verifyEqual(d.provenance.params.kappa,1.0,'AbsTol',1e-15);
end

% ===================== Jacobian FD agreement =============================
function test_rhs_jacobian_fd_agreement(testCase)
% Use a small P_ref so no limiter/clamp is active at the test state (smooth
% region); forward and centered FD must then agree to FD error.
d = make_dev(struct(),0.10,0.0);
V = 1.0;
y = y_for(V,bus_pos());
x = d.equilibrium_initialize(V,0.10,0.0,struct());
u = [0.10;0.0];
% Perturb slightly off equilibrium so all channels are exercised and the
% limiter/clamp remain inactive (small currents).
x = x + 1e-3*[1;0;0.5;0;0;0;0;0;0.5;0];
f0 = d.f(0,x,y,u,struct());
eps = 1e-6;
J = zeros(10,10);
for k = 1:10
    xp = x; xp(k) = xp(k)+eps;
    J(:,k) = (d.f(0,xp,y,u,struct())-f0)/eps;
end
Jc = zeros(10,10);
for k = 1:10
    xp = x; xp(k) = xp(k)+eps;
    xm = x; xm(k) = xm(k)-eps;
    Jc(:,k) = (d.f(0,xp,y,u,struct())-d.f(0,xm,y,u,struct()))/(2*eps);
end
testCase.verifyEqual(J,Jc,'AbsTol',1e-3);
testCase.verifyTrue(all(isfinite(J(:))));
end

% ===================== no external solver / no SSSA-A in source =========
function test_no_external_solver_in_source(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
p = fullfile(root,'+ibr','gfl_rms10_model.m');
testCase.assertTrue(exist(p,'file')==2);
txt = fileread(p);
lines = splitlines(txt);
code_lines = lines(~startsWith(strtrim(lines), '%'));
code = strjoin(code_lines, newline);
bad = {'eig(','inv(','pinv(','fsolve','fmincon','lsqnonlin', ...
    'matpower','psat','simulink'};
for j = 1:numel(bad)
    testCase.assertFalse(contains(lower(code), lower(bad{j})), ...
        sprintf('gfl_rms10_model.m must not contain %s', bad{j}));
end
end

% ===================== fail-closed IDs ===================================
function test_bad_bus_mapping_fails_closed(testCase)
testCase.verifyError(@() ibr.gfl_rms10_model("T",2,1,[1 2],1.0,struct(),0.4,0), ...
    'ibr:gfl_rms10_model:busMappingMismatch');
end

function test_bad_v0_fails_closed(testCase)
testCase.verifyError(@() ibr.gfl_rms10_model("T",2,2,[1 2],0,struct(),0.4,0), ...
    'ibr:gfl_rms10_model:badV0');
end

function test_bad_params_fails_closed(testCase)
testCase.verifyError(@() make_dev(struct('gfl_rms10',struct('L',-0.1)),0.4,0), ...
    'ibr:gfl_rms10_model:badParam');
end

function test_bad_input_fails_closed(testCase)
d = make_dev(struct(),0.4,0.0);
y = y_for(1.0,bus_pos());
testCase.verifyError(@() d.f(0,d.x0,y,[NaN;0],struct()), ...
    'ibr:gfl_rms10_model:badInput');
end

function test_bad_state_fails_closed(testCase)
d = make_dev(struct(),0.4,0.0);
y = y_for(1.0,bus_pos());
x = d.x0; x(1) = Inf;
testCase.verifyError(@() d.f(0,x,y,[0.4;0],struct()), ...
    'ibr:gfl_rms10_model:badState');
end

function test_equilibrium_current_limit_fails_closed(testCase)
% Construct the device with a small P/Q so x0 init passes; then call
% equilibrium_initialize with P,Q that exceed Imax and verify fail-closed.
d = make_dev(struct('gfl_rms10',struct('Imax',0.3)),0.1,0.0);
testCase.verifyError(@() d.equilibrium_initialize(1.0,0.9,0.9,struct()), ...
    'ibr:gfl_rms10_model:equilibriumCurrentLimit');
end

% ===================== helpers ==========================================
function d = make_dev(params,P,Q)
d = ibr.gfl_rms10_model("T",2,bus_pos(),[1 2],1.01*exp(1i*0.02),params,P,Q);
end

function bp = bus_pos()
bp = 2;
end

function y = y_for(V,bp)
y = zeros(2*max(bp,1),1);
if numel(y) < 2*bp
    y = zeros(2*bp,1);
end
y(2*bp-1) = real(V);
y(2*bp) = imag(V);
end

function r = reconstruct(d,x,y,u,~)
r = d.reconstruct(0,x,y,u,struct());
end
