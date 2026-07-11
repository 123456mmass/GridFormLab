function rel = coi_relative(delta, omega, H, gen_buses)
%COI_RELATIVE  Inertia-weighted center-of-inertia (COI) relative quantities.
%   rel = COI_RELATIVE(delta, omega, H, gen_buses) computes the COI frame for
%   BOTH rotor angle and speed using inertia weights H (NOT arithmetic mean):
%       delta_coi = sum(H .* delta, 2) / sum(H)
%       omega_coi = sum(H .* omega, 2) / sum(H)
%       delta_rel = delta - delta_coi
%       omega_rel = omega - omega_coi
%   Inputs (columns = generators, mapped by gen_buses):
%     delta : [nt x ng] rotor angles (any consistent unit, e.g. deg or rad)
%     omega : [nt x ng] rotor speeds (pu deviation or absolute)
%     H     : [1 x ng] or [ng x 1] inertia constants (per generator bus)
%     gen_buses : [ng x 1] generator bus IDs (for mapping; not used in math
%                 but carried so callers keep angle/speed on the same mapping)
%   Output: struct with delta_coi, omega_coi, delta_rel, omega_rel.
%   Using arithmetic mean for speed (omega - mean(omega,2)) is WRONG when
%   inertias differ; this function always uses inertia weights.

if nargin < 4, gen_buses = []; end
H = H(:).';   % row vector [1 x ng]
if numel(H) ~= size(delta,2) || numel(H) ~= size(omega,2)
    error('coi_relative:dim', 'H length (%d) must match ng=%d (delta) / ng=%d (omega).', ...
        numel(H), size(delta,2), size(omega,2));
end
Hsum = sum(H);
if Hsum <= 0, error('coi_relative:badH', 'sum(H) must be positive.'); end
delta_coi = (delta .* H) ./ Hsum;   % sum over columns implicitly via .* + sum? no:
delta_coi = sum(delta .* H, 2) ./ Hsum;
omega_coi = sum(omega .* H, 2) ./ Hsum;
rel = struct();
rel.delta_coi = delta_coi;
rel.omega_coi = omega_coi;
rel.delta_rel = delta - delta_coi;
rel.omega_rel = omega - omega_coi;
rel.H = H;
rel.gen_buses = gen_buses;
end
