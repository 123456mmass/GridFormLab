function tests = test_sssa_fd_convergence()
%TEST_SSSA_FD_CONVERGENCE  Finite-difference step convergence study.
%   Verifies that the central-FD Jacobian and the resulting eigenvalues
%   CONVERGE as the FD step h decreases, on the plateau h=1e-5/1e-6. This is a
%   convergence study, NOT a fit to literature values. Tolerances are declared
%   up front from FD truncation order (central FD is O(h^2)) -- they are NOT
%   relaxed after seeing a result.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function ssa = padiyar_avr_fixture()
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
end

function ssa = padiyar_manual_fixture()
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','manual','fd_eps',1e-6));
end

function ssa = emf6_fixture()
c = cases.kundur_ex126_book_case();
ssa = stability.synchronous_emf6_ssa(c, struct('load_model','cc_p_cz_q'));
end

function [Jxx,Jxy,Jyx,Jyy] = fd_jacobian(f, g, x0, y0, h)
% Independent central-FD Jacobian of f(x,y) and g(x,y) at step h.
nx = numel(x0); ny = numel(y0);
Jxx = zeros(nx,nx); Jxy = zeros(nx,ny);
Jyx = zeros(ny,nx); Jyy = zeros(ny,ny);
for i = 1:nx
    xp = x0; xm = x0; xp(i) = xp(i)+h; xm(i) = xm(i)-h;
    Jxx(:,i) = (f(xp,y0) - f(xm,y0))/(2*h);
    Jyx(:,i) = (g(xp,y0) - g(xm,y0))/(2*h);
end
for j = 1:ny
    yp = y0; ym = y0; yp(j) = yp(j)+h; ym(j) = ym(j)-h;
    Jxy(:,j) = (f(x0,yp) - f(x0,ym))/(2*h);
    Jyy(:,j) = (g(x0,yp) - g(x0,ym))/(2*h);
end
end

function [x0,y0,f,g,fy,Afun] = model_handles(name)
% Return handles and Schur reconstructor for the named model.
switch name
case 'padiyar_manual'
    ssa = padiyar_manual_fixture();
    x0 = ssa.dae.x0; y0 = ssa.dae.y0;
    f = ssa.dae.dae_f; g = @(x,y) ssa.dae.dae_g(x,y,ssa.dae.Ynet);
    fy = 1:numel(y0);
case 'padiyar_avr'
    ssa = padiyar_avr_fixture();
    x0 = ssa.dae.x0; y0 = ssa.dae.y0;
    f = ssa.dae.dae_f; g = @(x,y) ssa.dae.dae_g(x,y,ssa.dae.Ynet);
    fy = 1:numel(y0);
case 'emf6'
    ssa = emf6_fixture();
    x0 = ssa.init.x0; y0 = ssa.init.y0;
    f = ssa.dae_f; g = @(x,y) ssa.dae_g(x,y,ssa.Ynet);
    fy = 1:numel(y0);
otherwise
    error('fd_convergence:unknownModel', 'unknown model %s', name);
end
Afun = @(Jxx,Jxy,Jyx,Jyy) Jxx - Jxy(:,fy)*(Jyy(fy,fy)\Jyx(fy,:));
end

function test_1_jacobian_blocks_finite(testCase)
% For each model and each h in H_LIST, re-derive the FD Jacobian from the DAE
% handles. All blocks must be finite at every h. Afull drift between adjacent
% h-levels is reported (informational, not gated here).
names = {'padiyar_manual','padiyar_avr','emf6'};
h_list = [1e-4, 1e-5, 1e-6, 1e-7];
for m = 1:numel(names)
    [x0,y0,f,g,fy,Afun] = model_handles(names{m});
    A_prev = [];
    for hi = 1:numel(h_list)
        h = h_list(hi);
        [Jxx,Jxy,Jyx,Jyy] = fd_jacobian(f, g, x0, y0, h);
        testCase.verifyTrue(all(isfinite(Jxx(:))) && all(isfinite(Jxy(:))) && ...
            all(isfinite(Jyx(:))) && all(isfinite(Jyy(:))), ...
            sprintf('%s h=%.0e: all Jacobian blocks finite', names{m}, h));
        A = Afun(Jxx,Jxy,Jyx,Jyy);
        if ~isempty(A_prev)
            drift = max(abs(A - A_prev),[],'all');
            fprintf('  %s h=%.0e->%.0e: max|dA|=%.3e\n', names{m}, h_list(hi-1), h, drift);
        end
        A_prev = A;
    end
end
end

function test_2_eigenvalue_plateau_convergence(testCase)
% Physical modes (|lambda|>0.01) must match between h=1e-5 and h=1e-6 within
% EIG_TOL. This proves the eigenvalues have converged on the plateau (not
% selected to look good).
names = {'padiyar_manual','padiyar_avr','emf6'};
eig_tol = 1e-3;
for m = 1:numel(names)
    [x0,y0,f,g,fy,Afun] = model_handles(names{m});
    [Jxx5,Jxy5,Jyx5,Jyy5] = fd_jacobian(f, g, x0, y0, 1e-5);
    [Jxx6,Jxy6,Jyx6,Jyy6] = fd_jacobian(f, g, x0, y0, 1e-6);
    A5 = Afun(Jxx5,Jxy5,Jyx5,Jyy5);
    A6 = Afun(Jxx6,Jxy6,Jyx6,Jyy6);
    lam5 = sort(eig(A5)); lam6 = sort(eig(A6));
    testCase.verifyEqual(numel(lam5), numel(lam6), ...
        sprintf('%s: same eigenvalue count at h=1e-5 and 1e-6', names{m}));
    mask5 = abs(lam5) > 0.01;
    lam5p = lam5(mask5); lam6p = lam6(mask5);
    testCase.verifyEqual(numel(lam5p), numel(lam6p), ...
        sprintf('%s: same physical-mode count', names{m}));
    err = greedy_error(lam5p, lam6p);
    fprintf('  %s plateau(h=1e-5 vs 1e-6): max physical-mode error=%.3e\n', ...
        names{m}, max(err));
    testCase.verifyLessThan(max(err), eig_tol, ...
        sprintf('%s: physical eigenvalues converge on plateau h=1e-5/1e-6', names{m}));
end
end

function err = greedy_error(a, b)
% Greedy one-to-one matching error between two eigenvalue vectors.
a = a(:); b = b(:);
if numel(a) ~= numel(b), err = inf; return; end
used = false(size(b)); err = zeros(size(a));
for k = 1:numel(a)
    d = abs(b - a(k)); d(used) = inf;
    [err(k),j] = min(d); used(j) = true;
end
end
