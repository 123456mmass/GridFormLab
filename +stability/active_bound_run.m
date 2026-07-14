function [z_sol, niter, converged, res_norm, rcond_val] = active_bound_run( ...
    z0, base_residual_fn, fd_eps, ...
    active_x_idx, frozen_x_idx, frozen_x_val, ...
    free_vars, vcon_vars, vcon_ref, ny_full, u_base, ...
    all_specs, eq_ctx, tol, max_iter, verbose)
%active_bound_run  Active-set outer loop for G2 equilibrium.
%  Pre-declared constants (NUMERICAL_METHOD): max_outer = 5.

MAX_OUTER = 5;

cur_regime = stability.active_bound_classify(z0, active_x_idx, ...
    frozen_x_idx, frozen_x_val, free_vars, vcon_vars, vcon_ref, ...
    ny_full, u_base, all_specs, eq_ctx);
history = {cur_regime};

total_iters = 0;
z_current = z0;

for outer = 1:MAX_OUTER
    locked = history{end};

    % locked residual——replace saturated rows with x - ub or x - lb
    wres = @(wz) make_residual(wz, base_residual_fn, locked, ...
        active_x_idx, all_specs);

    % FD Jacobian from locked residual
    wjac = @(wz) fd_jacobian(wz, wres, fd_eps);

    [z_next, ni, cv, rn, rc] = stability.composite_newton( ...
        z_current, wres, wjac, tol, max_iter, verbose);
    total_iters = total_iters + ni;

    if ~cv
        z_sol = z_next; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        return;
    end

    % reclassify at solution
    new_regime = stability.active_bound_classify(z_next, active_x_idx, ...
        frozen_x_idx, frozen_x_val, free_vars, vcon_vars, vcon_ref, ...
        ny_full, u_base, all_specs, eq_ctx);

    % admissibility
    adm = check_admissible(z_next, locked, active_x_idx, ...
        frozen_x_idx, frozen_x_val, free_vars, vcon_vars, vcon_ref, ...
        ny_full, u_base, all_specs, eq_ctx);

    if regime_same(new_regime, locked)
        z_sol = z_next; niter = total_iters;
        converged = adm; res_norm = rn; rcond_val = rc;
        return;
    end

    if regime_seen(new_regime, history)
        z_sol = z_next; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        return;
    end

    history{end+1} = new_regime; %#ok<AGROW>
    z_current = z_next;
end

z_sol = z_current; niter = total_iters;
converged = false; res_norm = inf; rcond_val = NaN;
end

% ====================================================================
function r = make_residual(z, base_fn, locked, active_x, specs)
r = base_fn(z);
for dk = 1:numel(specs)
    entry = specs{dk};
    if isempty(entry), continue; end
    for sp = 1:numel(entry.specs)
        reg = find_reg(locked, dk, entry.specs(sp).local_idx);
        if isempty(reg) || strcmp(reg, 'interior')
            continue;
        end
        gidx = entry.offset + entry.specs(sp).local_idx;
        zp = find(active_x == gidx, 1, 'first');
        if isempty(zp), continue; end

        if strcmp(reg, 'upper')
            r(zp) = z(zp) - entry.specs(sp).upper_bound;
        elseif strcmp(reg, 'lower')
            r(zp) = z(zp) - entry.specs(sp).lower_bound;
        end
    end
end
end

% ====================================================================
function J = fd_jacobian(z, fn, h)
% disk forward-difference Jacobian
nz = numel(z);
r0 = fn(z);
if numel(r0) ~= nz
    error('active_bound:size', 'residual size %d != vars %d', numel(r0), nz);
end
J = zeros(nz);
for j = 1:nz
    zp = z; zp(j) = zp(j) + h;
    rp = fn(zp);
    J(:, j) = (rp - r0) / h;
end
end

% ====================================================================
function reg = find_r(locked, dev_idx, local_idx)
    reg = '';
    for i = 1:numel(locked)
        if locked(i).dev_idx == dev_idx && locked(i).local_idx == local_idx
            reg = locked(i).regime;
            return;
        end
    end
end

% ====================================================================
function ok = check_admissible(z, locked, ax, fx, fxv, fv, vcv, vcr, ...
    ny, ub, specs, eqx)
% Using blindly, reconstruct x/y for each constraint. calls admissible_fn
    nt = numel(ax) + numel(fx);
    x_full = zeros(nt, 1);
    x_full(ax) = z(1:numel(ax));
    for fi = 1:numel(fx)
        x_full(fx(fi)) = fxv(fi);
    end

    ny_free = numel(fv);
    y_full = zeros(ny, 1);
    y_free = z(numel(ax)+1 : numel(ax)+ny_free);
    y_full(fv) = y_free;
    y_full(vcv) = vcr;

    ok = true;
    for dk = 1:numel(specs)
        en = specs{dk};
        if isempty(en), continue; end
        x_d = x_full(en.offset+1 : en.offset + en.dev_nx);
        u_d = [];
        if en.dev_nu > 0
            u_d = ub(en.u_offset+1 : en.u_offset + en.dev_nu);
        end
        for sp = 1:numel(en.specs)
            for ni = 1:numel(locked)
                if locked(ni).dev_idx == dk && ...
                   locked(ni).local_idx == en.specs(sp).local_idx
                    reg = locked(ni).regime;
                    if ~en.specs(sp).admissible_fn(x_d, y_full, u_d, eqx, reg)
                        ok = false;
                        return;
                    end
                end
            end
        end
    end
end

% ====================================================================
function tf = regime_same(a, b)
    na = numel(a);
    if na ~= numel(b)
        tf = false; return;
    end
    for k = 1:na
        if a(k).dev_idx ~= b(k).dev_idx, tf = false; return; end
        if a(k).local_idx ~= b(k).local_idx, tf = false; return; end
        if ~strcmp(a(k).regime, b(k).regime), tf = false; return; end
    end
    tf = true;
end

% ====================================================================
function tf = regime_seen(reg, hist)
    tf = false;
    for h = 1:numel(hist)
        if regime_same(reg, hist{h})
            tf = true;
            return;
        end
    end
end