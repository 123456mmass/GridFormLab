function dev = active_bound_diag_device(k_target, bound_lo, bound_hi)
%active_bound_diag_device  Single-state active-bound test fixture.
%
%  dev = active_bound_diag_device(k_target, bound_lo, bound_hi)
%  creates a tiny device whose sole state evolves as dx/dt = k_target * x
%  (x=0 is the unconstrained equilibrium). The constraint mechanics are
%  bound_lo <= x <= bound_hi with regime = upper|lower|interior driven by
%  raw_dot sign. The device is suitable for testing the active-bound outer
%  loop in isolation with the composite solver.
%
%  (SOURCE_DEFINED test scaffold.)

if nargin < 1, k_target = 2.0; end
if nargin < 2, bound_lo  = -0.5; end
if nargin < 3, bound_hi  = 0.5; end

dev.device_id       = 'active_bound_diag';
dev.resource_type   = 'diagnostic_fixture';
dev.mode            = 'gfm';
dev.initial_mode    = 'gfm';
dev.initial_online  = true;

dev.nx = 1;   dev.nu = 0;   dev.ny = 2;
dev.bus_id        = 1;
dev.bus_position  = 1;
dev.x0  = 0.123;
dev.y0  = [0; 0];
dev.input_names  = {};
dev.output_names = {'Re(V)','Im(V)'};

dev.active_state_indices = 1;

% Trivial current injection so the device never disturbs the network.
dev.current_injection = @(t, xd, y, u, ec) 0i;

% ODE: dx/dt = k_target * x  → equilibrium at x=0.
dev.dae_f = @(t, xd, y, u, ec) k_target * xd(1);

dev.electrical_power = @(t, x, y, u, ec) 0.0;

dev.reconstruct = @(t, xd, y, u, ec) struct();

dev.capabilities = struct('resource_type','ibr', ...
    'can_switch_mode',true, 'supported_modes',{{'gfm'}}, ...
    'voltage_forming_modes',{{'gfm'}});

% ---------------------------------
% equilibrium_constraint_specs callback
% ---------------------------------
dev.equilibrium_constraint_specs = @(x_dev, y, u_dev, ec) ...
    ab_diag_spec(x_dev, k_target, bound_lo, bound_hi);

end

% =========================================================================
function s = ab_diag_spec(x_dev, k_target, lo, hi)
%ab_diag_spec  Return one constraint specification for local index 1.
x = x_dev(1); %#ok<NASGU>
s = struct('local_idx', 1, ...
    'classify_fn',   @(xd,y,u,ec) ab_classify(xd(1), k_target, lo, hi), ...
    'residual_fn',   @(xd,y,u,ec,locked) ab_residual(xd(1), locked, lo, hi), ...
    'raw_dot_fn',    @(xd,y,u,ec) k_target * xd(1), ...
    'admissible_fn', @(xd,y,u,ec,locked) ab_admissible(xd(1), k_target, locked, lo, hi), ...
    'description',   sprintf('dx=%.1f*x bounded [%.3g, %.3g]', k_target, lo, hi));
end

% =========================================================================
function regime = ab_classify(x, k, lo, hi)
%classify  raw_dot = k*x  (not negated — matches dx = k_target*x).
raw = k * x;
if raw > 1e-6
    regime = 'upper';
elseif raw < -1e-6
    regime = 'lower';
elseif x >= hi - 1e-8
    regime = 'upper';
elseif x <= lo + 1e-8
    regime = 'lower';
else
    regime = 'interior';
end
end

% =========================================================================
function r = ab_residual(x, locked, lo, hi)
%ab_residual  Return row for the residual given present locked regime.
switch locked
    case 'interior'
        r = 2.0 * x;           % maps to k_target = 2.0 (dx/dt)
    case 'upper'
        r = x - hi;
    case 'lower'
        r = x - lo;
end
end

% =========================================================================
function ok = ab_admissible(x, k, locked, lo, hi)
%ab_admissible  Does the solution satisfy the constraint regime?
dot = k * x;
switch locked
    case 'upper'
        ok = dot >= -1e-6;        % raw_dot >= 0 on the upper bound
    case 'lower'
        ok = dot <= 1e-6;         % raw_dot <= 0 on the lower bound
    case 'interior'
        ok = (x >= lo + 1e-8) && (x <= hi - 1e-8);
end
end