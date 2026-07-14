function sssa = composite_sssa_model(devices, x0, y0, case_data, opt)
%COMPOSITE_SSSA_MODEL  Small-signal stability model for mixed SG+IBR system.
%   SSSA = composite_sssa_model(DEVICES, X0, Y0, CASE_DATA, OPT) builds a
%   2-arg binding for multimachine_ssa from an operating point + device list.
%
%   Correction 8 (active-state reduction before eig): frozen states (e.g. Edp
%   for Tpq0=0 round-rotor SG) are EXCLUDED through Galerkin projection BEFORE
%   eig, NOT deleted from the spectrum afterward. The active-state indices are
%   derived from per-device frozen_state_indices metadata — NEVER hard-coded.
%
%   The model returns:
%     sssa.A  = reduced active-state state matrix (nx_active x nx_active)
%     sssa.x0 = equilibrium operating point
%     sssa.eigenvalues = eig(A)
%     sssa.active_state_indices (from device metadata)
%     sssa.frozen_state_indices
%
%   STATUS: STRUCTURAL_ONLY (Phase D). No production-readiness claim.
%   Source: execution plan §D; correction 8.

arguments
    devices struct
    x0 (:,1) double
    y0 (:,1) double
    case_data struct
    opt struct = struct()
end

fd_eps = 3e-6;
if isfield(opt, 'fd_eps') && ~isempty(opt.fd_eps), fd_eps = opt.fd_eps; end

% --- Build composite DAE for Jacobian evaluation --------------------------
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae_opt = struct('load_model','cz_p_cz_q','vcon',vcon);
dae = stability.composite_dae(case_data, devices, dae_opt);

% --- Detect frozen states from device metadata ----------------------------
frozen_x_indices = [];
active_x_indices = 1:numel(x0);
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk);
    if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        off = dae.device_offsets(dk);
        fsi = dev.frozen_state_indices(:)';
        frozen_x_indices = [frozen_x_indices, off + fsi]; %#ok<AGROW>
    end
end
active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
nx_active = numel(active_x_indices);

% --- Evaluate df/dx at operating point via central FD ---------------------
nx = numel(x0);
u = dae.u0;
ec = struct();

% Evaluate RHS at op point
f0 = dae.dae_f(0, x0, y0, u, ec);
dfdx = zeros(nx, nx);
x_op = x0;
for j = 1:nx
    xp = x_op; xp(j) = xp(j) + fd_eps;
    fp = dae.dae_f(0, xp, y0, u, ec);
    dfdx(:, j) = (fp - f0) / fd_eps;
end

% --- Active-state reduction (Galerkin) before eig -------------------------
% A = df/dx restricted to active state indices
A_full = dfdx;
A = A_full(active_x_indices, active_x_indices);

% --- Compute eigenvalues --------------------------------------------------
eig_vals = eig(A);

% --- Assemble output ------------------------------------------------------
sssa = struct();
sssa.A = A;
sssa.A_full = A_full;
sssa.x0 = x0;
sssa.y0 = y0;
sssa.eigenvalues = eig_vals;
sssa.active_state_indices = active_x_indices;
sssa.frozen_state_indices = frozen_x_indices;
sssa.nx_total = nx;
sssa.nx_active = nx_active;
sssa.omega = sort(real(eig_vals));    % damping constants (negative = stable)
sssa.frequencies = sort(abs(imag(eig_vals)));
sssa.stable = all(real(eig_vals) < 0);
sssa.reduction_method = 'active_state_galerkin_before_eig';
sssa.no_eig_delete = true;
end
