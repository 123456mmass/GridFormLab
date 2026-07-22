function tests = test_ibr_gfm_reduced6()
%TEST_IBR_GFM_REDUCED6  6-state reduced grid-forming VSG (EECON49-P4) SMIB.
%   One reduced GFM VSG model (blocks IBR+VSG+GFM, 2 states each, NO PLL)
%   connected to an ideal algebraic infinite bus. Verifies ABI/state order, the
%   no-PLL construction guard, closed-form equilibrium (residual ~0), the
%   P+jQ=V*conj(I) identity, SSSA finiteness/Schur consistency and asymptotic
%   stability, the presence of the expected underdamped electromechanical swing
%   complex mode, the swing-only (no-PLL) angle contract, FD-step convergence,
%   and event-free TDS drift.
tests = functiontests(localfunctions());
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [dev,x,V,u,E,Z,s] = gfm6_fixture()
c = cases.case_ibr_smib_gfm_reduced6();
m = c.smib_verification;
V = m.V_terminal; Z = m.Z_line_pu;
dev = ibr.gfm_reduced6_model(char(m.device_id),1,1,1,V,struct(), ...
    m.P_terminal_pu, m.Q_terminal_pu);
x = dev.equilibrium_initialize(V,m.P_terminal_pu,m.Q_terminal_pu,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V - Z*I;
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
end

% =========================================================================
function test_abi_state_order_and_metadata(testCase)
dev = gfm6_fixture();
testCase.verifyEqual(dev.nx,6);
testCase.verifyEqual(dev.nu,2);
testCase.verifyEqual(dev.device_type,'ibr_gfm_reduced6');
testCase.verifyEqual(dev.state_names,{'i_d','i_q','omega','delta','E','xi_V'});
testCase.verifyEqual(dev.input_names,{'P_ref','Q_ref'});
testCase.verifyTrue(isfield(dev.provenance,'readiness'));
end

% =========================================================================
function test_no_pll_guard_and_inventory(testCase)
mk = @(opt) ibr.gfm_reduced6_model('T',1,1,1,1.0,struct('gfm_reduced6',opt),0.4,0.1);
for fld = {'kp_PLL','ki_PLL','delta_PLL','x_gov','Imax'}
    o = struct(); o.(fld{1}) = 1.0;
    testCase.verifyError(@() mk(o),'ibr:gfm_reduced6_model:unsupportedOption');
end
dev = gfm6_fixture();
testCase.verifyFalse(any(contains(lower(dev.state_names),'pll')));
end

% =========================================================================
function test_equilibrium_and_power_identity(testCase)
[dev,x,V,u,~,~,s] = gfm6_fixture();
testCase.verifyLessThan(norm(s.f0,inf),1e-8);
testCase.verifyLessThan(norm(s.g0,inf),1e-10);
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
S = V*conj(I);
testCase.verifyEqual(real(S),0.40,'AbsTol',1e-8);
testCase.verifyEqual(imag(S),0.10,'AbsTol',1e-8);
testCase.verifyEqual(s.eigenvalue_count,dev.nx);
end

% =========================================================================
function test_sssa_finite_schur_and_stable(testCase)
[~,~,~,~,~,~,s] = gfm6_fixture();
testCase.verifyGreaterThan(s.gy_rcond,1e-8);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyLessThan(s.schur_direct_relative_error,2e-5);
testCase.verifyLessThan(s.max_real_eigenvalue,0);
end

% =========================================================================
function test_swing_complex_mode_present(testCase)
% The low-inertia VSG swing loop is underdamped -> a complex electromechanical
% pole pair must exist (oscillatory swing mode).
[~,~,~,~,~,~,s] = gfm6_fixture();
lam = s.eigenvalues(:);
osc = lam(abs(imag(lam))>1e-6);
testCase.verifyGreaterThanOrEqual(numel(osc),2);
end

% =========================================================================
function test_no_pll_angle_from_swing_only(testCase)
% Runtime rotor-angle derivative comes ONLY from the swing:
%   d(delta)/dt = omega_b*(omega - 1); independent of the terminal voltage
%   angle (no PLL / no angle(V) tracking). delta is state 4, omega is state 3.
[dev,x,V,u] = gfm6_fixture();
ec = struct(); y = [real(V);imag(V)];
f0 = dev.f(0,x,y,u,ec);
dphi = 0.05; Vp = V*exp(1i*dphi); yp = [real(Vp);imag(Vp)];
fp = dev.f(0,x,yp,u,ec);
testCase.verifyLessThan(abs(fp(4)-f0(4)),1e-9);
omega_b = dev.provenance.params.omega_b;
h = 1e-6; xp = x; xp(3) = xp(3)+h;
fw = dev.f(0,xp,y,u,ec);
testCase.verifyEqual((fw(4)-f0(4))/h, omega_b, 'RelTol',1e-4);
end

% =========================================================================
function test_sssa_fd_convergence(testCase)
[dev,x,V,u,E,Z] = gfm6_fixture();
s1 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z,'fd_eps',2e-6,'direct_fd_eps',2e-6);
s2 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z,'fd_eps',1e-6,'direct_fd_eps',1e-6);
rel = norm(s1.A-s2.A,inf)/max(1,norm(s1.A,inf)+norm(s2.A,inf));
testCase.verifyLessThan(rel,2e-5);
end

% =========================================================================
function test_event_free_tds_drift(testCase)
[dev,x,V,u,E,Z,s] = gfm6_fixture();
tds = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',3,'perturb_amp',1e-3,'A_linear',s.A);
testCase.verifyLessThan(tds.max_drift,1e-9);
testCase.verifyTrue(tds.newton_info_drift.all_converged);
testCase.verifyFalse(tds.linear_overflow);
end

% =========================================================================
function test_rhs_jacobian_fd_agreement(testCase)
[dev,x,V,u,~,~,s] = gfm6_fixture();
ec = struct(); y = [real(V);imag(V)];
h = 1e-6; nx = dev.nx; fx = zeros(nx);
for j = 1:nx
    xp = x; xm = x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
    fx(:,j) = (dev.f(0,xp,y,u,ec)-dev.f(0,xm,y,u,ec))/(2*h);
end
rel = norm(fx - s.fx,inf)/max(1,norm(s.fx,inf));
testCase.verifyLessThan(rel,1e-4);
end
