function [study, T] = miescr_condition_study(case_profile, opt)
%MIESCR_CONDITION_STUDY  ESCR across the four switchable conditions.
%
%   [STUDY, T] = ai.miescr_condition_study(CASE_PROFILE, OPT)
%
%   Builds the IEEE-14 case's own passive network once, then evaluates the
%   multi-infeed ESCR under the conditions the switching decision distinguishes:
%
%     C1  SG online,  no converter forming     the pre-trip reference
%     C2  SG offline, no converter forming      the islanded weak-grid case
%     C3  SG offline, 1-2 converters forming    the adaptive policy's range
%     C4  SG offline, all four forming          the pinned arm
%
%   WHAT IS HELD FIXED, AND WHY. The bus-voltage magnitudes are held at the
%   case's own base-load equilibrium for every condition, so the movement shown
%   between C1 and C2 is the movement of the NETWORK SUPPORT alone, not a
%   mixture of support and voltage. That is the comparison the question is
%   about -- "does promoting a converter change the strength of the network?"
%   -- and holding |V| is what isolates it. A condition that also re-solved its
%   own operating point would move two things at once. INFO carries the |V|
%   used so the choice is visible rather than implied.
%
%   SOURCES, all read from the case, none assumed:
%     y_sg  = 1/(j*Xdpp) on the system base, Xdpp scaled by Sbase/S_MVA from
%             the machine block. Stamped only while the SG is online.
%     y_gfm = 1/(Rf + j*Lf) from the converter's own gfm_eecon49 parameters.
%             Stamped only at buses whose converter is forming.
%   A grid-following converter stamps nothing: it is a current source and
%   contributes no Thevenin admittance.
%
%   OPT fields
%     form        passed through to ai.miescr_metrics, default "cigre"
%     zeta_table  path to the frozen admissibility summary that carries
%                 zeta_worst per forming set. Default
%                 output/diagnostics/ieee14_gfm_lock_compare_zeta/summary.mat.
%                 Read only; a missing file leaves the damping column NaN and
%                 the study still returns.
%     verbose     default true
%
%   T is a MATLAB table with one row per condition. STUDY carries the raw
%   per-condition structs (Z, S_sc, MII, ESCR) for a caller that wants more
%   than the summary.
%
%   CLASSIFICATION. Every number here is a DIAGNOSTIC. The SCR gate is forced
%   to 'not_applicable_full_state_source_model' for this model family and
%   admits it without consulting any short-circuit number
%   (+stability/ibr_scr_metrics.m:266-292). Nothing here is gate evidence, and
%   no result in this repository consumes it.
%
%   See also ai.miescr_metrics, ai.ai_escr_metrics.

arguments
    case_profile (1,1) string = "eecon49_figure4"
    opt struct = struct()
end

pf_init_paths();

verbose = getfield_default(opt, 'verbose', true);
form = getfield_default(opt, 'form', "cigre");
sbase = 100.0;

say(verbose, sprintf('=== MI-ESCR condition study :: %s ===', case_profile));

% --- the case, its devices and its base-load operating point --------------
scen = cases.scenario_ieee14_1sg_4ibr(struct('case_profile', char(case_profile)));
[devices0, ~] = stability.build_mixed_resource_devices( ...
    scen.case_data, scen.resources, scen.scenario_opt);
eq = stability.mixed_equilibrium_solve(scen.case_data, ...
    struct('devices', devices0), struct('verbose', false));
if ~eq.converged
    error('ai:miescr_condition_study:equilibrium', ...
        'The base-load equilibrium did not converge: %s', eq.failure_reason);
end
dae = stability.composite_dae(scen.case_data, eq.devices, ...
    struct('load_model', 'cz_p_cz_q'));
Ynet = dae.Ynet;

bus_ids = scen.case_data.mpc.bus(:, 1);
nb = numel(bus_ids);
pos = @(b) find(bus_ids == b, 1);
p_sg = pos(1);

% Base-load |V|, held fixed across conditions by design (see header).
y0 = eq.y0;
Vm = abs(y0(1:2:end) + 1i*y0(2:2:end));
if numel(Vm) ~= nb
    error('ai:miescr_condition_study:voltageLayout', 'The equilibrium vector holds %d voltages but the case has %d buses.', numel(Vm), nb);
end

% --- source admittances, from the case ------------------------------------
mc = scen.case_data.machines;
Xdpp = mc.reactances.Xdpp * (sbase / mc.base.S_MVA);
y_sg = 1 / (1i * Xdpp);

is_ibr = arrayfun(@(r) strcmp(r.model_id, 'eecon49_dual'), scen.resources);
ibr_res = scen.resources(is_ibr);
conv_buses = arrayfun(@(r) r.bus_id, ibr_res);
srated = arrayfun(@(r) r.ratings.Mbase, ibr_res) / sbase;
gp = ibr_res(1).dynamic_params.gfm_eecon49;
for k = 2:numel(ibr_res)
    g2 = ibr_res(k).dynamic_params.gfm_eecon49;
    if g2.Rf ~= gp.Rf || g2.Lf ~= gp.Lf
        error('ai:miescr_condition_study:filterMismatch', 'Converters %d and %d carry different GFM filters; no single admittance can represent both.', 1, k);
    end
end
y_gfm = 1 / (gp.Rf + 1i * gp.Lf);

say(verbose, sprintf('  Xdpp %.6f pu (%.0f MVA base) -> |y_sg| %.4f', ...
    Xdpp, mc.base.S_MVA, abs(y_sg)));
say(verbose, sprintf('  Rf %.4f  Lf %.4f pu -> |y_gfm| %.4f', ...
    gp.Rf, gp.Lf, abs(y_gfm)));
say(verbose, sprintf('  converter buses %s  ratings %s pu', ...
    mat2str(conv_buses), mat2str(srated)));

zvals = damping_by_set(getfield_default(opt, 'zeta_table', ...
    fullfile('output', 'diagnostics', 'ieee14_gfm_lock_compare_zeta', 'summary.mat')));

% --- the conditions -------------------------------------------------------
% Device indices as the report uses them: [1]=SG [2]=IBR2 [3]=IBR3 [4]=IBR6
% [5]=IBR8. Forming sets below are written in those indices.
cond_ids = {'C1_SG_on_0gfm', 'C2_SG_off_0gfm', 'C3a_SG_off_1gfm', ...
    'C3b_SG_off_2gfm', 'C4_SG_off_4gfm'};
cond_labels = {'SG online, no former', 'islanded, no former', ...
    'islanded, {IBR2} forming', 'islanded, {IBR2,IBR6} forming', ...
    'islanded, all four forming'};
cond_sg_online = [true false false false false];
cond_forming = {[], [], 2, [2 4], [2 3 4 5]};
n_cond = numel(cond_ids);

study = struct('case_profile', case_profile, 'Ynet', Ynet, ...
    'bus_ids', bus_ids, 'conv_buses', conv_buses, 'Vm_pu', Vm, ...
    'srated_pu', srated, 'y_sg', y_sg, 'y_gfm', y_gfm, ...
    'Xdpp_pu', Xdpp, 'Rf', gp.Rf, 'Lf', gp.Lf, 'form', string(form), ...
    'zeta_source', '', 'conditions', struct([]));

rows = struct('id', {}, 'label', {}, 'sg_online', {}, 'n_forming', {}, ...
    'escr_ibr2', {}, 'escr_min', {}, 'escr_max', {}, 'Ssc_ibr2', {}, ...
    'MII_max', {}, 'zeta_worst', {});

say(verbose, '');
say(verbose, sprintf('%-20s %-28s %5s %10s %10s %10s %8s', ...
    'condition', 'label', 'nGFM', 'ESCR(IBR2)', 'ESCR_min', 'ESCR_max', '#zeta'));

for c = 1:n_cond
    sources = struct('bus_position', {}, 'admittance', {}, 'name', {});
    if cond_sg_online(c)
        sources(end+1) = struct('bus_position', p_sg, 'admittance', y_sg, ...
            'name', "SG1"); %#ok<AGROW>
    end
    for d = cond_forming{c}
        bp = pos(conv_buses(d - 1));
        sources(end+1) = struct('bus_position', bp, 'admittance', y_gfm, ...
            'name', sprintf('IBR%d', conv_buses(d - 1))); %#ok<AGROW>
    end

    [e, info] = ai.miescr_metrics(Ynet, arrayfun(pos, conv_buses), ...
        Vm, srated, struct('sources', sources, 'form', form, ...
        'sbase_MVA', sbase));

    zw = zvals.set_key(cond_forming{c});
    rows(end+1) = struct('id', string(cond_ids{c}), ...
        'label', string(cond_labels{c}), 'sg_online', cond_sg_online(c), ...
        'n_forming', numel(cond_forming{c}), ...
        'escr_ibr2', e(1), 'escr_min', min(e), 'escr_max', max(e), ...
        'Ssc_ibr2', info.Ssc_pu(1), 'MII_max', max(info.MII(:)), ...
        'zeta_worst', zw); %#ok<AGROW>

    cs = struct('id', cond_ids{c}, 'label', cond_labels{c}, ...
        'sg_online', cond_sg_online(c), 'forming', cond_forming{c}, ...
        'sources', sources, 'escr', e, 'info', info, 'zeta_worst', zw);
    if isempty(study.conditions), study.conditions = cs;
    else, study.conditions(end+1) = cs; end

    say(verbose, sprintf('%-20s %-28s %5d %10.4f %10.4f %10.4f %8s', ...
        cond_ids{c}, cond_labels{c}, numel(cond_forming{c}), e(1), ...
        min(e), max(e), num2str(zw, '%.4f')));
end

T = struct2table(rows);
say(verbose, '');
end

% =========================================================================
function z = damping_by_set(summary_path)
%DAMPING_BY_SET  zeta_worst per forming set, read from the frozen admissibility
%   table. Two fields of the delivered record are used, both written by the run
%   that certified the sets, neither recomputed here:
%
%     selected   the forming set, as the same device indices this study uses
%                ([1]=SG1 [2]=IBR2 [3]=IBR3 [4]=IBR6 [5]=IBR8), so the key needs
%                no translation.
%     reason     the run's own one-line justification, which carries the number
%                as "robust zeta 0.1223 >= 0.05". The compact summary does not
%                keep zeta_worst as its own field; it keeps the sentence that
%                quotes it. Parsing that sentence is reading the artefact.
%
%   If the sentence ever stops carrying the number, the column goes NaN and the
%   study still returns -- NaN is the honest outcome there, not a substitute
%   value. A missing or unreadable file behaves the same way.
z = struct('set_key', @(forming) NaN, 'source', '');
if ~isfile(summary_path)
    return;
end
try
    S = load(summary_path, 'summary');
catch
    return;
end

keys = {};
vals = [];
if isfield(S, 'summary') && isfield(S.summary, 'shared') && ...
        isfield(S.summary.shared, 'sg_off_candidates')
    c = S.summary.shared.sg_off_candidates;
    for k = 1:numel(c)
        if ~isfield(c(k), 'feasible') || ~c(k).feasible, continue; end
        if ~isfield(c(k), 'selected') || isempty(c(k).selected), continue; end
        zw = zeta_from_reason(c(k));
        if ~isfinite(zw), continue; end
        keys{end+1} = mat2str(sort(c(k).selected(:).')); %#ok<AGROW>
        vals(end+1) = zw; %#ok<AGROW>
    end
end
z.source = summary_path;
z.set_key = @(forming) lookup(keys, vals, forming);
end

function zw = zeta_from_reason(c)
%ZETA_FROM_REASON  The 'robust zeta <value>' sentence the run itself published.
zw = NaN;
if ~isfield(c, 'reason'), return; end
tok = regexp(char(string(c.reason)), ...
    'robust zeta\s+([0-9.eE+-]+)', 'tokens', 'once');
if isempty(tok), return; end
v = str2double(tok{1});
if isfinite(v), zw = v; end
end

function v = lookup(keys, vals, forming)
v = NaN;
if isempty(forming), return; end
hit = find(strcmp(keys, mat2str(sort(forming(:).'))), 1);
if ~isempty(hit), v = vals(hit); end
end

function v = getfield_default(s, name, dflt)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = dflt;
end
end

function say(verbose, msg)
if verbose, fprintf('%s\n', msg); end
end
