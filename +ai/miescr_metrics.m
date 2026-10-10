function [escr, info] = miescr_metrics(Ynet, bus_positions, Vm_pu, srated_pu, opt)
%MIESCR_METRICS  Multi-infeed effective short-circuit ratio at the IBR buses.
%
%   [ESCR, INFO] = ai.miescr_metrics(YNET, BUS_POSITIONS, VM_PU, SRATED_PU, OPT)
%
%   A single-infeed short-circuit ratio answers "how strong is the network at
%   this bus?". When several converters sit on the same island the question is
%   no longer separable: each converter's Thevenin is loaded by the others, and
%   the published MI-ESCR is the ratio that counts that loading. This function
%   is the instrument; it decides nothing and gates nothing.
%
%   MATHEMATICS
%       Y_sys     = YNET + diag(stamped source admittances)
%       Z_sys     = inv(Y_sys)                      (sources shorted)
%       S_sc,i    = |V_i|^2 / |Z_sys(i,i)|          [pu on the system base]
%       MII_ji    = |Z_sys(j,i)| / |Z_sys(i,i)|
%       ESCR_i    = S_sc,i / ( S_rated,i + sum_{j~=i} MII_ji * S_rated,j )
%
%   WHY THE SOURCE ADMITTANCE IS STAMPED ON THE DIAGONAL. A voltage source E
%   behind a series admittance y injects I = y*E - y*V. For a Thevenin
%   equivalent every source is shorted (E = 0), which leaves exactly -y*V: a
%   shunt admittance y at that bus. This is the same "voltage sources shorted"
%   convention the repository's single-infeed metric already uses
%   (+stability/ibr_scr_metrics.m:144-146), and it is why the augmented matrix
%   is YNET + diag(y) rather than something with a current-injection column.
%
%   WHAT IS *NOT* STAMPED. A grid-following converter is a current source: it
%   holds no bus voltage of its own and contributes no Thevenin admittance. It
%   is represented by the ABSENCE of a source entry, not by a small one. Do not
%   stamp a nominal admittance for a GFL unit to "be fair" to it -- that would
%   invent voltage support the model does not provide.
%
%   YNET must be the SAME passive network the metric is being compared against,
%   including or excluding constant-impedance load exactly as that comparison
%   requires. This function does not add or remove load; it takes YNET as given
%   and only stamps sources onto it.
%
%   OPT fields
%     sources    struct array, one entry per source to stamp. Fields:
%                  bus_position  row index into YNET (1..nb)
%                  admittance    complex pu, the series admittance BEHIND the
%                                source; 0/NaN/empty skips the entry
%                  name          char/string label, carried into INFO only
%                Default: empty (no source stamped), in which case the result
%                degenerates to the single-infeed ratio at every bus and
%                MII == 0.
%     form       "cigre"    (default) interaction terms load the denominator
%                "numerator" interaction terms are subtracted from S_sc
%                The two are NOT equivalent. "cigre" is the published
%                multi-infeed definition; "numerator" is retained because it
%                can go NEGATIVE on a very weak island, which is a shape worth
%                being able to see. INFO always carries both.
%     sbase_MVA  system base, default 100. Reported, not used: every quantity
%                below is a ratio on that base.
%
%   RETURNS
%     ESCR  m-by-1, the requested form. NaN where the solve failed, where the
%           rating is not finite and positive, or where the bus voltage is not
%           finite. NaN -- never 0, which would read as "infinitely weak" and
%           invert any rule that ranks on the smallest value.
%     INFO  .Z_sys (m-by-m)    self and mutual Thevenin impedances at the IBR
%           .Ssc_pu (m-by-1)   short-circuit capacity, pu on the system base
%           .MII (m-by-m)      MII(j,i) = |Z(j,i)|/|Z(i,i)|, diagonal 0
%           .escr_cigre        denominator form
%           .escr_numerator    numerator form (may be negative)
%           .Y_sys, .sbase_MVA, .form, .sources_applied, .classification
%
%   CLASSIFICATION. Every output is a DIAGNOSTIC. The production SCR gate for
%   the full-state IBR families is forced to
%   'not_applicable_full_state_source_model' and admits them without consulting
%   any short-circuit number (+stability/ibr_scr_metrics.m:266-292). Nothing
%   here changes that, and nothing here may be cited as gate evidence.
%
%   See also ai.ai_escr_metrics, ai.miescr_condition_study.

arguments
    Ynet (:,:) double
    bus_positions (1,:) double {mustBePositive, mustBeInteger}
    Vm_pu double {mustBeReal}
    srated_pu (1,:) double {mustBePositive}
    opt struct = struct()
end

m = numel(bus_positions);
if numel(srated_pu) ~= m
    error('ai:miescr_metrics:ratingCountMismatch', ...
        'Got %d bus positions but %d ratings; they must correspond one to one.', ...
        m, numel(srated_pu));
end
nb = size(Ynet, 1);
if size(Ynet, 2) ~= nb || nb == 0
    error('ai:miescr_metrics:notSquare', 'Ynet must be a non-empty square matrix.');
end
if any(bus_positions > nb)
    error('ai:miescr_metrics:busOutOfRange', ...
        'A bus position exceeds the %d-by-%d admittance.', nb, nb);
end
if numel(Vm_pu) == nb
    Vm = Vm_pu(bus_positions);
elseif numel(Vm_pu) == m
    Vm = Vm_pu(:).';
else
    error('ai:miescr_metrics:voltageLengthMismatch', ...
        ['Vm_pu has %d entries; expected %d (one per bus) or %d ' ...
         '(one per IBR bus).'], numel(Vm_pu), nb, m);
end

form = lower(string(getfield_default(opt, 'form', "cigre")));
if ~any(form == ["cigre","numerator"])
    error('ai:miescr_metrics:badForm', ...
        'form must be "cigre" or "numerator", got "%s".', form);
end

% --- stamp the sources ----------------------------------------------------
Ysys = Ynet;
applied = strings(0, 1);
sources = getfield_default(opt, 'sources', struct([]));
for k = 1:numel(sources)
    bp = sources(k).bus_position;
    if isempty(bp) || ~isscalar(bp) || ~isfinite(bp) || bp < 1 || bp > nb
        error('ai:miescr_metrics:badSourceBus', ...
            'sources(%d).bus_position is not a valid row index into Ynet.', k);
    end
    if ~isfield(sources(k), 'admittance'), continue; end
    y = sources(k).admittance;
    if isempty(y) || ~isscalar(y) || ~isfinite(y) || y == 0
        % A source with no admittance is a current source. It contributes
        % nothing to the Thevenin; it is skipped, not approximated.
        continue;
    end
    Ysys(bp, bp) = Ysys(bp, bp) + y;
    nm = string(getfield_default(sources(k), 'name', sprintf('bus%d', bp)));
    applied(end+1, 1) = nm; %#ok<AGROW>
end

% --- Thevenin -------------------------------------------------------------
info = struct();
info.Y_sys = Ysys;
info.sbase_MVA = getfield_default(opt, 'sbase_MVA', 100.0);
info.form = form;
info.sources_applied = applied;
info.classification = 'PROJECT_DERIVED diagnostic; not gate evidence';

Z = nan(nb, nb);
info.is_singular = false;
if rcond(Ysys) < 1e-14 || ~all(isfinite(Ysys(:)))
    info.is_singular = true;
else
    try
        Zful = Ysys \ eye(nb);
    catch
        Zful = nan(nb, nb);
    end
    if all(isfinite(Zful(:)))
        Z = Zful;
    else
        info.is_singular = true;
    end
end

self = arrayfun(@(i) Z(i, i), bus_positions);
info.Z_sys = Z(bus_positions, bus_positions);

Ssc = nan(1, m);
MII = zeros(m, m);
for i = 1:m
    if ~isfinite(self(i)) || abs(self(i)) <= eps || ~isfinite(Vm(i))
        continue;
    end
    Ssc(i) = (Vm(i)^2) / abs(self(i));
    for j = 1:m
        if j == i, continue; end
        MII(j, i) = abs(Z(bus_positions(j), bus_positions(i))) / abs(self(i));
    end
end

info.Ssc_pu = Ssc(:);
info.MII = MII;

% --- the two forms --------------------------------------------------------
e_cig = nan(1, m);
e_num = nan(1, m);
for i = 1:m
    if ~isfinite(Ssc(i)), continue; end
    load_i = 0;
    for j = 1:m
        if j == i, continue; end
        load_i = load_i + MII(j, i) * srated_pu(j);
    end
    e_cig(i) = Ssc(i) / (srated_pu(i) + load_i);
    e_num(i) = (Ssc(i) - load_i) / srated_pu(i);
end
info.escr_cigre = e_cig(:);
info.escr_numerator = e_num(:);

if form == "cigre"
    escr = e_cig(:);
else
    escr = e_num(:);
end
end

% =========================================================================
function v = getfield_default(s, name, dflt)
%GETFIELD_DEFAULT  s.name when present and non-empty, otherwise dflt.
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = dflt;
end
end
