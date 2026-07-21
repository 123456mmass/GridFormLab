function tests = test_ibr_gfm_vsm_sakimoto()
%TEST_IBR_GFM_VSM_SAKIMOTO  9-state Sakimoto GFM VSG (no PLL/AVR/PSS) SMIB.
%   One Sakimoto current-controlled VSG connected to an ideal algebraic
%   infinite bus (no SG states). Verifies ABI/state order, the hard
%   no-PLL/no-AVR/no-PSS construction guard, machine-zero equilibrium, the
%   P+jQ=V*conj(I) identity, SSSA (shared oracle) finiteness/eigenpair/Schur
%   consistency and asymptotic stability (Sakimoto proves K=10,J=4 stable),
%   FD-step convergence, and event-free TDS drift. Separate from the 4-state
%   gfm_vsg_no_pll device (test_ibr_gfm_vsg_no_pll_smib.m); never paired.
tests = functiontests(localfunctions());
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [dev,x,V,u,E,Z,s] = sakimoto_fixture()
c = cases.case_ibr_smib_gfm_vsm_sakimoto();
m = c.smib_verification;
V = m.V_terminal; Z = m.Z_line_pu;
dev = ibr.gfm_vsm_sakimoto_model(char(m.device_id),1,1,1,V,struct(), ...
    m.P_terminal_pu, m.Q_terminal_pu);
x = dev.equilibrium_initialize(V,m.P_terminal_pu,m.Q_terminal_pu,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V - Z*I;
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
end

% =========================================================================
function test_abi_state_order_and_metadata(testCase)
[dev,~,~,~,~,~,~] = sakimoto_fixture();
testCase.verifyEqual(dev.nx,9);
testCase.verifyEqual(dev.nu,2);
testCase.verifyEqual(dev.device_type,'ibr_gfm_vsm_sakimoto');
testCase.verifyEqual(dev.state_names, ...
    {'i_d','i_q','xi_id','xi_iq','omega_R','delta','x_gov','T_m','x_d'});
testCase.verifyEqual(dev.input_names,{'P_ref','Q_ref'});
testCase.verifyTrue(isfield(dev.provenance,'readiness'));
end

% =========================================================================
function test_no_pll_no_avr_no_pss_guard(testCase)
% Hard construction-time guard: dormant PLL/AVR/PSS options fail closed.
mk = @(opt) ibr.gfm_vsm_sakimoto_model('T',1,1,1,1.0, ...
    struct('gfm_vsm_sakimoto',opt),0.4,0.1);
for fld = {'kp_PLL','ki_PLL','delta_PLL','K_ad','K_AI','pss_gain','VFlag'}
    o = struct(); o.(fld{1}) = 1.0;
    testCase.verifyError(@() mk(o), ...
        'ibr:gfm_vsm_sakimoto_model:unsupportedOption');
end
% No PLL/AVR/PSS state in the inventory.
dev = sakimoto_fixture();
names = dev.state_names;
testCase.verifyFalse(any(contains(lower(names),'pll')));
testCase.verifyFalse(any(contains(lower(names),'avr')));
testCase.verifyFalse(any(contains(lower(names),'pss')));
end

% =========================================================================
function test_equilibrium_machine_zero_and_power_identity(testCase)
[dev,x,V,u,~,~,s] = sakimoto_fixture();
testCase.verifyLessThan(norm(s.f0,inf),1e-8);
testCase.verifyLessThan(norm(s.g0,inf),1e-10);
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
S = V*conj(I);
testCase.verifyEqual(real(S),0.40,'AbsTol',1e-8);
testCase.verifyEqual(imag(S),0.10,'AbsTol',1e-8);
testCase.verifyEqual(s.eigenvalue_count,dev.nx);
testCase.verifyEqual(numel(s.active_state_indices),dev.nx);
end

% =========================================================================
function test_sssa_finite_schur_and_stable(testCase)
[~,~,~,~,~,~,s] = sakimoto_fixture();
testCase.verifyGreaterThan(s.gy_rcond,1e-8);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyLessThan(s.schur_direct_relative_error,2e-5);
[Vp,Dp] = eig(s.A);
res = norm(s.A*Vp - Vp*Dp,inf)/max(1,norm(s.A,inf));
testCase.verifyLessThan(res,1e-6);
% Asymptotic stability: Sakimoto eq 24-25 proves K=10, J=4 (Table 3 case 2-2)
% is stable. This device reproduces that (source-backed physics check).
testCase.verifyLessThan(s.max_real_eigenvalue,0);
end

% =========================================================================
function test_sssa_fd_convergence(testCase)
[dev,x,V,u,E,Z] = sakimoto_fixture();
s1 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z,'fd_eps',2e-6,'direct_fd_eps',2e-6);
s2 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z,'fd_eps',1e-6,'direct_fd_eps',1e-6);
rel = norm(s1.A-s2.A,inf)/max(1,norm(s1.A,inf)+norm(s2.A,inf));
testCase.verifyLessThan(rel,2e-5);
end

% =========================================================================
function test_event_free_tds_drift(testCase)
[dev,x,V,u,E,Z,s] = sakimoto_fixture();
% Perturb omega_R (state 5, a stable swing direction).
tds = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',5,'perturb_amp',1e-3,'A_linear',s.A);
testCase.verifyLessThan(tds.max_drift,1e-9);
testCase.verifyTrue(tds.newton_info_drift.all_converged);
testCase.verifyFalse(tds.linear_overflow);
end

% =========================================================================
function test_no_pll_angle_from_swing_only(testCase)
% The runtime load angle derivative comes ONLY from the swing:
%   d(delta)/dt = omega_b*(omega_R - 1); it must not depend on the terminal
%   voltage angle (no PLL / no angle(V) tracking).
[dev,x,V,u] = sakimoto_fixture();
ec = struct(); y = [real(V);imag(V)];
f0 = dev.f(0,x,y,u,ec);
% d(delta)/dt (state 6) independent of the terminal voltage angle.
dphi = 0.05; Vp = V*exp(1i*dphi); yp = [real(Vp);imag(Vp)];
fp = dev.f(0,x,yp,u,ec);
testCase.verifyLessThan(abs(fp(6)-f0(6)),1e-9);
% d(delta)/dt scales with omega_R deviation at omega_b.
omega_b = dev.provenance.params.omega_b;
h = 1e-6; xp = x; xp(5) = xp(5)+h;
fw = dev.f(0,xp,y,u,ec);
testCase.verifyEqual((fw(6)-f0(6))/h, omega_b, 'RelTol',1e-4);
% delta derivative does not depend on delta itself.
xp2 = x; xp2(6) = xp2(6)+h;
fd = dev.f(0,xp2,y,u,ec);
testCase.verifyLessThan(abs(fd(6)-f0(6)),1e-9);
end

% =========================================================================
function test_rhs_jacobian_fd_agreement(testCase)
% Independent centered-FD Jacobian of dev.f wrt x agrees with the oracle fx.
[dev,x,V,u,~,~,s] = sakimoto_fixture();
ec = struct(); y = [real(V);imag(V)];
h = 1e-6; nx = dev.nx; fx = zeros(nx);
for j = 1:nx
    xp = x; xm = x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
    fx(:,j) = (dev.f(0,xp,y,u,ec)-dev.f(0,xm,y,u,ec))/(2*h);
end
rel = norm(fx - s.fx,inf)/max(1,norm(s.fx,inf));
testCase.verifyLessThan(rel,1e-4);
end
