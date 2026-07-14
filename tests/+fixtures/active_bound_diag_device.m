function dev = active_bound_diag_device(k_target, bound_lo, bound_hi, ...
    kiv_diag, Emin_diag, Emax_diag)
%active_bound_diag_device  2-state active-bound diagnostic test fixture.
%
%  dev = active_bound_diag_device(k_target,bound_lo,bound_hi,...
%        kiv_diag,Emin_diag,Emax_diag)
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
%  (mode=gfl, no voltage_forming_modes). Suitable for end-to-end tests
%  alongside an existing SG reference at IEEE14 bus 1.
%
%  (SOURCE_DEFINED test scaffold.)

if nargin < 1, k_target = 2.0; end
if nargin < 2, bound_lo  = -0.5; end
if nargin < 3, bound_hi  = 0.5; end
if nargin < 4, kiv_diag  = 3.0; end
if nargin < 5, Emin_diag = 0.95; end
if nargin < 6, Emax_diag = 1.05; end

% --- identity (non-voltage-forming) ---
dev.name            = 'active_bound_diag';
dev.device_id       = 'active_bound_diag';
dev.resource_type   = 'diagnostic_fixture';
dev.mode            = 'gfl';
dev.initial_mode    = 'gfl';
dev.initial_online  = true;

dev.nx = 2;  dev.nu = 0;
dev.bus_id        = 5;
dev.bus_position  = 5;
dev.state_names   = {'x1','x2'};
dev.x0 = [0.123; 0.0];
dev.u0 = zeros(0,1);
dev.active_state_indices = [1 2];

% --- DAE ---
dev.f = @(t, xd, y, u, ec) [k_target * xd(1); k_target * xd(2)];
dev.current_injection = @(t, xd, y, u, ec) 0i;
dev.electrical_power  = @(t, x, y, u, ec) 0.0;
dev.reconstruct       = @(t, xd, y, u, ec) struct();
dev.input_names  = {};
dev.output_names = {};

dev.capabilities = struct('resource_type','diagnostic_fixture', ...
    'can_switch_mode', true, 'supported_modes', {{'gfl'}}, ...
    'voltage_forming_modes', {{}});

% --- equilibrium_constraint_specs callback ---
dev.equilibrium_constraint_specs = @(x_dev, y, u_dev, ec) ...
    make_specs(x_dev, k_target, bound_lo, bound_hi, ...
              kiv_diag, Emin_diag, Emax_diag);
end

% =========================================================================
function specs = make_specs(z_dev, k, lo, hi, kiv, Emin, Emax)
% Spec 1: ordinary bound (state 1 local_idx = 1)
s1.local_idx = 1;
s1.classify_fn   = @(x_d, y, u, ec) classify_s1(x_d(1), k, lo, hi);
s1.residual_fn   = @(x_d, y, u, ec, locked) residual_s1(x_d(1), locked, k, lo, hi);
s1.raw_dot_fn    = @(x_d, y, u, ec) k * x_d(1);
s1.admissible_fn = @(x_d, y, u, ec, locked) admissible_s1(x_d(1), k, locked, lo, hi);
s1.description   = sprintf('x1: k=%.1f [%.3g,%.3g]', k, lo, hi);

% Spec 2: voltage diagnostic (state  2 local_idx = 2)
s2.local_idx = 2;
s2.classify_fn   = @(x_d, y, u, ec) classify_s2(x_d(2), y, k, kiv, Emin, Emax);
s2.residual_fn   = @(x_d, y, u, ec, locked) residual_s2(x_d(2), y, locked, k, kiv, Emin, Emax);
s2.raw_dot_fn    = @(x_d, y, u, ec) k * x_d(2);
s2.admissible_fn = @(x_d, y, u, ec, locked) admissible_s2(x_d(2), y, k, locked, kiv, Emin, Emax);
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
% --- State 2 voltage-style helpers (y at bus_position = 5 => (2*5-1, 2*5))

function Vbus = diag_bus_real_voltage(y_in)
    % bus_position = 5 => y[9], y[10] in rectangular y
    vr = y(9);
    vi = y(10);
    Vbus = sqrt(vr^2 + vi^2);
end

function E = diag_mean(Vbus, x, kiv)
    E = Vbus + kiv * x;
end

function regime = classify_s2(x, y, k, kiv, Emin, Emax)
    btol = 1e-8;  stol = 1e-6;
    Vbus = diag_bus_real_voltage(y);
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

function r = residual_s2(x, y, locked, k, kiv, Emin, Emax)
    Vbus = diag_bus_real_voltage(y);
    EV_ = Vbus + kiv * x;
    switch locked
        case 'interior', r = k * x;
        case 'upper',    r = EV_ - Emax;
        case 'lower',    r = EV_ - Emin;
    end
end

function ok = admissible_s2(x, y, k, locked, kiv, Emin, Emax)
    Vbus = diag_bus_real_voltage(y);
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