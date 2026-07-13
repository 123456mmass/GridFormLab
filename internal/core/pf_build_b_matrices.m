function [Bp, Bpp] = pf_build_b_matrices(model, variant)
%PF_BUILD_B_MATRICES  Construct FDPF B' and B'' matrices per Stott-Alsac / van Amerongen.
%   [BP, BPP] = PF_BUILD_B_MATRICES(MODEL, VARIANT) returns the decoupled
%   susceptance matrices B' (P-theta) and B'' (Q-V) for the fast decoupled
%   load flow, per the verified sources:
%
%   Sources (VERIFIED):
%     Stott & Alsac (1974), "Fast Decoupled Load Flow", IEEE Trans. PAS-93,
%       pp.859-869, DOI 10.1109/TPAS.1974.293985. Construction items (a)-(d)
%       p.863; final equations (8) [dP/V]=[B'][dtheta] and (9) [dQ/V]=[B''][dV].
%     van Amerongen (1989), "A General-Purpose Version of the Fast Decoupled
%       Loadflow", IEEE Trans. Power Systems 4(2), pp.760-766, p.761.
%       Variant definitions: BB / XB / BX / XX.
%
%   Variant R-treatment (verified, per van Amerongen p.761):
%     'XB' (standard FDL, Stott-Alsac original): remove R in B' only;
%          B' is made of branch reactances (1/X). B'' retains R (full series
%          admittance). [Stott-Alsac item (d) + van Amerongen XB def]
%     'BX' (van Amerongen proposed): retain R in B' (X/(R^2+X^2)); remove R
%          in B'' (B'' made of branch reactances 1/X). [van Amerongen BX def]
%
%   Common construction (verified, Stott-Alsac items a-d):
%     B' : omit shunt reactances and off-nominal in-phase transformer taps
%          (item a); omit series resistance per variant (item d / BX); omit
%          phase-shift angle (set phase_shift=0).
%     B'': omit angle-shifting effects of phase shifters (item b); include
%          line charging and bus shunts; off-nominal tap ratios included;
%          series resistance per variant (retain for XB, omit for BX).
%
%   Row/column sets (matches NR partitioning):
%     B'  unknowns: delta_idx = [pv_buses; pq_buses] (P-theta; REF excluded)
%     B'' unknowns: V_idx = pq_buses (Q-V; PV excluded)
%   The FULL matrices (all buses) are returned; the caller indexes the
%   reduced sets. This keeps the construction readable and matches the
%   project's existing indexing convention (model.delta_idx, model.V_idx).
%
%   No inv/pinv. Matrices are built directly from line_data/bus_data.
%   Parallel branches accumulate via +=.

if nargin < 2, variant = 'XB'; end
variant = upper(variant);
switch variant
    case {'XB', 'BX'}
        % allowed
    otherwise
        error('pf_build_b_matrices:unknownVariant', ...
            'Unknown FDPF variant ''%s''. Allowed: XB, BX.', variant);
end

bus_data = model.bus_data;
line_data = model.line_data;
external_bus_ids = bus_data(:, 1);
[line_from_ok, line_from_idx] = ismember(line_data(:, 1), external_bus_ids);
[line_to_ok, line_to_idx] = ismember(line_data(:, 2), external_bus_ids);

num_buses = size(bus_data, 1);
num_lines = size(line_data, 1);
Bp  = zeros(num_buses, num_buses);   % B'  (P-theta)
Bpp = zeros(num_buses, num_buses);   % B'' (Q-V)

for i = 1:num_lines
    from = line_from_idx(i);
    to   = line_to_idx(i);
    R = line_data(i, 3);
    X = line_data(i, 4);
    B_half = line_data(i, 5);
    tap_ratio = line_data(i, 6);
    if tap_ratio == 0, tap_ratio = 1.0; end

    % --- B' (P-theta): no shunt, no charging, no tap, no phase shift ---
    % B' = -imag(Ybus_reduced) per Stott-Alsac "elements of [-B]": diagonal
    % POSITIVE (sum of branch susceptances), off-diagonal NEGATIVE.
    % Equation (8) [dP/V]=[B'][dtheta] with B' = -B gives dtheta = B'\(dP/V)
    % = (-B)\(dP/V) = -(dP/V)/B, which is the correct Newton direction
    % (since dP/dtheta ~ -V^2*B, so dtheta = dP/(dP/dtheta) = -dP/(V^2*B),
    % matching dtheta = (dP/V)/(-B) = (dP/V)/B' with B' = -B).
    switch variant
        case 'XB'
            % remove R in B' (item d): series susceptance magnitude = 1/X.
            b_series_bp = 1/X;
        case 'BX'
            % retain R in B': series susceptance magnitude = X/(R^2+X^2).
            b_series_bp = X/(R^2 + X^2);
    end
    % B' = -imag(Ybus): off-diag = -b_series, diag = +b_series.
    Bp(from, from) = Bp(from, from) + b_series_bp;
    Bp(to, to)     = Bp(to, to)     + b_series_bp;
    Bp(from, to)   = Bp(from, to)   - b_series_bp;
    Bp(to, from)   = Bp(to, from)   - b_series_bp;

    % --- B'' (Q-V): include charging, shunt, tap; R per variant ---
    % B'' = -imag(Ybus) convention (same as B'): off-diag = -b_series, diag = +b_series.
    switch variant
        case 'XB'
            % retain R in B'': series susceptance magnitude = X/(R^2+X^2).
            b_series_bpp = X/(R^2 + X^2);
        case 'BX'
            % remove R in B'' (BX): series susceptance magnitude = 1/X.
            b_series_bpp = 1/X;
    end
    % Line charging (B_half) included in B'' diagonal (both ends, magnitude).
    % B'' = -imag(Ybus): off-diag = -b_series, diag = +b_series + B_half.
    Bpp(from, from) = Bpp(from, from) + b_series_bpp + B_half;
    Bpp(to, to)     = Bpp(to, to)     + b_series_bpp + B_half;
    Bpp(from, to)   = Bpp(from, to)   - b_series_bpp / tap_ratio;
    Bpp(to, from)   = Bpp(to, from)   - b_series_bpp / tap_ratio;
end

% Bus shunts (G_shunt, B_shunt) added to B'' diagonal only (item a omits
% shunt reactances from B'). B'' includes bus shunt susceptance.
B_shunt = bus_data(:, 10);
for i = 1:num_buses
    Bpp(i, i) = Bpp(i, i) + B_shunt(i);
end
end
