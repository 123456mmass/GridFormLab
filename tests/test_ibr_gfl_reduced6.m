function tests = test_ibr_gfl_reduced6()
%TEST_IBR_GFL_REDUCED6  6-state reduced grid-following inverter (EECON49-P4) SMIB.
%   One reduced GFL model (blocks IBR+GFL(PLL)+PQ, 2 states each) connected to
%   an ideal algebraic infinite bus. Verifies ABI/state order, closed-form
%   equilibrium (residual ~0), the P+jQ=V*conj(I) identity, SSSA finiteness/
%   Schur consistency and asymptotic stability, the presence of the expected
%   underdamped PLL complex mode, FD-step convergence, and event-free TDS drift.
tests = functiontests(localfunctions());
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [dev,x,V,u,E,Z,s] = gfl6_fixture()
c = cases.case_ibr_smib_gfl_reduced6();
m = c.smib_verification;
V = m.V_terminal; Z = m.Z_line_pu;
dev = ibr.gfl_reduced6_model(char(m.device_id),1,1,1,V,struct(), ...
    m.P_terminal_pu, m.Q_terminal_pu);
x = dev.equilibrium_initialize(V,m.P_terminal_pu,m.Q_terminal_pu,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V - Z*I;
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
end

% =========================================================================
function test_abi_state_order_and_metadata(testCase)
dev = gfl6_fixture();
testCase.verifyEqual(dev.nx,6);
testCase.verifyEqual(dev.nu,2);
testCase.verifyEqual(dev.device_type,'ibr_gfl_reduced6');
testCase.verifyEqual(dev.state_names,{'i_d','i_q','delta_PLL','xi_PLL','xi_P','xi_Q'});
testCase.verifyEqual(dev.input_names,{'P_ref','Q_ref'});
testCase.verifyTrue(isfield(dev.provenance,'readiness'));
end

% =========================================================================
function test_reduced_option_guard(testCase)
% Options belonging only to the full 10-state model must fail closed.
mk = @(opt) ibr.gfl_reduced6_model('T',1,1,1,1.0,struct('gfl_reduced6',opt),0.4,0.1);
for fld = {'T_P','ki_i','Imax','Vdip','ts_pll'}
    o = struct(); o.(fld{1}) = 1.0;
    testCase.verifyError(@() mk(o),'ibr:gfl_reduced6_model:unsupportedOption');
end
end

% =========================================================================
function test_equilibrium_and_power_identity(testCase)
[dev,x,V,u,~,~,s] = gfl6_fixture();
testCase.verifyLessThan(norm(s.f0,inf),1e-9);
testCase.verifyLessThan(norm(s.g0,inf),1e-10);
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
S = V*conj(I);
testCase.verifyEqual(real(S),0.40,'AbsTol',1e-8);
testCase.verifyEqual(imag(S),0.10,'AbsTol',1e-8);
testCase.verifyEqual(s.eigenvalue_count,dev.nx);
end

% =========================================================================
function test_sssa_finite_schur_and_stable(testCase)
[~,~,~,~,~,~,s] = gfl6_fixture();
testCase.verifyGreaterThan(s.gy_rcond,1e-8);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyLessThan(s.schur_direct_relative_error,2e-5);
testCase.verifyLessThan(s.max_real_eigenvalue,0);
end

% =========================================================================
function test_pll_complex_mode_present(testCase)
% A physically-tuned SRF-PLL (zeta<1) must yield an underdamped complex pole
% pair (the oscillatory synchronization mode). Verify at least one complex
% conjugate pair exists with a low, positive oscillation frequency.
[~,~,~,~,~,~,s] = gfl6_fixture();
lam = s.eigenvalues(:);
osc = lam(abs(imag(lam))>1e-6);
testCase.verifyGreaterThanOrEqual(numel(osc),2);   % at least one pair
f_osc = abs(imag(osc))/(2*pi);
% The PLL mode sits at a low frequency (order ~0.1-2 Hz for these gains).
testCase.verifyTrue(any(f_osc>0.05 & f_osc<3.0));
end

% =========================================================================
function test_sssa_fd_convergence(testCase)
[dev,x,V,u,E,Z] = gfl6_fixture();
s1 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z,'fd_eps',2e-6,'direct_fd_eps',2e-6);
s2 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z,'fd_eps',1e-6,'direct_fd_eps',1e-6);
rel = norm(s1.A-s2.A,inf)/max(1,norm(s1.A,inf)+norm(s2.A,inf));
testCase.verifyLessThan(rel,2e-5);
end

% =========================================================================
function test_event_free_tds_drift(testCase)
[dev,x,V,u,E,Z,s] = gfl6_fixture();
tds = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',3,'perturb_amp',1e-3,'A_linear',s.A);
testCase.verifyLessThan(tds.max_drift,1e-9);
testCase.verifyTrue(tds.newton_info_drift.all_converged);
testCase.verifyFalse(tds.linear_overflow);
end

% =========================================================================
function test_rhs_jacobian_fd_agreement(testCase)
[dev,x,V,u,~,~,s] = gfl6_fixture();
ec = struct(); y = [real(V);imag(V)];
h = 1e-6; nx = dev.nx; fx = zeros(nx);
for j = 1:nx
    xp = x; xm = x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
    fx(:,j) = (dev.f(0,xp,y,u,ec)-dev.f(0,xm,y,u,ec))/(2*h);
end
rel = norm(fx - s.fx,inf)/max(1,norm(s.fx,inf));
testCase.verifyLessThan(rel,1e-4);
end
