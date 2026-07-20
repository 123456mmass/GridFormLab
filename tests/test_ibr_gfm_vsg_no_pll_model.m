function tests = test_ibr_gfm_vsg_no_pll_model()
%TEST_IBR_GFM_VSG_NO_PLL_MODEL  Constructor/ABI/no-PLL structural tests.
%   Verifies the 4-state GFM-VSG-no-PLL device: constructor, mapping, dims,
%   bases, current/power identity, equilibrium inversion, fail-closed, and
%   behavioral no-PLL falsification (angle-derivative structure, terminal-
%   angle independence, rigid-frame covariance).
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [dev,x,V,P,Q,V_ref] = default_fixture()
V = 1.0+0i; P = 0.40; Q = 0.10;
X_L = 0.15; m_q = 0.05; Q_ref = 0.0; kappa = 1.0;
I_sys = conj((P+1i*Q)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
V_ref = abs(E_internal) + m_q*(kappa*Q - Q_ref);
dev = ibr.gfm_vsg_no_pll_model("GFM_TEST",1,1,1,V,struct(),P,V_ref);
x = dev.equilibrium_initialize(V,P,Q,struct());
end

% =========================================================================
function test_constructor_identity(testCase)
[dev,~,~] = default_fixture();
testCase.verifyEqual(dev.nx,4);
testCase.verifyEqual(dev.nu,2);
testCase.verifyEqual(dev.device_type,'ibr_gfm_vsg_no_pll');
testCase.verifyEqual(dev.mode,'GFM');
testCase.verifyEqual(dev.state_names, ...
    {'delta_vsm','delta_omega_vsm','P_f','Q_f'});
testCase.verifyEqual(dev.input_names,{'P_ref','V_ref'});
testCase.verifyEqual(dev.bus_position,1);
testCase.verifyEqual(dev.bus_id,1);
testCase.verifyEqual(dev.bus_ids,1);
end

% =========================================================================
function test_active_state_indices_runtime(testCase)
[dev,~] = default_fixture();
active = dev.active_state_indices;
if isa(active,'function_handle')
    active = active(struct());
end
testCase.verifyEqual(active,1:dev.nx);
end

% =========================================================================
function test_equilibrium_residual_zero(testCase)
[dev,x,V,P,Q] = default_fixture();
y = [real(V);imag(V)];
f = dev.f(0,x,y,dev.u0,struct());
testCase.verifyLessThan(norm(f,inf),1e-9);
% delta_omega_vsm = 0 at equilibrium.
testCase.verifyEqual(x(2),0.0,'AbsTol',1e-12);
% P_f = kappa*P, Q_f = kappa*Q (kappa=1 for source-study base).
testCase.verifyEqual(x(3),P,'AbsTol',1e-9);
testCase.verifyEqual(x(4),Q,'AbsTol',1e-9);
end

% =========================================================================
function test_power_identity(testCase)
[dev,x,V,P,Q] = default_fixture();
y = [real(V);imag(V)];
I = dev.current_injection(0,x,y,dev.u0,struct());
S = V*conj(I);
testCase.verifyEqual(real(S),P,'AbsTol',1e-9);
testCase.verifyEqual(imag(S),Q,'AbsTol',1e-9);
Pe = dev.electrical_power(0,x,y,dev.u0,struct());
testCase.verifyEqual(Pe,real(S),'AbsTol',1e-9);
end

% =========================================================================
function test_kappa_boundary_conversion(testCase)
% kappa = Sbase/Mbase; verify current_injection returns system base.
V = 1.0+0i; P = 0.40; Q = 0.10;
X_L = 0.15; m_q = 0.05; Q_ref = 0.0;
Sbase = 100.0; Mbase = 50.0;   % kappa = 2
kappa = Sbase/Mbase;
I_sys = conj((P+1i*Q)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
V_ref = abs(E_internal) + m_q*(kappa*Q - Q_ref);
params = struct('Sbase',Sbase,'Mbase',Mbase);
dev = ibr.gfm_vsg_no_pll_model("GFM_KAPPA",1,1,1,V,params,P,V_ref);
x = dev.equilibrium_initialize(V,P,Q,struct());
y = [real(V);imag(V)];
I = dev.current_injection(0,x,y,dev.u0,struct());
S = V*conj(I);
% System-base power must reproduce requested P,Q.
testCase.verifyEqual(real(S),P,'AbsTol',1e-9);
testCase.verifyEqual(imag(S),Q,'AbsTol',1e-9);
% Internal inverter-base current is kappa times system current.
rc = dev.reconstruct(0,x,y,dev.u0,struct());
testCase.verifyEqual(rc.I_inv, kappa*rc.I_sys, 'AbsTol', 1e-9);
end

% =========================================================================
function test_no_pll_state_names(testCase)
[dev,~] = default_fixture();
names = dev.state_names;
testCase.verifyFalse(any(strcmp(names,'delta_PLL')));
testCase.verifyFalse(any(strcmp(names,'xi_PLL')));
testCase.verifyFalse(any(strcmp(names,'x_PLL_int')));
end

% =========================================================================
function test_no_pll_param_scan(testCase)
% provenance.params must not carry PLL/voltage-PI/limiter fields.
[dev,~] = default_fixture();
p = dev.provenance.params;
forbidden = {'kp_PLL','ki_PLL','VPLLfrz','k_pv','k_iv','xi_E','V_f', ...
    'VFlag','QVFlag','ImaxF','Emax','Emin','kpqmax','Kiqmax'};
for k = 1:numel(forbidden)
    testCase.verifyFalse(isfield(p,forbidden{k}), ...
        ['provenance.params must not carry ' forbidden{k}]);
end
end

% =========================================================================
function test_rejects_unsupported_options(testCase)
V = 1.0+0i; P = 0.40;
params = struct('gfm_no_pll',struct('kp_PLL',0.265));
testCase.verifyError(@() ibr.gfm_vsg_no_pll_model("BAD",1,1,1,V,params,P,1.0), ...
    'ibr:gfm_vsg_no_pll_model:unsupportedOption');
end

% =========================================================================
function test_bus_mapping_mismatch(testCase)
V = 1.0+0i; P = 0.40;
testCase.verifyError(@() ibr.gfm_vsg_no_pll_model("BAD",2,1,[1 2],V,struct(),P,1.0), ...
    'ibr:gfm_vsg_no_pll_model:busMappingMismatch');
end

% =========================================================================
function test_infeasible_vref_fail_closed(testCase)
% A V_ref inconsistent with (V0,P_ref) must fail closed at construction
% (no consistent Q exists for the frozen Q-V droop voltage law).
V = 1.0+0i; P = 0.40;
testCase.verifyError(@() ibr.gfm_vsg_no_pll_model("GFM_BAD",1,1,1,V,struct(),P,1.5), ...
    'ibr:gfm_vsg_no_pll_model:infeasibleVref');
end

% =========================================================================
function test_infeasible_equilibrium_voltage_law(testCase)
% equilibrium_initialize must fail closed when (V,P,Q,V_ref) is inconsistent.
% Construct a device with a consistent V_ref at (V,P,Q=0), then call
% equilibrium_initialize with a Q that breaks the voltage law.
V = 1.0+0i; P = 0.40; Q = 0.10;
X_L = 0.15; m_q = 0.05; Q_ref = 0.0; kappa = 1.0;
I_sys = conj((P+1i*Q)/V);
E_internal = V + 1i*X_L*kappa*I_sys;
V_ref = abs(E_internal) + m_q*(kappa*Q - Q_ref);
dev = ibr.gfm_vsg_no_pll_model("GFM_OK",1,1,1,V,struct(),P,V_ref);
% Now request a different Q that is inconsistent with this V_ref.
testCase.verifyError(@() dev.equilibrium_initialize(V,P,0.5,struct()), ...
    'ibr:gfm_vsg_no_pll_model:infeasibleEquilibriumVoltageLaw');
end

% =========================================================================
function test_angle_derivative_structure(testCase)
% Behavioral no-PLL: dot(delta_vsm) = omega_base*delta_omega_vsm only.
% d(dot(delta_vsm))/d(y) = 0; d(dot(delta_vsm))/d(delta_vsm) = 0;
% d(dot(delta_vsm))/d(delta_omega_vsm) = omega_base.
[dev,x,V] = default_fixture();
y = [real(V);imag(V)];
u = dev.u0; ec = struct();
f0 = dev.f(0,x,y,u,ec);
h = 1e-6;
% Perturb y (terminal voltage real/imag): dot(delta_vsm) must not change.
yp = y; yp(1) = yp(1)+h;
fp_y = dev.f(0,x,yp,u,ec);
testCase.verifyLessThan(abs(fp_y(1)-f0(1)),1e-9);
% Perturb delta_vsm: dot(delta_vsm) must not change.
xp = x; xp(1) = xp(1)+h;
fp_d = dev.f(0,xp,y,u,ec);
testCase.verifyLessThan(abs(fp_d(1)-f0(1)),1e-9);
% Perturb delta_omega_vsm: dot(delta_vsm) must change by omega_base*h.
xp2 = x; xp2(2) = xp2(2)+h;
fp_w = dev.f(0,xp2,y,u,ec);
omega_base = dev.provenance.params.omega_base;
testCase.verifyEqual((fp_w(1)-f0(1))/h, omega_base, 'RelTol', 1e-4);
end

% =========================================================================
function test_terminal_angle_independence(testCase)
% Perturb angle(V) with rotor states fixed: dot(delta_vsm) unchanged.
[dev,x,V] = default_fixture();
u = dev.u0; ec = struct();
y = [real(V);imag(V)];
f0 = dev.f(0,x,y,u,ec);
dphi = 0.05;
Vp = V*exp(1i*dphi);
yp = [real(Vp);imag(Vp)];
fp = dev.f(0,x,yp,u,ec);
testCase.verifyLessThan(abs(fp(1)-f0(1)),1e-9);
end

% =========================================================================
function test_rigid_frame_covariance(testCase)
% Rotate V and delta_vsm by the same constant angle: P, Q, rotor RHS invariant.
[dev,x,V] = default_fixture();
u = dev.u0; ec = struct();
y = [real(V);imag(V)];
f0 = dev.f(0,x,y,u,ec);
I0 = dev.current_injection(0,x,y,u,ec);
S0 = V*conj(I0);
dphi = 0.07;
Vp = V*exp(1i*dphi);
yp = [real(Vp);imag(Vp)];
xp = x; xp(1) = xp(1)+dphi;
fp = dev.f(0,xp,yp,u,ec);
Ip = dev.current_injection(0,xp,yp,u,ec);
Sp = Vp*conj(Ip);
% Rotor RHS (swing, filters) invariant under rigid rotation.
testCase.verifyEqual(fp(2:4),f0(2:4),'AbsTol',1e-9);
% P, Q invariant.
testCase.verifyEqual(real(Sp),real(S0),'AbsTol',1e-9);
testCase.verifyEqual(imag(Sp),imag(S0),'AbsTol',1e-9);
end

% =========================================================================
function test_provenance_fields(testCase)
[dev,~] = default_fixture();
req = {'model','source','source_classification','state_register', ...
    'parameter_manifest','control_option','pu_base_contract', ...
    'low_voltage_policy','params','readiness','angle_contract'};
for k = 1:numel(req)
    testCase.verifyTrue(isfield(dev.provenance,req{k}), ...
        ['provenance missing ' req{k}]);
end
testCase.verifyTrue(contains(dev.provenance.source_classification,'NO PLL'));
testCase.verifyTrue(contains(dev.provenance.angle_contract,'never from angle(V)'));
end
