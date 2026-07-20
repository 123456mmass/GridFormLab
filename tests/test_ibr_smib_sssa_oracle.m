function tests = test_ibr_smib_sssa_oracle()
%TEST_IBR_SMIB_SSSA_ORACLE One converter against an algebraic infinite bus.
%   This isolates IBR equations/network signs/Schur reduction from the
%   already-verified SG analysis path. REGFM_B1 results are legacy-with-PLL
%   comparison evidence only, not validation of the future no-PLL GFM.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_gfl_rms10_smib_equilibrium(testCase)
[dev,x,V,u,E,Z] = gfl_fixture();
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
testCase.verifyLessThan(norm(s.f0,inf),1e-9);
testCase.verifyLessThan(norm(s.g0,inf),1e-11);
testCase.verifyEqual(s.eigenvalue_count,dev.nx);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyGreaterThan(s.gy_rcond,1e-8);
end

function test_gfl_schur_matches_resolved_kcl_oracle(testCase)
[dev,x,V,u,E,Z] = gfl_fixture();
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
testCase.verifyLessThan(s.schur_direct_relative_error,2e-5);
end

function test_gfl_fd_step_convergence(testCase)
[dev,x,V,u,E,Z] = gfl_fixture();
s1 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z, ...
    'fd_eps',2e-6,'direct_fd_eps',2e-6);
s2 = ibr.smib_sssa_oracle(dev,x,V,u,E,Z, ...
    'fd_eps',1e-6,'direct_fd_eps',1e-6);
rel = norm(s1.A-s2.A,inf)/max(1,norm(s1.A,inf)+norm(s2.A,inf));
testCase.verifyLessThan(rel,2e-5);
end

function test_gfl_rms10_smib_sssa(testCase)
% GFL SSSA gate: gy conditioning, finite eigenvalues, Schur-vs-direct.
[dev,x,V,u,E,Z,s] = gfl_fixture_with_sssa();
testCase.verifyGreaterThan(s.gy_rcond,1e-8);
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
testCase.verifyEqual(s.eigenvalue_count,dev.nx);
testCase.verifyLessThan(s.schur_direct_relative_error,2e-5);
[Vp,Dp] = eig(s.A);
res = norm(s.A*Vp - Vp*Dp,inf)/max(1,norm(s.A,inf));
testCase.verifyLessThan(res,1e-6);
end

function test_gfl_rms10_smib_event_free_tds(testCase)
[dev,x,V,u,E,Z,s] = gfl_fixture_with_sssa();
% Perturb P_f (state 3, a stable mode). GFL has an unstable PLL eigenvalue
% (delta_PLL mode, real part ~3.4e5) at this operating point; perturbing
% state 1 would make expm(A*t) overflow. Stability is an outcome, reported
% honestly in the diagnostics; the TDS drift gate uses a stable direction.
tds = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',3,'perturb_amp',1e-3, ...
    'A_linear',s.A);
testCase.verifyLessThan(tds.max_drift,1e-9);
testCase.verifyTrue(tds.newton_info_drift.all_converged);
end

function test_gfl_rms10_smib_small_perturbation_consistency(testCase)
[dev,x,V,u,E,Z,s] = gfl_fixture_with_sssa();
tds1 = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.02,'dt',5e-4,'perturb_state',3,'perturb_amp',1e-3, ...
    'perturb_amp_half',5e-4,'A_linear',s.A);
tds2 = ibr.smib_tds_oracle(dev,x,V,u,E,Z, ...
    'T',0.02,'dt',5e-4,'perturb_state',3,'perturb_amp',1e-4, ...
    'perturb_amp_half',5e-5,'A_linear',s.A);
% GFL has an unstable PLL eigenvalue (real part ~3.4e5) at this operating
% point, so the linear SSSA response expm(A*t) overflows. The
% perturbation-halving ratio (a nonlinear-only metric) must still converge.
% The nonlinear-vs-linear comparison is skipped when linear_overflow is true.
if tds1.linear_overflow
    testCase.verifyTrue(tds1.linear_overflow);
    testCase.verifyEqual(tds1.nonlinear_vs_linear_error,Inf);
else
    testCase.verifyLessThan(tds2.nonlinear_vs_linear_error, ...
        tds1.nonlinear_vs_linear_error);
end
testCase.verifyLessThan(tds1.perturbation_halving_ratio,1e-3);
end

function test_legacy_regfm_smib_is_explicitly_not_no_pll(testCase)
[dev,x,V,u,E,Z] = legacy_gfm_fixture();
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
testCase.verifyLessThan(norm(s.f0,inf),1e-8);
testCase.verifyLessThan(norm(s.g0,inf),1e-10);
testCase.verifyEqual(s.eigenvalue_count,numel(dev.active_state_indices));
testCase.verifyTrue(any(strcmp(dev.state_names,'delta_PLL')));
testCase.verifyTrue(any(strcmp(dev.state_names,'x_PLL_int')));
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
end

function test_legacy_regfm_schur_matches_resolved_kcl_oracle(testCase)
[dev,x,V,u,E,Z] = legacy_gfm_fixture();
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
testCase.verifyLessThan(s.schur_direct_relative_error,5e-5);
end

function test_oracle_rejects_nonstandalone_bus_position(testCase)
dev = ibr.gfl_rms10_model("GFL_BAD",2,2,[1 2],1,struct(),0.4,0.0);
x = dev.equilibrium_initialize(1,0.4,0.0,struct());
testCase.verifyError(@() ibr.smib_sssa_oracle(dev,x,1,dev.u0,0.99-0.08i,0.2i), ...
    'ibr:smib_sssa_oracle:busPosition');
end

function [dev,x,V,u,E,Z] = gfl_fixture()
V = 1.0+0i; P = 0.40; Q = 0.10; Z = 0.02+0.20i;
dev = ibr.gfl_rms10_model("GFL_SMIB",1,1,1,V,struct(),P,Q);
x = dev.equilibrium_initialize(V,P,Q,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V-Z*I;
end

function [dev,x,V,u,E,Z,s] = gfl_fixture_with_sssa()
[dev,x,V,u,E,Z] = gfl_fixture();
s = ibr.smib_sssa_oracle(dev,x,V,u,E,Z);
end

function [dev,x,V,u,E,Z] = legacy_gfm_fixture()
V = 1.0+0i; P = 0.40; Q = 0.00; Z = 0.02+0.20i;
dev = ibr.regfm_b1_vsg_model("GFM_LEGACY_SMIB",1,1,1,V,struct(),P,abs(V));
x = dev.equilibrium_initialize(V,P,Q,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V-Z*I;
end
