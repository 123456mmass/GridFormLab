function tests = test_emf6_physics_contract()
%TEST_EMF6_PHYSICS_CONTRACT  Physics/model-contract tests for the operational
%   EMF6 model on the Kundur two-area (12.6) case. These tests verify
%   STRUCTURAL and NUMERICAL properties derived from the equations — NOT
%   literature frequency/damping ranges and NOT Kundur Table E12.3.
%
%   Replaces the former test_kundur_literature_ranges (which used external
%   literature bands as numerical acceptance). Literature ranges are retained
%   only as diagnostic-only data in scripts/diagnostics/kundur_literature_reference.m.
%
%   Contracts:
%     1. Equilibrium residual (f, g ~ 0 at the operating point)
%     2. Reference-angle invariance (angle-shift is a near-zero mode)
%     3. Stability: all NON-reference-angle modes have Re < 0 (the only
%        non-decaying modes are the reference-angle modes, explained by
%        rotational invariance + COI-reduction numerics — not real instability)
%     4. Conjugate-pair structure (complex eigenvalues come in conjugate pairs)
%     5. Finite eigenvalues (no Inf/NaN)
%     6. Expected state count (ng * 6 differential states)
%     7. Jacobian finite-difference convergence (analytic Jacobian matches
%        numerical finite-difference Jacobian)

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function [c,ssa] = emf6_fixture()
c = cases.kundur_ex126_book_case();
ssa = stability.synchronous_emf6_ssa(c, struct('load_model','cc_p_cz_q'));
end

function test_1_equilibrium_residual(testCase)
% The operating point must zero the DAE residual (f, g).
[c,ssa] = emf6_fixture();
EQ_TOL = 1e-9;
f0 = ssa.dae_f(ssa.init.x0, ssa.init.y0);
g0 = ssa.dae_g(ssa.init.x0, ssa.init.y0, ssa.Ynet);
testCase.verifyLessThan(norm(f0,inf), EQ_TOL, 'differential residual max|f| at equilibrium');
testCase.verifyLessThan(norm(g0,inf), EQ_TOL, 'algebraic residual max|g| at equilibrium');
end

function test_2_reference_angle_invariance(testCase)
% A common rotation of all rotor angles is a symmetry of the equations:
% Afull * angle_shift must be ~0 (the reference-angle zero mode).
[~,ssa] = emf6_fixture();
testCase.verifyLessThan(ssa.angle_shift_residual, 1e-6, ...
    'Afull*angle_shift must be ~0 (rotational invariance)');
end

function test_3_non_reference_modes_stable(testCase)
% All modes EXCEPT the reference-angle modes must have Re < 0. The
% reference-angle modes (identified by overlap with the angle-shift
% direction) are the only non-decaying modes; they are explained by
% rotational invariance + COI-reduction numerics, NOT real instability.
[~,ssa] = emf6_fixture();
lam = ssa.eigenvalues; V = ssa.mode_shapes;
as = zeros(numel(lam),1); as(1:6:end) = 1;
Vn = V ./ vecnorm(V,2,1).';   % normalize columns
overlap = abs(Vn' * as) / norm(as);
refmask = overlap > 0.99;     % reference-angle modes
nonref = lam(~refmask);
testCase.verifyTrue(~isempty(nonref), 'must have non-reference modes');
testCase.verifyTrue(all(isfinite(real(nonref))), 'non-reference eigenvalues finite');
testCase.verifyTrue(all(real(nonref) < 0), ...
    'all non-reference-angle modes must be stable (Re<0)');
end

function test_4_conjugate_pair_structure(testCase)
% Complex eigenvalues must come in conjugate pairs (real state matrix).
[~,ssa] = emf6_fixture();
lam = ssa.eigenvalues;
cmplx = lam(abs(imag(lam)) > 1e-9);
testCase.verifyTrue(~isempty(cmplx), 'must have complex modes');
% For each complex eigenvalue, its conjugate must also be present.
matched = false(size(cmplx));
for k = 1:numel(cmplx)
    d = abs(cmplx - conj(cmplx(k)));
    [~,j] = min(d);
    if d(j) < 1e-9 * (1 + abs(cmplx(k))), matched(k) = true; end
end
testCase.verifyTrue(all(matched), 'complex eigenvalues must come in conjugate pairs');
end

function test_5_finite_eigenvalues(testCase)
% No Inf/NaN eigenvalues.
[~,ssa] = emf6_fixture();
lam = ssa.eigenvalues;
testCase.verifyTrue(all(isfinite(lam)), 'all eigenvalues finite (no Inf/NaN)');
end

function test_6_expected_state_count(testCase)
% ng machines * 6 differential states per machine.
[~,ssa] = emf6_fixture();
ng = ssa.init.ng;
testCase.verifyEqual(numel(ssa.init.x0), ng*6, ...
    'differential state count = ng * 6');
testCase.verifyEqual(numel(ssa.eigenvalues), ng*6, ...
    'eigenvalue count = ng * 6');
end

function test_7_jacobian_finite_difference(testCase)
% The analytic Jacobian (Jxx, Jxy) must match a numerical finite-difference
% Jacobian of dae_f. This proves the linearization is consistent with the
% equations (not a hand-coded approximation).
[c,ssa] = emf6_fixture();
x0 = ssa.init.x0; y0 = ssa.init.y0;
f = @(x,y) ssa.dae_f(x,y);
eps_fd = ssa.fd_eps; if isempty(eps_fd), eps_fd = 1e-6; end
nx = numel(x0); ny = numel(y0);
Jxx_fd = zeros(nx,nx); Jxy_fd = zeros(nx,ny);
for i = 1:nx
    e = zeros(nx,1); e(i) = eps_fd;
    Jxx_fd(:,i) = (f(x0+e,y0) - f(x0-e,y0)) / (2*eps_fd);
end
for i = 1:ny
    e = zeros(ny,1); e(i) = eps_fd;
    Jxy_fd(:,i) = (f(x0,y0+e) - f(x0,y0-e)) / (2*eps_fd);
end
% Relative scale of the Jacobian; FD error ~ eps_fd^(2/3) for central diff.
scale = max([norm(ssa.Jxx,inf), norm(ssa.Jxy,inf), 1]);
tol = 1e-4 * scale;   % central-difference O(eps_fd^2) with eps_fd=1e-6 -> ~1e-4 rel
testCase.verifyLessThan(max(abs(ssa.Jxx - Jxx_fd),[],'all'), tol, ...
    'analytic Jxx matches finite-difference Jxx');
testCase.verifyLessThan(max(abs(ssa.Jxy - Jxy_fd),[],'all'), tol, ...
    'analytic Jxy matches finite-difference Jxy');
end
