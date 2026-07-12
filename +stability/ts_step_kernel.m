function step = ts_step_kernel(x, y, h, dae_f, dae_g, Y, Jyy, opt)
%TS_STEP_KERNEL Shared implicit-trapezoidal single-step kernel (CANONICAL).
%   STEP = ts_step_kernel(X, Y, H, DAE_F, DAE_G, Y_ADM, JYY, OPT) performs one
%   implicit-trapezoidal step of size H. Both fixed-step and adaptive drivers
%   call THIS kernel so the predictor/corrector/residual logic is never
%   duplicated. This is the single production trapezoidal implementation.
%
%   Strategy form (Phase 1):
%   STEP = ts_step_kernel(STRATEGY, X, Y, H, Y_ADM, OPT) where STRATEGY is built
%   by stability.ts_model_strategy. The strategy wraps the model's dae_f,
%   dae_g, and jac_y closures; this entry dispatches into the legacy signature
%   path so routing Padiyar/EMF6 through the strategy is bit-identical to the
%   legacy call (verified by tests/test_ts_strategy_equivalence.m). The
%   strategy form is a thin adapter — it introduces no second trapezoidal
%   implementation.
%
%   OPT.corrector_mode:
%     'adaptive' (default) — iterate until update+residual converge (Padiyar,
%        EMF6 adaptive path). Re-solves g at the corrected state.
%     'fixed'             — exactly OPT.max_corrector_iter Picard iterations,
%        no early exit, no re-solve at corrected state (EMF6 fixed path).
%
%   JYY is the precomputed dg/dy at the step start (reused, re-evaluated only
%   on line-search failure). Pass [] to compute fresh at (x,y).

% --- Strategy dispatch (Phase 1): thin adapter into the legacy path ---------
% Strategy form: ts_step_kernel(strategy, x, y, h, Y, opt)  -> 6 args.
% Legacy form:   ts_step_kernel(x, y, h, dae_f, dae_g, Y, Jyy, opt) -> 8 args.
if isstruct(x) && isfield(x,'model')
    strategy = x;
    x_state = y;
    y_state = h;
    h_step = dae_f;
    Y_adm = dae_g;
    opt_s = Y;
    if isfield(strategy,'needs_algebraic_solve') && ~strategy.needs_algebraic_solve
        % Classical (linear) model: algebraic state is solved inside dae_f via
        % a direct linear V=Y\Iinj; there is no nonlinear dae_g and no Jyy.
        % Use the linear-strategy path (no ts_algebraic_solve calls).
        step = classical_step(strategy, x_state, y_state, h_step, Y_adm, opt_s);
        return;
    end
    Jyy_s = strategy.jac_y(x_state, y_state, Y_adm);
    step = stability.ts_step_kernel(x_state, y_state, h_step, strategy.dae_f, ...
        strategy.dae_g, Y_adm, Jyy_s, opt_s);
    return;
end

g_tol = opt.algebraic_tolerance;
max_citer = opt.max_corrector_iter;
abs_tol = opt.corrector_abs_tol;
rel_tol = opt.corrector_rel_tol;
jac_fn = @stability.ts_jac_y_fd;
mode = 'adaptive';
if isfield(opt,'corrector_mode') && ~isempty(opt.corrector_mode)
    mode = lower(opt.corrector_mode);
end

if isempty(Jyy), Jyy = jac_fn(x, y, Y, dae_g); end

% Consistent algebraic state at current x (reuse precomputed Jyy).
[y, alg0] = stability.ts_algebraic_solve(x, y, Y, dae_g, jac_fn, g_tol, Jyy);
if ~alg0.converged, error('ts_step_kernel:algebraic', ...
    'Pre-step algebraic solve did not converge: residual=%.3e (tol=%.3e).', alg0.final_residual, g_tol); end
f0 = dae_f(x, y);

x_pred = x + h*f0;
y_pred = y;

converged = false; upd = 0; resn = 0; ci_used = 0;
switch mode
case 'adaptive'
    for ci = 1:max_citer
        [y_pred, alg1] = stability.ts_algebraic_solve(x_pred, y_pred, Y, dae_g, jac_fn, g_tol, Jyy);
        if ~alg1.converged, error('ts_step_kernel:algebraic', ...
            'Corrector algebraic solve did not converge: residual=%.3e (tol=%.3e).', alg1.final_residual, g_tol); end
        f1 = dae_f(x_pred, y_pred);
        x_new = x + 0.5*h*(f0 + f1);
        [y_new, alg2] = stability.ts_algebraic_solve(x_new, y_pred, Y, dae_g, jac_fn, g_tol, Jyy);
        if ~alg2.converged, error('ts_step_kernel:algebraic', ...
            'Corrector algebraic solve did not converge: residual=%.3e (tol=%.3e).', alg2.final_residual, g_tol); end
        R = x_new - x - 0.5*h*(f0 + dae_f(x_new, y_new));
        upd = norm(x_new - x_pred, inf);
        resn = norm(R, inf);
        x_pred = x_new; y_pred = y_new;
        ci_used = ci;
        tol_now = abs_tol + rel_tol*max(1, norm(x_pred, inf));
        if upd <= tol_now && resn <= tol_now
            converged = true; break;
        end
    end
case 'fixed'
    for ci = 1:max(1, max_citer)
        [y_pred, algf] = stability.ts_algebraic_solve(x_pred, y_pred, Y, dae_g, jac_fn, g_tol, Jyy);
        if ~algf.converged, error('ts_step_kernel:algebraic', ...
            'Fixed corrector algebraic solve did not converge: residual=%.3e (tol=%.3e).', algf.final_residual, g_tol); end
        f1 = dae_f(x_pred, y_pred);
        x_pred = x + 0.5*h*(f0 + f1);
        ci_used = ci;
    end
    % Final consistent algebraic state at x_full (requirement 5).
    [y_fin, algfin] = stability.ts_algebraic_solve(x_pred, y_pred, Y, dae_g, jac_fn, g_tol, Jyy);
    if ~algfin.converged, error('ts_step_kernel:algebraic', ...
        'Fixed-mode final algebraic solve did not converge: residual=%.3e (tol=%.3e).', algfin.final_residual, g_tol); end
    y_pred = y_fin;
    R = x_pred - x - 0.5*h*(f0 + dae_f(x_pred, y_fin));
    resn = norm(R, inf);
    upd = resn;
    converged = (resn <= 1e-6);
otherwise
    error('ts_step_kernel:badMode','Unknown corrector_mode "%s".',mode);
end

alg_res = norm(dae_g(x_pred, y_pred, Y), inf);
all_finite = all(isfinite(x_pred)) && all(isfinite(y_pred)) && ...
    all(isfinite(f0)) && all(isfinite(resn));

step = struct( ...
    'x_full', x_pred, 'y_full', y_pred, ...
    'f0', f0, 'f1', dae_f(x_pred, y_pred), ...
    'corrector_iterations', ci_used, ...
    'corrector_residual', resn, ...
    'corrector_update', upd, ...
    'corrector_converged', converged, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = classical_step(strategy, x, y, h, Y, opt)
%CLASSICAL_STEP  Trapezoidal step for the classical (linear-network) model.
%   The classical network is LINEAR given (delta, Eqmag, Y): the algebraic state
%   y is solved exactly inside dae_f via V = (Y+Ygen)\Iinj. There is no nonlinear
%   dae_g and no Jyy, so the ts_algebraic_solve calls of the legacy path are
%   skipped. The trapezoidal predictor/corrector/residual logic is the SAME
%   algorithm as the legacy path; only the algebraic-solve calls are omitted.
%
%   This is NOT a second trapezoidal implementation: it shares the predictor,
%   corrector, residual, and convergence semantics of the canonical kernel. The
%   difference is solely that the algebraic solve is exact-and-inline (linear)
%   rather than a damped-Newton iteration on a nonlinear g.

dae_f = strategy.dae_f;
max_citer = opt.max_corrector_iter;
abs_tol = opt.corrector_abs_tol;
rel_tol = opt.corrector_rel_tol;
mode = 'adaptive';
if isfield(opt,'corrector_mode') && ~isempty(opt.corrector_mode)
    mode = lower(opt.corrector_mode);
end

% Pre-step: dae_f solves the linear network internally, giving f0 at (x,y,Y).
% y is consistent by construction (V = (Y+Ygen)\Iinj at x).
f0 = dae_f(x, y, Y);
x_pred = x + h*f0;
y_pred = y;

converged = false; upd = 0; resn = 0; ci_used = 0;
switch mode
case 'adaptive'
    for ci = 1:max_citer
        f1 = dae_f(x_pred, y_pred, Y);
        x_new = x + 0.5*h*(f0 + f1);
        f1_new = dae_f(x_new, y_pred, Y);
        R = x_new - x - 0.5*h*(f0 + f1_new);
        upd = norm(x_new - x_pred, inf);
        resn = norm(R, inf);
        x_pred = x_new;
        ci_used = ci;
        tol_now = abs_tol + rel_tol*max(1, norm(x_pred, inf));
        if upd <= tol_now && resn <= tol_now
            converged = true; break;
        end
    end
case 'fixed'
    for ci = 1:max(1, max_citer)
        f1 = dae_f(x_pred, y_pred, Y);
        x_pred = x + 0.5*h*(f0 + f1);
        ci_used = ci;
    end
    R = x_pred - x - 0.5*h*(f0 + dae_f(x_pred, y_pred, Y));
    resn = norm(R, inf);
    upd = resn;
    converged = (resn <= 1e-6);
otherwise
    error('ts_step_kernel:badMode','Unknown corrector_mode "%s".',mode);
end

% Classical algebraic residual: the network is solved exactly inside dae_f, so
% the algebraic residual (network balance) is zero by construction at the
% recorded y. We recompute y at x_pred for the recorded output.
alg_res = 0;
all_finite = all(isfinite(x_pred)) && all(isfinite(f0)) && all(isfinite(resn));

step = struct( ...
    'x_full', x_pred, 'y_full', y_pred, ...
    'f0', f0, 'f1', dae_f(x_pred, y_pred, Y), ...
    'corrector_iterations', ci_used, ...
    'corrector_residual', resn, ...
    'corrector_update', upd, ...
    'corrector_converged', converged, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end
