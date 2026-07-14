function [z_sol, niter, converged, res_norm, rcond_val, ...
          fail_id, fail_reason, outer_iters, regime_history] = ...
    active_bound_run(z0, base_residual_fn, fd_eps, ...
    active_x_idx, frozen_x_idx, frozen_x_val, ...
    free_vars, vcon_vars, vcon_ref, ny_full, u_base, slack_u_idx, ...
    all_specs, eq_ctx, tol, max_iter, verbose)
%active_bound_run  Active-set outer loop for G2 equilibrium (corrective patch).
%
%  Pre-declared (NUMERICAL_METHOD): max_outer = 5.
%  Failure IDs returned on any failure; '' on success.

MAX_OUTER = 5;

% convenience sizes
nx_active = numel(active_x_idx);
ny_free   = numel(free_vars);
n_slack   = numel(slack_u_idx);

% ---- Validate spec structure before any classification ----
[spec_ok, spec_msg] = validate_specs(all_specs);
if ~spec_ok
    z_sol = z0(:); niter = 0; converged = false;
    res_norm = inf; rcond_val = NaN;
    fail_id = 'mixed_equilibrium_solve:badActiveBoundSpec';
    fail_reason = spec_msg;
    regime_history = {};
    outer_iters = 0;
    return;
end

% ---- Initial classification ----
regime_c = classify_one_z(z0, active_x_idx, frozen_x_idx, frozen_x_val, ...
    free_vars, vcon_vars, vcon_ref, ny_full, u_base, slack_u_idx, ...
    all_specs, eq_ctx);

% ---- Validate regime values ----
[rg_ok, rg_msg] = validate_regime(regime_c);
if ~rg_ok
    z_sol = z0(:); niter = 0; converged = false;
    res_norm = inf; rcond_val = NaN;
    fail_id = 'mixed_equilibrium_solve:badActiveBoundSpec';
    fail_reason = rg_msg;
    regime_history = {};
    outer_iters = 0;
    return;
end

% ---- Validate initial raw_dot outputs are finite ----
[rd_ok, rd_msg] = check_rawdot_finite(z0, active_x_idx, frozen_x_idx, ...
    frozen_x_val, free_vars, vcon_vars, vcon_ref, ny_full, u_base, ...
    slack_u_idx, all_specs, eq_ctx);
if ~rd_ok
    z_sol = z0(:); niter = 0; converged = false;
    res_norm = inf; rcond_val = NaN;
    fail_id = 'mixed_equilibrium_solve:nonFiniteActiveBound';
    fail_reason = rd_msg;
    regime_history = {};
    outer_iters = 0;
    return;
end

history = {regime_c};
regime_history = history;
total_iters = 0;
z_c = z0;

% ---- Outer loop ----
for outer = 1:MAX_OUTER
    locked = history{end};

    wres = @(wz) locked_residual(wz, locked, base_residual_fn, ...
        active_x_idx, frozen_x_idx, frozen_x_val, ...
        free_vars, vcon_vars, vcon_ref, ny_full, u_base, slack_u_idx, ...
        all_specs, eq_ctx);
    wjac = @(wz) fd_jac(wz, wres, fd_eps);

    [z_new, ni, cv, rn, rc] = stability.composite_newton( ...
        z_c, wres, wjac, tol, max_iter, verbose);
    total_iters = total_iters + ni;

    if ~cv
        z_sol = z_new; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        outer_iters = outer; regime_history = history;
        fail_id = 'mixed_equilibrium_solve:activeBoundNewton';
        fail_reason = sprintf('Newton stalled at outer %d: residual=%.3e', outer, rn);
        return;
    end

    % ---- reclassify ----
    regime_new = classify_one_z(z_new, active_x_idx, frozen_x_idx, frozen_x_val, ...
        free_vars, vcon_vars, vcon_ref, ny_full, u_base, slack_u_idx, ...
        all_specs, eq_ctx);

    % ---- Validate reclassified regime ----
    [r2_ok, r2_msg] = validate_regime(regime_new);
    if ~r2_ok
        z_sol = z_new; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        outer_iters = outer; regime_history = history;
        fail_id = 'mixed_equilibrium_solve:badActiveBoundSpec';
        fail_reason = r2_msg;
        return;
    end

    % ---- Reclassified raw_dot finite check ----
    [rd2_ok, rd2_msg] = check_rawdot_finite(z_new, active_x_idx, frozen_x_idx, ...
        frozen_x_val, free_vars, vcon_vars, vcon_ref, ny_full, u_base, ...
        slack_u_idx, all_specs, eq_ctx);
    if ~rd2_ok
        z_sol = z_new; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        outer_iters = outer; regime_history = history;
        fail_id = 'mixed_equilibrium_solve:nonFiniteActiveBound';
        fail_reason = rd2_msg;
        return;
    end

    % ---- check admissibility ----
    adm = all_admissible_inx(z_new, locked, ...
        active_x_idx, frozen_x_idx, frozen_x_val, ...
        free_vars, vcon_vars, vcon_ref, ny_full, u_base, slack_u_idx, ...
        all_specs, eq_ctx);

    if ~isfinite(adm)
        z_sol = z_new; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        outer_iters = outer; regime_history = history;
        fail_id = 'mixed_equilibrium_solve:nonFiniteActiveBound';
        fail_reason = 'admissibility check returned non-finite value.';
        return;
    end

    % ---- decision ----
    if regimes_equal(regime_new, locked)
        z_sol = z_new; niter = total_iters;
        res_norm = rn; rcond_val = rc;
        outer_iters = outer; regime_history = history;
        if adm
            converged = true; fail_id = ''; fail_reason = '';
        else
            converged = false;
            fail_id = 'mixed_equilibrium_solve:activeBoundInconsistent';
            fail_reason = 'locked regime violated by converged solution';
        end
        return;
    end

    if regime_in_history(regime_new, history)
        z_sol = z_new; niter = total_iters;
        converged = false; res_norm = rn; rcond_val = rc;
        outer_iters = outer; regime_history = history;
        fail_id = 'mixed_equilibrium_solve:activeBoundCycle';
        fail_reason = sprintf('regime cycle at outer %d', outer);
        return;
    end

    history{end+1} = regime_new; %#ok<AGROW>
    regime_history = history;
    z_c = z_new;
end

% exhausted
z_sol = z_c; niter = total_iters;
converged = false; res_norm = inf; rcond_val = NaN;
outer_iters = MAX_OUTER; regime_history = history;
fail_id = 'mixed_equilibrium_solve:activeBoundMaxOuter';
fail_reason = 'max outer loop exhausted (5)';
end

% ====================================================================
function r = locked_residual(wz, locked, base_fn, ...
    active_x, frozen_x, frozen_x_val, ...
    free_v, vcon_v, vcon_r, ny, u_base, slack_u, ...
    all_specs, eq_ctx)
%locked_residual  Reconstruct x/y/u, call base, replace constrained rows with spec.residual_fn. always includes interior.

% reconstruct full x
nx_t = numel(active_x) + numel(frozen_x);
x_full = zeros(nx_t, 1);
x_full(active_x) = wz(1:numel(active_x));
for fi = 1:numel(frozen_x)
    x_full(frozen_x(fi)) = frozen_x_val(fi);
end

% reconstruct y
y_full = zeros(ny, 1);
y_free_vec = wz(numel(active_x)+1 : numel(active_x)+numel(free_v));
y_full(free_v) = y_free_vec;
y_full(vcon_v) = vcon_r;

% reconstruct u (including solved slack)
u_full = u_base;
n_sl = numel(slack_u);
if n_sl > 0
    u_full(slack_u) = wz(end - n_sl + 1 : end);
end

% base residual
r = base_fn(wz);

% for EVERY constraint, replace diff row with spec.residual_fn
for dk = 1:numel(all_specs)
    e = all_specs{dk};
    if isempty(e), continue; end
    x_dev = x_full(e.offset+1 : e.offset + e.dev_nx);
    u_dev = [];
    if e.dev_nu > 0
        u_dev = u_full(e.u_offset+1 : e.u_offset + e.dev_nu);
    end
    for sp = 1:numel(e.specs)
        reg = find_regime_locked(locked, dk, e.specs(sp).local_idx);
        gidx = e.offset + e.specs(sp).local_idx;
        zp = find(active_x == gidx, 1, 'first');
        if isempty(zp), continue; end
        row_val = e.specs(sp).residual_fn(x_dev, y_full, u_dev, eq_ctx, reg);
        if ~isscalar(row_val) || ~isfinite(row_val)
            error('deflagged_component:bogusSpecResidual', ...
                'Constraint for_each=%d setting=%d residual non-finite.', ...
                dk, e.specs(sp).local_idx);
        end
        r(zp) = row_val;
    end
end
end

% ====================================================================
function ok = all_admissible_inx(z, locked, ...
    active_x, frozen_x, frozen_x_val_flag, ...
    free_v, vcon_v, vcon_r, ny, u_base, slack_u, ...
    all_specs, eq_ctx)
% Reconstruct x/y/u; call admissible_fn for every locked constraint entry.

n_a = numel(active_x);
n_fx = numel(frozen_x);
nx_t = n_a + n_fx;
x_full = zeros(nx_t, 1);
x_full(active_x) = z(1:n_a);
for fi = 1:n_fx
    x_full(frozen_x(fi)) = frozen_x_val_flag(fi);
end

y_full = zeros(ny, 1);
y_dz = z(n_a+1 : n_a+numel(free_v));
y_full(free_v) = y_dz;
y_full(vcon_v) = vcon_r;

u_full = u_base;
ns = numel(slack_u);
if ns > 0
    u_full(slack_u) = z(end - ns + 1 : end);
end

ok = true;
for dk = 1:numel(all_specs)
    e = all_specs{dk};
    if isempty(e), continue; end
    x_dv = x_full(e.offset+1 : e.offset + e.dev_nx);
    u_dv = [];
    if e.dev_nu > 0
        u_dv = u_full(e.u_offset+1 : e.u_offset + e.dev_nu);
    end
    for sp = 1:numel(e.specs)
        for si = 1:numel(locked)
            if locked(si).dev_idx == dk && ...
               locked(si).local_idx == e.specs(sp).local_idx
                reg_val = locked(si).regime;
                ad = e.specs(sp).admissible_fn(x_dv, y_full, u_dv, eq_ctx, reg_val);
                if ~isscalar(ad) || ~islogical(ad) || ~isfinite(ad)
                    error('inactive_branch:notScalarAdmissibleDelivery', ...
                        'admissible_fn dev=%d local=%d returned non-scalar-logical.', ...
                        dk, e.specs(sp).local_idx);
                end
                if ~ad
                    ok = false;
                    return;
                end
            end
        end
    end
end
ok = ok; % explicit before return
end

% ====================================================================
function regime = classify_one_z(z, active_x, frozen_x, frozen_x_val, ...
    free_v, vcon_v, vcon_r, ny, u_base, slack_u, all_specs, eq_ctx)
% wrapper over stability.active_bound_classify; calls it after reconstructing
% whatever state label it decides.
    regime = stability.active_bound_classify(z, active_x, frozen_x, frozen_x_val, ...
        free_v, vcon_v, vcon_r, ny, u_base, slack_u, all_specs, eq_ctx);
end

% ====================================================================
function J = fd_jac(z, fn, h)
    nz = numel(z);
    r0 = fn(z);
    if numel(r0) ~= nz
        error('bound aria:size', 'residual %d != z %d', numel(r0), nz);
    end
    J = zeros(nz);
    for j = 1:nz
        zp = z; zp(j) = zp(j) + h;
        rp = fn(zp);
        J(:, j) = (rp - r0) / h;
    end
end

% ====================================================================
function reg = find_regime_locked(locked, dev_id, local_id)
    reg = 'interior';   % fallback when constraint not in locked set
    for i = 1:numel(locked)
        if locked(i).dev_idx == dev_id && locked(i).local_idx == local_id
            reg = locked(i).regime;
            return;
        end
    end
end

% ====================================================================
function tf = regimes_equal(a, b)
    na = numel(a);
    if na ~= numel(b), tf = false; return; end
    for k = 1:na
        if a(k).dev_idx ~= b(k).dev_idx, tf = false; return; end
        if a(k).local_idx ~= b(k).local_idx, tf = false; return; end
        if ~strcmp(a(k).regime, b(k).regime), tf = false; return; end
    end
    tf = true;
end

% ====================================================================
function tf = regime_in_history(reg, hist)
    tf = false;
    for h = 1:numel(hist)
        if regimes_equal(reg, hist{h})
            tf = true;
            return;
        end
    end
end

% ====================================================================
function [ok, msg] = validate_specs(all_spec_list)
    ok = true; msg = '';
    for d = 1:numel(all_spec_list)
        entry = all_spec_list{d};
        if isempty(entry), continue; end
        if ~isstruct(entry) || ~isscalar(entry)
            ok = false;
            msg = sprintf('all_specs entry %d is not a scalar struct.', d);
            return;
        end
        must = {'offset','u_offset','dev_nu','dev_nx','specs'};
        for mi = 1:numel(must)
            if ~isfield(entry, must{mi})
                ok = false;
                msg = sprintf('all_specs entry %d missing field "%s".', d, must{mi});
                return;
            end
        end
        if entry.dev_nx < 1
            ok = false;
            msg = sprintf('all_specs entry %d has dev_nx=%d (must be >=1).', d, entry.dev_nx);
            return;
        end
        if isempty(entry.specs), continue; end
        for s = 1:numel(entry.specs)
            sp = entry.specs(s);
            if ~isfield(sp, 'local_idx') || ~isscalar(sp.local_idx) || ...
               ~isfinite(sp.local_idx) || sp.local_idx ~= fix(sp.local_idx) || ...
               sp.local_idx < 1 || sp.local_idx > entry.dev_nx
                ok = false;
                msg = sprintf(...
                    'all_specs entry %d spec %d: local_idx problem (valid [1,%d]).', ...
                    d, s, entry.dev_nx);
                return;
            end
            required = {'classify_fn','residual_fn','admissible_fn'};
            for n = 1:numel(required)
                if ~isfield(sp, required{n}) || ~isa(sp.(required{n}), 'function_handle')
                    ok = false;
                    msg = sprintf(...
                        'all_specs entry %d spec %d missing %s.', ...
                        d, s, required{n});
                    return;
                end
            end
        end
    end
end

% ====================================================================
function [ok, msg] = validate_regime(rg)
    ok = true; msg = '';
    if isempty(rg), return; end
    valid_regs = {'interior','upper','lower'};
    for i = 1:numel(rg)
        r = rg(i);
        for field = {'dev_idx','local_idx','regime'}
            if ~isfield(r, field{1})
                ok = false;
                msg = sprintf('regime entry %d missing field "%s".', i, field{1});
                return;
            end
        end
        if ~any(strcmpi(r.regime, valid_regs))
            ok = false;
            msg = sprintf(...
                'regime entry %d: regime="%s" not in {interior,upper,lower}.', ...
                i, r.regime);
            return;
        end
        if ~isscalar(r.dev_idx) || ~isfinite(r.dev_idx) || ...
           r.dev_idx ~= fix(r.dev_idx) || r.dev_idx < 1
            ok = false;
            msg = sprintf('regime entry %d has invalid dev_idx.', i);
            return;
        end
        if ~isscalar(r.local_idx) || ~isfinite(r.local_idx) || ...
           r.local_idx ~= fix(r.local_idx) || r.local_idx < 1
            ok = false;
            msg = sprintf('regime entry %d has invalid local_idx.', i);
            return;
        end
    end
end

% ====================================================================
function [ok, msg] = check_rawdot_finite(z, ...
    active_x, frozen_x, frozen_x_initials, ...
    free_v, vcon_v, vcon_r, ny, u_base, slack_idx, ...
    all_sp, ctx)
% Evaluate raw_dot_fn for each constraint spec; verify scalar finite output.

    n_a = numel(active_x);
    n_fv = numel(free_v);
    n_s = numel(slack_idx);

    nx_t = n_a + numel(frozen_x);
    x_full = zeros(nx_t, 1);
    x_full(active_x) = z(1:n_a);
    for fi = 1:numel(frozen_x)
        x_full(frozen_x(fi)) = frozen_x_initials(fi);
    end

    y_full = zeros(ny, 1);
    y_seg = z(n_a + (1:n_fv));
    y_full(free_v) = y_seg;
    y_full(vcon_v) = vcon_r;

    u_full = u_base;
    if n_s > 0
        u_full(slack_idx) = z(end - n_s + 1 : end);
    end

    ok = true; msg = '';
    for d = 1:numel(all_sp)
        e = all_sp{d};
        if isempty(e), continue; end

        x_dev = x_full(e.offset+1 : e.offset + e.dev_nx);
        u_dev = [];
        if e.dev_nu > 0
            u_dev = u_full(e.u_offset+1 : e.u_offset + e.dev_nu);
        end

        for si = 1:numel(e.specs)
            sp = e.specs(si);
            if ~isfield(sp, 'raw_dot_fn') || ~isa(sp.raw_dot_fn, 'function_handle')
                continue;
            end

            try
                raw_val = sp.raw_dot_fn(x_dev, y_full, u_dev, ctx);
            catch me
                ok = false;
                msg = sprintf('raw_dot_fn threw dev %d spec %d: %s', d, si, me.message);
                return;
            end

            if ~isscalar(raw_val) || ~isfinite(raw_val)
                ok = false;
                msg = sprintf('raw_dot_fn dev %d spec %d returned non-finite.', d, si);
                return;
            end
        end
    end
end