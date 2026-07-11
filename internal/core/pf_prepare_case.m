function model = pf_prepare_case(case_data)
%PF_PREPARE_CASE Normalize, validate, index, and build matrices for a case.
%   The input bus format remains backward compatible:
%   [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]
%   [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh]
%   or [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh Qmin Qmax].
%   Net scheduled injection is always Pgen-Pload and Qgen-Qload.

case_data = normalize_case_data(case_data);
validate_case_data(case_data);

bus_data = case_data.bus_data;
line_data = case_data.line_data;
external_bus_ids = bus_data(:, 1);

[line_from_ok, line_from_idx] = ismember(line_data(:, 1), external_bus_ids);
[line_to_ok, line_to_idx] = ismember(line_data(:, 2), external_bus_ids);
if any(~line_from_ok) || any(~line_to_ok)
    error('Line data references bus numbers that do not exist in bus_data.');
end

bus_type = bus_data(:, 2);
slack_buses = find(bus_type == 1);
pv_buses = find(bus_type == 2);
pq_buses = find(bus_type == 3);

[Ybus, line_data] = build_ybus(bus_data, line_data, line_from_idx, line_to_idx);

model = struct();
model.case_data = case_data;
model.case_data.line_data = line_data;
model.system_name = char(case_data.system_name);
model.base_values = case_data.base_values;
model.bus_data = bus_data;
model.line_data = line_data;
model.external_bus_ids = external_bus_ids;
model.num_buses = size(bus_data, 1);
model.num_lines = size(line_data, 1);
model.bus_type = bus_type;
% Physical source of truth: bus_data columns 3-6 (V, angle, Pgen, Qgen).
% Reference/comparison fields (e.g. operating_point.printed_*, case_data.reference.*)
% are never read here -- see test_pf_reference_independence.
model.V_spec = bus_data(:, 3);
model.angle_spec_deg = bus_data(:, 4);
model.P_gen = bus_data(:, 5);
model.Q_gen = bus_data(:, 6);
model.P_load = bus_data(:, 7);
model.Q_load = bus_data(:, 8);
model.G_shunt = bus_data(:, 9);
model.B_shunt = bus_data(:, 10);
model.Q_min = bus_data(:, 11);
model.Q_max = bus_data(:, 12);
model.P_net = model.P_gen - model.P_load;
model.Q_net = model.Q_gen - model.Q_load;
model.slack_buses = slack_buses;
model.pv_buses = pv_buses;
model.pq_buses = pq_buses;
model.line_from_idx = line_from_idx;
model.line_to_idx = line_to_idx;
model.Ybus = Ybus;
model.Gbus = real(Ybus);
model.Bbus = imag(Ybus);
model.delta_idx = [pv_buses; pq_buses];
model.V_idx = pq_buses;
model.n_delta = numel(model.delta_idx);
model.n_V = numel(model.V_idx);
model.n_total = model.n_delta + model.n_V;
end

function case_data = normalize_case_data(case_data)
if nargin < 1 || isempty(case_data)
    error('case_data is required.');
end

if ~isfield(case_data, 'bus_data') || isempty(case_data.bus_data)
    error('case_data.bus_data is required.');
end

if ~isfield(case_data, 'line_data') || isempty(case_data.line_data)
    error('case_data.line_data is required.');
end

if ~isfield(case_data, 'system_name') || isempty(case_data.system_name)
    case_data.system_name = 'N-Bus Power Flow System';
end

if ~isfield(case_data, 'base_values') || isempty(case_data.base_values)
    case_data.base_values = struct('S_base_MVA', 100, 'V_base_kV', 230, 'frequency_Hz', 60);
end

defaults = struct('S_base_MVA', 100, 'V_base_kV', 230, 'frequency_Hz', 60);
fields = fieldnames(defaults);
for i = 1:numel(fields)
    field_name = fields{i};
    if ~isfield(case_data.base_values, field_name) || isempty(case_data.base_values.(field_name))
        case_data.base_values.(field_name) = defaults.(field_name);
    end
end

switch size(case_data.bus_data, 2)
    case 8
        case_data.bus_data(:, 9:10) = 0;
        case_data.bus_data(:, 11) = -Inf;
        case_data.bus_data(:, 12) = Inf;
    case 10
        case_data.bus_data(:, 11) = -Inf;
        case_data.bus_data(:, 12) = Inf;
    case 12
        % Already complete.
    otherwise
        error('bus_data must have 8, 10, or 12 columns.');
end

switch size(case_data.line_data, 2)
    case 4
        case_data.line_data(:, 5:7) = [zeros(size(case_data.line_data, 1), 1), ones(size(case_data.line_data, 1), 1), zeros(size(case_data.line_data, 1), 1)];
    case 5
        case_data.line_data(:, 6:7) = [ones(size(case_data.line_data, 1), 1), zeros(size(case_data.line_data, 1), 1)];
    case 6
        case_data.line_data(:, 7) = 0;
    case 7
        % Already complete.
    otherwise
        error('line_data must have 4, 5, 6, or 7 columns.');
end
end

function validate_case_data(case_data)
bus_ids = case_data.bus_data(:, 1);
if numel(unique(bus_ids)) ~= numel(bus_ids)
    error('bus_data contains duplicate bus numbers.');
end

bus_types = case_data.bus_data(:, 2);
if sum(bus_types == 1) ~= 1
    error('Exactly one slack bus is required for this solver.');
end

if any(~ismember(bus_types, [1 2 3]))
    error('Bus types must be 1 (Slack), 2 (PV), or 3 (PQ).');
end

if any(case_data.bus_data(:, 3) <= 0)
    error('Initial/specified voltage magnitudes must be positive.');
end

if any(case_data.bus_data(:, 11) > case_data.bus_data(:, 12))
    error('Qmin must be less than or equal to Qmax for every bus.');
end

if any(case_data.line_data(:, 4) == 0 & case_data.line_data(:, 3) == 0)
    error('Each line must have non-zero impedance.');
end
end

function [Ybus, line_data] = build_ybus(bus_data, line_data, line_from_idx, line_to_idx)
num_buses = size(bus_data, 1);
num_lines = size(line_data, 1);
Ybus = zeros(num_buses, num_buses);

tap_zero = line_data(:, 6) == 0;
line_data(tap_zero, 6) = 1.0;

for i = 1:num_lines
    from = line_from_idx(i);
    to = line_to_idx(i);
    R = line_data(i, 3);
    X = line_data(i, 4);
    B_half = line_data(i, 5);
    tap_ratio = line_data(i, 6);
    phase_shift_deg = line_data(i, 7);

    tap = tap_ratio * exp(1i * deg2rad(phase_shift_deg));
    y_series = 1 / (R + 1i * X);
    y_shunt = 1i * B_half;

    Ybus(from, from) = Ybus(from, from) + (y_series + y_shunt) / (tap * conj(tap));
    Ybus(to, to) = Ybus(to, to) + y_series + y_shunt;
    Ybus(from, to) = Ybus(from, to) - y_series / conj(tap);
    Ybus(to, from) = Ybus(to, from) - y_series / tap;
end

G_shunt = bus_data(:, 9);
B_shunt = bus_data(:, 10);
for i = 1:num_buses
    Ybus(i, i) = Ybus(i, i) + G_shunt(i) + 1i * B_shunt(i);
end
end
