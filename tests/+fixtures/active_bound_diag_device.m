function dev = active_bound_diag_device(k_target, bound_lo, bound_hi, ...
    kiv_diag, Emin_diag, Emax_diag, case_ctx)
%active_bound_diag_device  2-state active-bound diagnostic test fixture.
%
%  dev = active_bound_diag_device(k_target,bound_lo,bound_hi,...
%        kiv_diag,Emin_diag,Emax_diag,case_ctx)
%
%  State 1 (ordinary bounded):
%    ODE: dx1/dt = k_target * x1
%    Constraint: bound_lo <= x1 <= bound_hi
%    interior residual = k_target*x1; upper = x1-hi; lower = x1-lo
%
%  State 2 (voltage-style):
%    ODE: dx2/dt = +k_target * x2   (% binding amendment)
%    EVSM_diag = |Vbus| + kiv_diag * x2
%    Upper residual = EVSM_diag - Emax_diag
%    Lower residual = EVSM_diag - Emin_diag
%    interior residual = k_target*x2
%    Classification uses EVSM_diag versus Emin/Emax
%
%  The device injects zero current. It is NOT a voltage-forming reference
%  (mode=gfl, no voltage_forming_modes). Optional case_ctx (struct with
%  fields .bus_ids, .bus_position, .bus_id) lets the fixture adopt a real
%  network's bus layout so it can be concatenated with production devices.
%
%  (ASSUMED_DIAGNOSTIC test scaffold; never used by production paths.)

if nargin < 1, k_target = 2.0; end
if nargin < 2, bound_lo  = -0.5; end
if nargin < 3, bound_hi  = 0.5; end
if nargin < 4, kiv_diag  = 3.0; end
if nargin < 5, Emin_diag = 0.95; end
if nargin < 6, Emax_diag = 1.05; end
if nargin < 7, case_ctx  = struct(); end

% Resolve bus attachment (default: standalone single-bus position 5).
if isfield(case_ctx,'bus_id'),        bus_id = case_ctx.bus_id;        else, bus_id = 5; end
if isfield(case_ctx,'bus_position'),  bus_pos = case_ctx.bus_position; else, bus_pos = 5; end
if isfield(case_ctx,'bus_ids'),       bus_ids = case_ctx.bus_ids;      else, bus_ids = bus_id; end

% --- identity (non-voltage-forming) ---
dev.name            = 'active_bound_diag';
dev.device_id       = 'active_bound_diag';
dev.bus_id          = bus_id;
dev.bus_position    = bus_pos;
dev.bus_ids         = bus_ids;
dev.device_type     = 'diagnostic_fixture';
dev.mode            = 'gfl';
dev.initial_mode    = 'gfl';
dev.initial_online  = true;

dev.nx = 2;  dev.nu = 0;
dev.state_names   = {'x1','x2'};
dev.x0 = [0.123; 0.0];
dev.u0 = zeros(0,1);
dev.input_names  = {};
dev.active_state_indices = [1 2];
dev.frozen_state_indices  = [];
dev.frozen_state_values   = [];
dev.frozen_state_source  = 'none';
dev.frozen_state_classification = 'none';
dev.provenance = struct('source','tests/+fixtures/active_bound_diag_device', ...
    'classification','ASSUMED_DIAGNOSTIC');
dev.equilibrium_initialize = @(x_dev, y, u_dev, ec) x_dev;
dev.dynamic_state_indices_for_context = @(ec) [1 2];
dev.active_state_indices_for_context = @(ec) [1 2];

% --- DAE ---
dev.f = @(t, xd, y, u, ec) [k_target * xd(1); k_target * xd(2)];
dev.current_injection = @(t, xd, y, u, ec) 0i;
dev.electrical_power  = @(t, x, y, u, ec) 0.0;
dev.reconstruct       = @(t, xd, y, u, ec) struct();

dev.capabilities = struct('resource_type','diagnostic_fixture', ...
    'supported_modes', {{'gfl'}}, 'voltage_forming_modes', {{}}, ...
    'can_switch_mode', false, 'can_switch_online', false, ...
    'has_current_limiter', false, 'has_frt', false, 'can_black_start', false);

% --- equilibrium_constraint_specs callback ---
% Captures bus_position so the voltage-style constraint indexes y correctly.
dev.equilibrium_constraint_specs = @(x_dev, y, u_dev, ec) ...
    make_specs(x_dev, k_target, bound_lo, bound_hi, ...
              kiv_diag, Emin_diag, Emax_diag, dev.bus_position);
end

% =========================================================================
function specs = make_specs(~, k, lo, hi, kiv, Emin, Emax, bus_pos)
% Spec 1: ordinary bound (state 1 local_idx = 1)
s1.local_idx = 1;
s1.classify_fn   = @(x_d, y, u, ec) classify_s1(x_d(1), k, lo, hi);
s1.residual_fn   = @(x_d, y, u, ec, locked) residual_s1(x_d(1), locked, k, lo, hi);
s1.raw_dot_fn    = @(x_d, y, u, ec) k * x_d(1);
s1.admissible_fn = @(x_d, y, u, ec, locked) admissible_s1(x_d(1), k, locked, lo, hi);
s1.description   = sprintf('x1: k=%.1f [%.3g,%.3g]', k, lo, hi);

% Spec 2: voltage diagnostic (state 2 local_idx = 2)
s2.local_idx = 2;
s2.classify_fn   = @(x_d, y, u, ec) classify_s2(x_d(2), y, k, kiv, Emin, Emax, bus_pos);
s2.residual_fn   = @(x_d, y, u, ec, locked) residual_s2(x_d(2), y, locked, k, kiv, Emin, Emax, bus_pos);
s2.raw_dot_fn    = @(x_d, y, u, ec) k * x_d(2);
s2.admissible_fn = @(x_d, y, u, ec, locked) admissible_s2(x_d(2), y, k, locked, kiv, Emin, Emax, bus_pos);
s2.description   = sprintf('voltage-style: kiv=%.1f E[%.2f,%.2f]', kiv, Emin, Emax);

specs = [s1; s2];
end

% ============================ State 1 helpers ====================================
function regime = classify_s1(x, k, lo, hi)
    btol = 1e-8;  stol = 1e-6;
    if x > hi + btol
        regime = 'upper';
    elseif x < lo - btol
        regime = 'lower';
    elseif x >= hi - btol && k*x >= -stol
        regime = 'upper';
    elseif x <= lo + btol && k*x <= stol
        regime = 'lower';
    else
        regime = 'interior';
    end
end

function r = residual_s1(x, locked, k, lo, hi)
    switch locked
        case 'interior', r = k * x;
        case 'upper',    r = x - hi;
        case 'lower',    r = x - lo;
    end
end

function ok = admissible_s1(x, k, locked, lo, hi)
    raw = k * x;
    switch locked
        case 'upper',    ok = raw >= -1e-6;
        case 'lower',    ok = raw <= 1e-6;
        case 'interior', ok = (x >= lo + 1e-8) && (x <= hi - 1e-8);
    end
end

% --------------------------------------------------------------------------------
% --- State 2 voltage-style helpers.
% y is the rectangular network voltage vector. For bus_position p, the
% real/imag parts of that bus voltage live at y(2*p-1) and y(2*p).

function Vbus = diag_bus_voltage_magnitude(y_in, bus_pos)
    if numel(y_in) < 2*bus_pos
        error('active_bound_diag:badYLength', ...
            'voltage-style constraint needs numel(y)>=%d, got %d.', ...
            2*bus_pos, numel(y_in));
    end
    vr = y_in(2*bus_pos - 1);
    vi = y_in(2*bus_pos);
    Vbus = sqrt(vr^2 + vi^2);
end

function regime = classify_s2(x, y, k, kiv, Emin, Emax, bus_pos)
    btol = 1e-8;  stol = 1e-6;
    Vbus = diag_bus_voltage_magnitude(y, bus_pos);
    EV_ = Vbus + kiv * x;
    if EV_ > Emax + btol
        regime = 'upper';
    elseif EV_ < Emin - btol
        regime = 'lower';
    elseif EV_ >= Emax - btol && k*x >= -stol
        regime = 'upper';
    elseif EV_ <= Emin + btol && k*x <= stol
        regime = 'lower';
    else
        regime = 'interior';
    end
end

function r = residual_s2(x, y, locked, k, kiv, Emin, Emax, bus_pos)
    Vbus = diag_bus_voltage_magnitude(y, bus_pos);
    EV_ = Vbus + kiv * x;
    switch locked
        case 'interior', r = k * x;
        case 'upper',    r = EV_ - Emax;
        case 'lower',    r = EV_ - Emin;
    end
end

function ok = admissible_s2(x, y, k, locked, kiv, Emin, Emax, bus_pos)
    Vbus = diag_bus_voltage_magnitude(y, bus_pos);
    EV_ = Vbus + kiv * x;
    raw = k * x;
    switch locked
        case 'upper'
            ok = raw >= -1e-6;
        case 'lower'
            ok = raw <= 1e-6;
        case 'interior'
            ok = (EV_ >= Emin + 1e-8) && (EV_ <= Emax - 1e-8);
    end
end
