function [violated_buses, fixed_Q, limit_type] = pf_find_q_limit_violations(model, results, tolerance)
%PF_FIND_Q_LIMIT_VIOLATIONS  Shared Q-limit violation finder (parity with NR's private function).
%   [VIOLATED_BUSES, FIXED_Q, LIMIT_TYPE] = PF_FIND_Q_LIMIT_VIOLATIONS(MODEL, RESULTS, TOLERANCE)
%   finds PV-bus Q-limit violations in the PF result. This is the SHARED helper
%   used by the FDPF solver (and later BFS); it reproduces the EXACT result/event
%   schema of the canonical Newton-Raphson solver's private find_q_limit_violations
%   (powerflow_newton_raphson.m), so downstream consumers are agnostic to which
%   method produced the switching events.
%
%   Parity (binding, per user correction 3): the canonical NR solver is NOT
%   modified to share code. Its private local function stays private; this is a
%   NEW shared helper that returns byte-identical violation sets and event
%   struct schema. Parity is asserted by test_q_limit_helper_parity.
%
%   Outputs (identical schema to NR's private function):
%     VIOLATED_BUSES : column vector of PV bus indices (internal row indices)
%     FIXED_Q        : column vector of the fixed Q value at each violated bus
%     LIMIT_TYPE     : cell array of 'Qmax' or 'Qmin' per violated bus
%
%   The Q-limit event struct (round, bus_id, from_type, to_type,
%   Q_generation_before, Q_fixed, limit_type) is assembled by the CALLER using
%   these outputs, matching NR's q_limit_switching.events schema.

if nargin < 3, tolerance = 1e-6; end
violated_buses = [];
fixed_Q = [];
limit_type = {};

for i = 1:numel(model.pv_buses)
    bus_i = model.pv_buses(i);
    Qg = results.Q_generation(bus_i);
    if isfinite(model.Q_max(bus_i)) && Qg > model.Q_max(bus_i) + tolerance
        violated_buses(end + 1, 1) = bus_i; %#ok<AGROW>
        fixed_Q(end + 1, 1) = model.Q_max(bus_i); %#ok<AGROW>
        limit_type{end + 1, 1} = 'Qmax'; %#ok<AGROW>
    elseif isfinite(model.Q_min(bus_i)) && Qg < model.Q_min(bus_i) - tolerance
        violated_buses(end + 1, 1) = bus_i; %#ok<AGROW>
        fixed_Q(end + 1, 1) = model.Q_min(bus_i); %#ok<AGROW>
        limit_type{end + 1, 1} = 'Qmin'; %#ok<AGROW>
    end
end
end
