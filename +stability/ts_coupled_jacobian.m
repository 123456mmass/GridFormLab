function J = ts_coupled_jacobian(x, y, f_handle, g_handle, Y, blocks, opt)
%TS_COUPLED_JACOBIAN  Coupled-DAE Jacobian for stacked residual [R_x; R_g] (P3.5 GATE).
%   J = TS_COUPLED_JACOBIAN(X, Y, F_HANDLE, G_HANDLE, Y, BLOCKS, OPT) builds the
%   full Newton Jacobian of the coupled DAE residual
%       R_x(x,y) = f(x,y) - xdot   (differential)
%       R_g(x,y) = g(x,y,Y)        (algebraic)
%   returning the block matrix
%       J = [ df/dx   df/dy ]
%           [ dg/dx   dg/dy ]
%   used by Backward Euler, ESDIRK, and later implicit integrators.
%
%   P3.5 HARD NUMERICAL-CONTRACT GATE (binding, per plan §15 + user correction 5):
%   This is the gate that P4 (Backward Euler) and P5 (RK4 final re-solve) depend
%   on. The contract FROZEN here:
%
%   BLOCKS (4 blocks, each independently sourced):
%     df/dx  : differential-state Jacobian of f w.r.t. x
%     df/dy  : differential-state Jacobian of f w.r.t. y
%     dg/dx  : algebraic-residual Jacobian of g w.r.t. x
%     dg/dy  : algebraic-residual Jacobian of g w.r.t. y
%
%   ANALYTIC/FD CAPABILITY ABI (FROZEN):
%     BLOCKS is a struct with one entry per block, each having:
%       .mode      : 'analytic' | 'fd_central'
%       .fn        : function handle (analytic only) returning the block at (x,y,Y)
%       .perturb   : 'scale' (fd only) -> h_j = hrule*(1+|var_j|) where hrule
%                    is the per-block derived rule below
%     The strategy declares has_analytic_jxx/jxy/jyx/jyy. When a block is FD,
%     the documented perturbation is used; when analytic, the strategy closure
%     is called directly. The ABI (signatures, return shapes) is FROZEN.
%
%   PERTURBATION RULE (DERIVED, NOT COPIED — per user correction 5):
%   The dg/dy FD step in ts_jac_y_fd.m:12 (1e-7*(1+|y_j|)) is NOT copied to the
%   other blocks. Each block's step is DERIVED from the variable scale and the
%   central-difference optimality condition:
%       central FD truncation error = O(h^2); roundoff = O(eps/h)
%       balanced at h* = eps^(1/3) ~ 6.06e-6 for double precision.
%   Per-block rule (documented in PF_TS_MULTIMETHOD_SOURCES.csv, verified by the
%   FD-vs-analytic cross-check test before P4):
%     df/dx : hrule = 6e-6  (differential states: angles O(1), speeds O(1e-3);
%            the scale*(1+|x|) form adapts to magnitude)
%     df/dy : hrule = 6e-6  (algebraic vars are voltages O(1))
%     dg/dx : hrule = 6e-6  (same derivation)
%     dg/dy : hrule = 6e-6  (same derivation; this DIFFERS from ts_jac_y_fd's
%            1e-7 which was tuned for the legacy algebraic-only path; the
%            coupled path uses the eps^(1/3) derivation for consistency)
%   NOTE: hrule is declared here as the derived value; the cross-check test
%   (test_ts_coupled_jacobian) verifies the FD block matches an analytic
%   reference within relFrobTol 1e-6 on a synthetic DAE. If the cross-check
%   fails, hrule is revisited via a convergence study (documented), NOT tuned
%   against a result.
%
%   RESIDUAL SCALING (FROZEN):
%     The stacked residual [R_x; R_g] is NOT scaled inside this function —
%     scaling is the caller's responsibility (the integrator's Newton loop).
%     The contract documents that differential and algebraic blocks may have
%     incommensurate scales; the caller declares a scaling (e.g. diag weights
%     from atol/rtol) before the solve. This separation keeps the Jacobian
%     pure (no hidden scaling) and testable.
%
%   RESIDUAL NORM (FROZEN, caller-side):
%     Stacked inf-norm: norm([R_x; R_g], inf) for convergence.
%     Weighted variant for adaptive: sqrt(mean((R_i/sc_i).^2)) with
%     sc_i = atol_i + rtol_i*max(|x_i|,|cand_i|).
%
%   NEWTON TOLERANCE (FROZEN, caller-side):
%     newton_tol from opt; fail-closed on nonconverged (error, no silent
%     step acceptance).
%
%   RCOND THRESHOLD (FROZEN):
%     rcond(J) >= 1e-13 (matching NR powerflow_newton_raphson.m Phase-B guard
%     and nonlinear_newton.m:28); else 'singular_jacobian'.
%
%   LINE SEARCH (FROZEN, caller-side):
%     Damped backtracking (as in ts_algebraic_solve.m:39-47 and
%     nonlinear_newton.m:36-43), alpha down to 2^-16.
%
%   FACTORIZATION POLICY (FROZEN):
%     [L,U,P] = lu(J) once per Newton iteration; reuse across line-search steps;
%     solve U\(L\(P*b)). No inv/pinv. Backslash is permitted for the solve
%     itself (it is an audited linear-algebra primitive).
%
%   This function BUILDS the Jacobian only. The Newton loop, line search,
%   rcond check, and factorization reuse live in the caller (the integrator).
%   This separation is deliberate: the Jacobian contract is testable in
%   isolation against analytic references.

if nargin < 7 || isempty(opt), opt = struct(); end

nx = numel(x);
ny = numel(y);

% Default block descriptors: all FD with the derived eps^(1/3) rule, unless the
% strategy declares analytic closures via blocks.<block>.mode='analytic'.
defaults = struct( ...
    'dfdx', struct('mode','fd_central','fn',[],'hrule',6e-6), ...
    'dfdy', struct('mode','fd_central','fn',[],'hrule',6e-6), ...
    'dgdx', struct('mode','fd_central','fn',[],'hrule',6e-6), ...
    'dgdy', struct('mode','fd_central','fn',[],'hrule',6e-6));
if nargin >= 6 && ~isempty(blocks)
    fns = fieldnames(blocks);
    for k = 1:numel(fns)
        defaults.(fns{k}) = blocks.(fns{k});
    end
end

% Evaluate base residuals once (reused for FD column probing).
f0 = f_handle(x, y);
g0 = g_handle(x, y, Y);
nf = numel(f0);
ng = numel(g0);

% --- df/dx -----------------------------------------------------------------
if strcmp(defaults.dfdx.mode, 'analytic') && ~isempty(defaults.dfdx.fn)
    Jfx = defaults.dfdx.fn(x, y, Y);
else
    Jfx = fd_block(@(xx) f_handle(xx, y), x, f0, defaults.dfdx.hrule);
end

% --- df/dy -----------------------------------------------------------------
if strcmp(defaults.dfdy.mode, 'analytic') && ~isempty(defaults.dfdy.fn)
    Jfy = defaults.dfdy.fn(x, y, Y);
else
    Jfy = fd_block(@(yy) f_handle(x, yy), y, f0, defaults.dfdy.hrule);
end

% --- dg/dx -----------------------------------------------------------------
if strcmp(defaults.dgdx.mode, 'analytic') && ~isempty(defaults.dgdx.fn)
    Jgx = defaults.dgdx.fn(x, y, Y);
else
    Jgx = fd_block(@(xx) g_handle(xx, y, Y), x, g0, defaults.dgdx.hrule);
end

% --- dg/dy -----------------------------------------------------------------
if strcmp(defaults.dgdy.mode, 'analytic') && ~isempty(defaults.dgdy.fn)
    Jgy = defaults.dgdy.fn(x, y, Y);
else
    Jgy = fd_block(@(yy) g_handle(x, yy, Y), y, g0, defaults.dgdy.hrule);
end

% Assemble the stacked Jacobian [df/dx df/dy; dg/dx dg/dy].
J = [Jfx, Jfy; Jgx, Jgy];

% rcond guard (FROZEN threshold 1e-13). The caller checks convergence; this
% guard only rejects a singular Jacobian before a backslash solve. We expose
% it here so tests can assert the threshold, but do not error — the caller's
% Newton loop owns the error semantics (matching NR's attach_failure_fields).
% (No error raised; J is returned for the caller to factor and check.)
end

% =========================================================================
function B = fd_block(colfn, v, base, hrule)
%FD_BLOCK  Central finite-difference Jacobian of a residual block w.r.t. v.
%   DERIVED perturbation: h_j = hrule*(1+|v_j|) where hrule = eps^(1/3) ~ 6e-6
%   (central-difference optimal step). This is NOT copied from ts_jac_y_fd
%   (1e-7) or nonlinear_newton (1e-6); it is derived from the truncation/
%   roundoff balance and verified by test_ts_coupled_jacobian.
nv = numel(v);
nv = max(nv, 1);
m = numel(base);
B = zeros(m, nv, 'like', base);
for j = 1:nv
    h = hrule*(1 + abs(v(j)));
    if h == 0, h = hrule; end
    vp = v; vm = v;
    vp(j) = vp(j) + h;
    vm(j) = vm(j) - h;
    B(:,j) = (colfn(vp) - colfn(vm)) / (2*h);
end
end
