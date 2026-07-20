function tests = test_ibr_gfm_vsg_no_pll_smib()
%TEST_IBR_GFM_VSG_NO_PLL_SMIB  GFM-noPLL single-infinite-bus verification.
%   Case B of the mandatory DUAL SMIB scope. One GFM-VSG-noPLL connected to
%   one ideal algebraic infinite bus (no SG states). Verifies equilibrium,
%   SSSA, FD convergence, event-free TDS drift, small-perturbation SSSA-TDS
%   consistency, and the behavioral no-PLL contract. GFL is the separate
%   control case in test_ibr_smib_sssa_oracle.m; the two are never paired.
tests = functiontests(localfunctions());
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [dev,x,V,u,E,Z,s] = gfm_fixture()
% Frozen source-reproduction fixture: 50 Hz, 100 MVA, H_GFM=5, D_GFM=20.
V = 1.0+0i; P = 0.40; Q = 0.10; Z = 0.02+0.20i;
X_L = 0.15; m_q = 0.05; Q_ref = 0.0; kappa = 1.0;
I_sys = conj((P+1i*Q)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
V_ref = abs(E_internal) + m_q*(kappa*Q - Q_ref);
dev = ibr.gfm_vsg_no_pll_model("GFM_SMIB",1,1,1,V,struct(),P,V_ref);
x = dev.equilibrium_initialize(V,P,Q,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V - Z*I;
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
end

% =========================================================================
function test_gfm_no_pll_smib_equilibrium(testCase)
[dev,x,V,u,E,Z,s] = gfm_fixture();
testCase.verifyLessThan(norm(s.f0,inf),1e-9);
testCase.verifyLessThan(norm(s.g0,inf),1e-11);
% Power identity: V*conj(I) reproduces requested P,Q.
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
S = V*conj(I);
testCase.verifyEqual(real(S),0.40,'AbsTol',1e-9);
testCase.verifyEqual(imag(S),0.10,'AbsTol',1e-9);
% Active-state count from runtime metadata.
testCase.verifyEqual(s.eigenvalue_count,dev.nx);
testCase.verifyEqual(numel(s.active_state_indices),dev.nx);
end

% =========================================================================
function test_gfm_no_pll_smib_sssa(testCase)
[~,~,~,~,~,~,s] = gfm_fixture();
testCase.verifyGreaterThan(s.gy_rcond,1e-8);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyLessThan(s.schur_direct_relative_error,2e-5);
% Eigenpair residual: A*v = lambda*v for each eigenpair.
[Vp,Dp] = eig(s.A);
res = norm(s.A*Vp - Vp*Dp,inf)/max(1,norm(s.A,inf));
testCase.verifyLessThan(res,1e-6);
% Report max real eigenvalue honestly (stability is an outcome, not a gate).
testCase.verifyTrue(isfinite(s.max_real_eigenvalue));
end

% =========================================================================
function test_gfm_no_pll_smib_fd_convergence(testCase)
[dev,x,V,u,E,Z] = gfm_fixture();
s1 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z, ...
    'fd_eps',2e-6,'direct_fd_eps',2e-6);
s2 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z, ...
    'fd_eps',1e-6,'direct_fd_eps',1e-6);
rel = norm(s1.A-s2.A,inf)/max(1,norm(s1.A,inf)+norm(s2.A,inf));
testCase.verifyLessThan(rel,2e-5);
end

% =========================================================================
function test_gfm_no_pll_smib_event_free_tds(testCase)
[dev,x,V,u,E,Z,s] = gfm_fixture();
tds = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',2,'perturb_amp',1e-3, ...
    'A_linear',s.A);
% Event-free drift must be at numerical zero (equilibrium is a fixed point).
testCase.verifyLessThan(tds.max_drift,1e-9);
% Every Newton step converged.
testCase.verifyTrue(tds.newton_info_drift.all_converged);
end

% =========================================================================
function test_gfm_no_pll_smib_small_perturbation_consistency(testCase)
[dev,x,V,u,E,Z,s] = gfm_fixture();
% Nonlinear TDS vs linear SSSA response must agree for small perturbation,
% and the discrepancy must decrease with perturbation amplitude.
tds1 = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.02,'dt',5e-4,'perturb_state',2,'perturb_amp',1e-3, ...
    'perturb_amp_half',5e-4,'A_linear',s.A);
tds2 = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.02,'dt',5e-4,'perturb_state',2,'perturb_amp',1e-4, ...
    'perturb_amp_half',5e-5,'A_linear',s.A);
% Linear-vs-nonlinear error at the smaller amplitude must be smaller.
testCase.verifyLessThan(tds2.nonlinear_vs_linear_error, ...
    tds1.nonlinear_vs_linear_error);
% Perturbation-halving ratio must be small (nonlinear scales with amplitude).
testCase.verifyLessThan(tds1.perturbation_halving_ratio,1e-3);
end

% =========================================================================
function test_gfm_no_pll_behavior_contains_no_pll(testCase)
% Behavioral no-PLL: angle-derivative structure, terminal-angle independence,
% rigid-frame covariance. Plus structural scan.
[dev,x,V] = gfm_fixture();
u = dev.u0; ec = struct();
y = [real(V);imag(V)];
% Structural: no PLL state names.
names = dev.state_names;
testCase.verifyFalse(any(strcmp(names,'delta_PLL')));
testCase.verifyFalse(any(strcmp(names,'xi_PLL')));
testCase.verifyFalse(any(strcmp(names,'x_PLL_int')));
% Angle-derivative structure.
f0 = dev.f(0,x,y,u,ec);
h = 1e-6;
yp = y; yp(1) = yp(1)+h;
fp_y = dev.f(0,x,yp,u,ec);
testCase.verifyLessThan(abs(fp_y(1)-f0(1)),1e-9);
xp = x; xp(1) = xp(1)+h;
fp_d = dev.f(0,xp,y,u,ec);
testCase.verifyLessThan(abs(fp_d(1)-f0(1)),1e-9);
xp2 = x; xp2(2) = xp2(2)+h;
fp_w = dev.f(0,xp2,y,u,ec);
omega_base = dev.provenance.params.omega_base;
testCase.verifyEqual((fp_w(1)-f0(1))/h, omega_base, 'RelTol', 1e-4);
% Terminal-angle independence.
dphi = 0.05;
Vp = V*exp(1i*dphi);
yp2 = [real(Vp);imag(Vp)];
fp_ta = dev.f(0,x,yp2,u,ec);
testCase.verifyLessThan(abs(fp_ta(1)-f0(1)),1e-9);
% Rigid-frame covariance.
xp3 = x; xp3(1) = xp3(1)+dphi;
fp3 = dev.f(0,xp3,yp2,u,ec);
testCase.verifyEqual(fp3(2:4),f0(2:4),'AbsTol',1e-9);
Ip3 = dev.current_injection(0,xp3,yp2,u,ec);
Sp3 = Vp*conj(Ip3);
S0 = V*conj(dev.current_injection(0,x,y,u,ec));
testCase.verifyEqual(real(Sp3),real(S0),'AbsTol',1e-9);
testCase.verifyEqual(imag(Sp3),imag(S0),'AbsTol',1e-9);
end
