function result = multimachine_ssa(model)
%MULTIMACHINE_SSA General DAE small-signal stability engine.
% This is the common solver/linearisation core used by benchmark wrappers.
% It is intentionally case-agnostic: Kundur, Sauer-Pai, or any other
% multimachine benchmark supplies only f(x,y), g(x,y), x0, y0, and options.
%
% Required model fields:
%   x0, y0          equilibrium state/algebraic vectors
%   f, g            function handles f(x,y), g(x,y)
%
% Optional model fields:
%   Jxx,Jxy,Jyx,Jyy precomputed DAE Jacobian blocks. If absent, central
%                   finite differences are used.
%   fd_eps          finite-difference step, default 1e-6
%   free_y          algebraic variables to retain in Schur complement
%   reduction       'none' (default) or 'coi'
%   ng              machine count for COI reduction
%   states_per_machine
%   angle_state_index, speed_state_index
%   inertia         H or M weights for COI
%   state_names

arguments
    model struct
end

mustHave(model, 'x0'); mustHave(model, 'y0'); mustHave(model, 'f'); mustHave(model, 'g');
x0 = model.x0(:); y0 = model.y0(:);
nx = numel(x0); ny = numel(y0);
if isfield(model, 'fd_eps'); h = model.fd_eps; else; h = 1e-6; end

if all(isfield(model, {'Jxx','Jxy','Jyx','Jyy'}))
    Jxx = model.Jxx; Jxy = model.Jxy; Jyx = model.Jyx; Jyy = model.Jyy;
else
    [Jxx, Jxy, Jyx, Jyy] = finite_difference_jacobian(model.f, model.g, x0, y0, h);
end

if isfield(model, 'free_y') && ~isempty(model.free_y)
    free_y = model.free_y(:).';
else
    free_y = 1:ny;
end

% R4: Separate variable/residual ownership for voltage constraints.
% vcon_vars: algebraic variables whose perturbations are constrained.
% vcon_rows: residual rows (KCL) replaced by voltage/reference constraints.
% vcon_eq:   equations defining those constraints (FIXED y-only:
%            vcon_eq(y, constant_reference), so dvcon_eq/dx = 0 => Jcon_x=0).
% free_y and vcon are STRICTLY field-level mutually exclusive. When vcon is
% used, the COMPLETE vcon set (vcon_vars + vcon_rows + vcon_eq) is required.
% Dimensions: nr=size(Jyy,1) (residual rows); ny=size(Jyy,2) (variables).
% Reduced Jyy(free_rows, free_vars) must be SQUARE and full-rank.
nr = size(Jyy,1); ny_size = size(Jyy,2);
has_freey = isfield(model,'free_y') && ~isempty(model.free_y);
has_vcon  = isfield(model,'vcon_vars') || isfield(model,'vcon_rows') || isfield(model,'vcon_eq');
if has_freey && has_vcon
    error('multimachine_ssa:exclusiveOwnership', ...
        'free_y and vcon_* are strictly mutually exclusive.');
end
if has_vcon
    % Require the COMPLETE vcon set.
    vcon_fields = {'vcon_vars','vcon_rows','vcon_eq'};
    for k = 1:numel(vcon_fields)
        if ~isfield(model, vcon_fields{k})
            error('multimachine_ssa:partialVcon', ...
                'vcon requires the COMPLETE set: vcon_vars, vcon_rows, vcon_eq.');
        end
    end
    vcon_vars = model.vcon_vars(:).';
    vcon_rows = model.vcon_rows(:).';
    if numel(vcon_vars) ~= numel(vcon_rows)
        error('multimachine_ssa:vconMismatch', ...
            'vcon_vars (%d) and vcon_rows (%d) must have the same cardinality.', ...
            numel(vcon_vars), numel(vcon_rows));
    end
    free_vars = setdiff(1:ny_size, vcon_vars);
    free_rows = setdiff(1:nr, vcon_rows);
    if numel(free_vars) ~= numel(free_rows)
        error('multimachine_ssa:vconSquare', ...
            'Reduced Jyy would be %dx%d (non-square). free_vars=%d, free_rows=%d.', ...
            numel(free_rows), numel(free_vars), numel(free_vars), numel(free_rows));
    end
    % Validate indices: unique, finite integers, in range.
    all_idx = [vcon_vars, vcon_rows];
    if any(all_idx ~= floor(all_idx)) || any(all_idx < 1) || ...
       any(vcon_vars > ny_size) || any(vcon_rows > nr) || ...
       numel(unique(vcon_vars)) ~= numel(vcon_vars) || ...
       numel(unique(vcon_rows)) ~= numel(vcon_rows)
        error('multimachine_ssa:vconBadIndex', ...
            'vcon indices must be unique finite integers in range.');
    end
    % B6: vcon/model.g value + Jx + Jy consistency + reduced-Jyy rcond.
    % Runtime ABI: model.vcon_eq(x, y) (frozen per B4). The checker uses
    % multimachine_ssa's OWN scalar model.fd_eps (default 1e-6) as a FIXED
    % absolute central-difference step (NOT ts_jac_y_fd's scale-aware rule —
    % different module/scheme; the two are NOT claimed to match).
    vcon_eq_fn = model.vcon_eq;
    g_vcon = vcon_eq_fn(model.x0, model.y0);
    if numel(g_vcon) ~= numel(vcon_rows)
        error('multimachine_ssa:vconEqDim', ...
            'vcon_eq output length %d must match vcon_rows length %d.', ...
            numel(g_vcon), numel(vcon_rows));
    end
    h_fd = 1e-6;
    if isfield(model,'fd_eps') && ~isempty(model.fd_eps), h_fd = model.fd_eps; end
    % FROZEN thresholds (B6, declared a-priori):
    V_FLOOR = 1e-8; J_FLOOR = 1e-8;
    VAL_TOL = 1e-6; JX_TOL = 1e-6; JY_TOL = 1e-6;
    RCOND_MIN = 1e-10; FD_STAB_TOL = 1e-4;
    % --- Value consistency: model.g(vcon_rows) == vcon_eq(x0,y0) ---
    g_rows = model.g(model.x0, model.y0);
    if iscolumn(g_rows), g_rows = g_rows(vcon_rows); else, g_rows = g_rows(vcon_rows); end
    rel_val = max(abs(g_rows - g_vcon)) / (max(abs(g_rows)) + max(abs(g_vcon)) + V_FLOOR);
    if rel_val > VAL_TOL
        error('multimachine_ssa:vconInconsistent', ...
            'model.g(vcon_rows) != vcon_eq(x0,y0) (rel_val=%.3e > %.0e).', rel_val, VAL_TOL);
    end
    % --- Compute Jcon_x = dvcon_eq/dx by central differences (h vs h/2) ---
    [Jcon_x, ~] = fd_jac_x(vcon_eq_fn, model.x0, model.y0, h_fd, FD_STAB_TOL);
    % (a) Jx row-equivalence: Jyx(vcon_rows,:) == Jcon_x (declared rows ARE
    %     the constraint rows). Checking Jcon_x ALONE does NOT prove model.g
    %     rows have no state coupling.
    rel_jx_eq = max(abs(Jyx(vcon_rows,:) - Jcon_x),[],'all') / ...
        (max(abs(Jyx(vcon_rows,:)),[],'all') + J_FLOOR);
    if rel_jx_eq > JX_TOL
        error('multimachine_ssa:vconJacobianMismatch', ...
            'Jyx(vcon_rows,:) != Jcon_x (rel=%.3e > %.0e).', rel_jx_eq, JX_TOL);
    end
    % (b) Fixed-y-only zero: Jcon_x ~= 0 (dvcon_eq/dx = 0).
    rel_jx_zero = max(abs(Jcon_x(:))) / (max(abs(Jcon_x(:))) + J_FLOOR + 1);
    % Scale by the largest Jy entry for a meaningful relative measure.
    if rel_jx_zero > JX_TOL
        error('multimachine_ssa:vconStateCoupling', ...
            'vcon_eq is state-dependent (max|Jcon_x|=%.3e). Only FIXED y-only supported.', ...
            max(abs(Jcon_x(:))));
    end
    % --- Compute Jcon_y_full = dvcon_eq/dy (ALL ny columns, h vs h/2) ---
    [Jcon_y_full, ~] = fd_jac_y(vcon_eq_fn, model.x0, model.y0, h_fd, FD_STAB_TOL);
    % Full-row Jacobian consistency: Jyy(vcon_rows,:) == Jcon_y_full (FULL row).
    rel_jy = max(abs(Jyy(vcon_rows,:) - Jcon_y_full),[],'all') / ...
        (max(abs(Jyy(vcon_rows,:)),[],'all') + J_FLOOR);
    if rel_jy > JY_TOL
        error('multimachine_ssa:vconJacobianMismatch', ...
            'Jyy(vcon_rows,:) != dvcon_eq/dy (rel=%.3e > %.0e).', rel_jy, JY_TOL);
    end
    % Reduced conditioning: rcond(Jyy(free_rows,free_vars)) before backslash.
    rc = rcond(Jyy(free_rows,free_vars));
    if rc < RCOND_MIN
        error('multimachine_ssa:singularReducedJyy', ...
            'Reduced Jyy(free_rows,free_vars) ill-conditioned (rcond=%.3e < %.0e).', ...
            rc, RCOND_MIN);
    end
    % Paired Schur with separate free_rows/free_vars.
    Afull = Jxx - Jxy(:,free_vars) * (Jyy(free_rows,free_vars) \ Jyx(free_rows,:));
    free_y_used = free_vars;   % for metadata
elseif has_freey
    free_vars = free_y; free_rows = free_y;
    Afull = Jxx - Jxy(:,free_vars) * (Jyy(free_rows,free_vars) \ Jyx(free_rows,:));
    free_y_used = free_vars;
else
    Afull = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
    free_y_used = free_y;
end
lambda_full = eig(Afull);
[Vfull, ~] = eig(Afull);

Ared = Afull; lambda_reduced = lambda_full; Vreduced = Vfull; T = eye(nx); keep = 1:nx;
if isfield(model, 'reduction') && strcmpi(model.reduction, 'coi')
    required = {'ng','states_per_machine','angle_state_index','speed_state_index','inertia'};
    for k = 1:numel(required); mustHave(model, required{k}); end
    [Ared, keep, T] = reduce_coi(Afull, model.ng, model.states_per_machine, ...
        model.angle_state_index, model.speed_state_index, model.inertia);
    lambda_reduced = eig(Ared);
    [Vreduced, ~] = eig(Ared);
end

result = struct();
result.Afull = Afull;
result.Ared = Ared;
result.Jxx = Jxx; result.Jxy = Jxy; result.Jyx = Jyx; result.Jyy = Jyy;
result.free_y = free_y_used;
result.eigenvalues = lambda_full;
result.reduced_eigenvalues = lambda_reduced;
result.mode_shapes = Vfull;
result.reduced_mode_shapes = Vreduced;
result.frequency_Hz = abs(imag(lambda_full))/(2*pi);
result.damping_ratio = -real(lambda_full)./(abs(lambda_full)+eps);
result.stable = all(real(lambda_full) < -1e-9);
result.reduced_frequency_Hz = abs(imag(lambda_reduced))/(2*pi);
result.reduced_damping_ratio = -real(lambda_reduced)./(abs(lambda_reduced)+eps);
result.reduced_stable = all(real(lambda_reduced) < -1e-9);
result.T_reduction = T;
result.keep = keep;
if isfield(model, 'state_names'); result.state_names = model.state_names; end
if isfield(model, 'metadata'); result.metadata = model.metadata; end
end

function [Jxx,Jxy,Jyx,Jyy] = finite_difference_jacobian(fhandle, ghandle, x0, y0, h)
nx = numel(x0); ny = numel(y0);
f0 = fhandle(x0,y0); g0 = ghandle(x0,y0); %#ok<NASGU>
nf = numel(f0); ng = numel(g0);
Jxx = zeros(nf,nx); Jxy = zeros(nf,ny); Jyx = zeros(ng,nx); Jyy = zeros(ng,ny);
for i = 1:nx
    xp = x0; xm = x0; xp(i) = xp(i)+h; xm(i) = xm(i)-h;
    Jxx(:,i) = (fhandle(xp,y0) - fhandle(xm,y0))/(2*h);
    Jyx(:,i) = (ghandle(xp,y0) - ghandle(xm,y0))/(2*h);
end
for j = 1:ny
    yp = y0; ym = y0; yp(j) = yp(j)+h; ym(j) = ym(j)-h;
    Jxy(:,j) = (fhandle(x0,yp) - fhandle(x0,ym))/(2*h);
    Jyy(:,j) = (ghandle(x0,yp) - ghandle(x0,ym))/(2*h);
end
end

function [Arel, keep, T] = reduce_coi(Afull, ng, ns, angle_idx, speed_idx, inertia)
% Generic COI projection.  It assumes each machine has the same number of
% states and the angle/speed locations are identical in each machine block.
Hn = inertia(:)/sum(inertia(:));
nx = size(Afull,1);
remove = false(nx,1);
remove(angle_idx) = true;
remove(speed_idx) = true;
nred = nx - 2;
T = zeros(nx,nred);
keep_mask = false(nx,1);
c = 1;
% Machine 1: angle/speed absorbed into COI, keep all other states.
for s = 1:ns
    if s == angle_idx || s == speed_idx; continue; end
    T(s,c) = 1; keep_mask(s) = true; c = c+1;
end
% Machines 2..ng: relative angle/speed and all other states.
for k = 2:ng
    base = (k-1)*ns;
    T(base+angle_idx,c) = 1;
    for kk = 1:ng
        T((kk-1)*ns+angle_idx,c) = T((kk-1)*ns+angle_idx,c) - Hn(kk);
    end
    keep_mask(base+angle_idx) = true; c = c+1;
    T(base+speed_idx,c) = 1;
    for kk = 1:ng
        T((kk-1)*ns+speed_idx,c) = T((kk-1)*ns+speed_idx,c) - Hn(kk);
    end
    keep_mask(base+speed_idx) = true; c = c+1;
    for s = 1:ns
        if s == angle_idx || s == speed_idx; continue; end
        T(base+s,c) = 1; keep_mask(base+s) = true; c = c+1;
    end
end
keep = find(keep_mask);
Arel = pinv(T) * Afull * T;
end

function mustHave(s, name)
if ~isfield(s, name)
    error('multimachine_ssa:missingField', 'Model is missing required field "%s".', name);
end
end

function [J, stable] = fd_jac_x(fn, x0, y0, h, stab_tol)
%FD_JAC_X  Central-difference dvcon_eq/dx with h-vs-h/2 stabilization (B6).
%   No |f'''|=O(1) assumption; stabilization gates the comparison.
nr = numel(fn(x0, y0)); nx = numel(x0);
J = zeros(nr, nx);
for j = 1:nx
    xp = x0; xm = x0; xp(j) = xp(j) + h; xm(j) = xm(j) - h;
    J(:,j) = (fn(xp, y0) - fn(xm, y0)) / (2*h);
end
% h-vs-h/2 stabilization: recompute at h/2 and check agreement.
J2 = zeros(nr, nx);
for j = 1:nx
    xp = x0; xm = x0; xp(j) = xp(j) + h/2; xm(j) = xm(j) - h/2;
    J2(:,j) = (fn(xp, y0) - fn(xm, y0)) / (2*(h/2));
end
rel = max(abs(J - J2),[],'all') / (max(abs(J),[],'all') + max(abs(J2),[],'all') + 1e-12);
if rel > stab_tol
    error('multimachine_ssa:fdUnstable', ...
        'FD dvcon_eq/dx unstable at h=%.2e (h-vs-h/2 rel change=%.3e > %.0e).', h, rel, stab_tol);
end
stable = true;
end

function [J, stable] = fd_jac_y(fn, x0, y0, h, stab_tol)
%FD_JAC_Y  Central-difference dvcon_eq/dy (ALL ny cols) with h-vs-h/2 (B6).
nr = numel(fn(x0, y0)); ny = numel(y0);
J = zeros(nr, ny);
for j = 1:ny
    yp = y0; ym = y0; yp(j) = yp(j) + h; ym(j) = ym(j) - h;
    J(:,j) = (fn(x0, yp) - fn(x0, ym)) / (2*h);
end
J2 = zeros(nr, ny);
for j = 1:ny
    yp = y0; ym = y0; yp(j) = yp(j) + h/2; ym(j) = ym(j) - h/2;
    J2(:,j) = (fn(x0, yp) - fn(x0, ym)) / (2*(h/2));
end
rel = max(abs(J - J2),[],'all') / (max(abs(J),[],'all') + max(abs(J2),[],'all') + 1e-12);
if rel > stab_tol
    error('multimachine_ssa:fdUnstable', ...
        'FD dvcon_eq/dy unstable at h=%.2e (h-vs-h/2 rel change=%.3e > %.0e).', h, rel, stab_tol);
end
stable = true;
end
