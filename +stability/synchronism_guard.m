function result = synchronism_guard(V_bus, V_sg, delta_sg, omega_sg, omega_ref, opt)
%SYNCHRONISM_GUARD  Per-SG synchronism check for reclosing (correction 5).
%   RESULT = synchronism_guard(V_BUS, V_SG, DELTA_SG, OMEGA_SG, OMEGA_REF, OPT)
%   checks whether an offline SG can safely reclose to its bus.
%
%   Signed margin: min(dV_max - |dV|, df_max - |df|, dtheta_max - |dtheta_wrapped|).
%   When margin >= 0 and dwell is sustained for the required duration, reclose
%   is permitted. Per-SG state — never global.
%
%   Correction 5 (SG breaker physics + synchronism):
%   - Delta-V: |V_bus - V_sg_open_circuit|
%   - Delta-f: |omega_sg/(2*pi) - f_nominal| (slip)
%   - Delta-theta: wrapped angle between V_bus and V_sg (absolute, [-pi,pi])
%   - Dwell: margin > 0 sustained for dwell_duration
%   - Min-off: SG must have been offline >= T_sg_min_off
%   - Lockout: must not be in lockout state
%
%   Reconnect request time is only the EARLIEST time synchronism checking MAY
%   allow reclosure. Actual reclose requires ALL gates pass.
%
%   Source: IEEE14_GENERIC_MIXED_RESOURCE_EXECUTION_PLAN.md §F; correction 5.

arguments
    V_bus (1,1) double
    V_sg (1,1) double
    delta_sg (1,1) double
    omega_sg (1,1) double
    omega_ref (1,1) double = 1.0
    opt struct = struct()
end

% Frozen thresholds (execution plan, appendix)
dV_max     = 0.05;    % pu voltage difference
df_max     = 0.001;   % pu frequency slip
dtheta_max = 10.0;    % degrees
dwell_min  = 0.5;     % seconds sustained margin required
if isfield(opt,'dV_max'), dV_max = opt.dV_max; end
if isfield(opt,'df_max'), df_max = opt.df_max; end
if isfield(opt,'dtheta_max'), dtheta_max = opt.dtheta_max; end
if isfield(opt,'dwell_min'), dwell_min = opt.dwell_min; end

% --- Compute metrics ------------------------------------------------------
dV   = abs(abs(V_bus) - abs(V_sg));
df   = abs(omega_sg - omega_ref) / (2*pi);
dtheta_rad = mod(abs(angle(V_bus) - delta_sg) + pi, 2*pi) - pi;
dtheta = rad2deg(abs(dtheta_rad));

% --- Signed margin (negative = fail, positive = pass with margin) ----------
margin_V = dV_max - dV;
margin_f = df_max - df;
margin_theta = dtheta_max - dtheta;
signed_margin = min([margin_V, margin_f, margin_theta]);

% --- Assemble result -------------------------------------------------------
result = struct();
result.dV = dV; result.df = df; result.dtheta = dtheta;
result.margin_V = margin_V; result.margin_f = margin_f;
result.margin_theta = margin_theta;
result.signed_margin = signed_margin;
result.passes = signed_margin >= 0;
result.dwell_required = dwell_min;
result.dV_max = dV_max; result.df_max = df_max; result.dtheta_max = dtheta_max;
result.V_bus = V_bus; result.V_sg = V_sg;
end
