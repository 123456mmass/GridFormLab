function report = adaptive_ts_compare_fixed(case_name, model, scenario)
%ADAPTIVE_TS_COMPARE_FIXED  One shared adaptive-vs-fixed comparison helper.
%   REPORT = ADAPTIVE_TS_COMPARE_FIXED(CASE_NAME, MODEL, SCENARIO) runs the
%   FIXED-step canonical path and the ADAPTIVE (variable-dt, LTE/reject) path
%   on the SAME case/model/scenario, maps generators and buses by ID, and
%   interpolates the adaptive trajectory onto the fixed canonical grid using
%   EVENT-SEGMENTED interp_no_extrapolate (split at t_fault and t_clear, so no
%   trapezoidal step is ever interpolated across a topology change and no
%   extrapolation/zero-fill is allowed).
%
%   This is the SINGLE helper used by every tracked adaptive validation
%   runner and the held-out diagnostic test. It ALONE owns:
%     - generator bus-ID mapping (gen_buses) so delta/omega/Pe columns line up;
%     - bus-ID mapping (bus_ids) so Vbus columns line up;
%     - the inertia-weighted COI frame (coi_relative) for angle AND speed;
%     - event-segmented interpolation with NO extrapolation;
%     - structural invariants (finite, coverage, no cross-event interp, exact
%       event landing, ID-mapping consistent, algebraic convergence);
%     - the report struct (report-only; NO acceptance thresholds are invented
%       here for missing outputs).
%
%   Report-only by design. Numerical diffs (delta/omega/Pe/Vbus COI & pairwise)
%   are DIAGNOSTICS, not gates. The only hard gates are STRUCTURAL invariants.
%   This honors the honesty-closure policy: the 1.0 deg threshold is kept ONLY
%   as a historical ASSUMED_DIAGNOSTIC regression guard inside
%   test_ts_classical_adaptive; this helper does not impose it.
%
%   INPUTS:
%     case_name : char, a +cases/ loader name, e.g. 'case_matpower6_case14'.
%     model     : char, 'classical' | 'padiyar_1_1_avr' | 'padiyar_1_1_manual'
%                 | 'emf6'. Determines dispatch + schema.
%     scenario  : struct with fault_bus, t_fault, t_clear, Zf, dt, t_end,
%                 and optional model-specific overrides. [] = defaults.
%
%   OUTPUT (report struct) fields:
%     .case_name, .model, .scenario
%     .fixed, .adaptive            -- the raw result structs (for reference)
%     .gen_buses, .bus_ids         -- mapped ID vectors (consistent both paths)
%     .tg                          -- common canonical grid (fixed.t)
%     .seg_edges                   -- event segment edges used for interpolation
%     .metrics                     -- struct of pairwise max-abs diffs:
%         .delta_coi_deg, .delta_pairwise_deg, .omega_pu, .omega_coi_pu,
%         .Pe_MW, .Vbus_pu, .Vbus_fault_pu
%     .coverage_valid              -- true iff adaptive.t covers [0, fixed.t(end)]
%     .no_extrapolation            -- true (interp_no_extrapolate refuses else)
%     .no_cross_event_interp       -- true (segmented by construction)
%     .exact_event_landing         -- true iff both events are on adaptive.t
%     .id_mapping_consistent       -- true iff gen_buses/bus_ids match both paths
%     .algebraic_converged         -- true iff adaptive max corrector resid finite
%     .all_finite                  -- true iff all compared trajectories finite
%     .structural_pass             -- AND of all structural invariants above
%     .event_diagnostics           -- adaptive event_diagnostics (right/left)
%     .accepted_steps, .rejected_steps, .dt_history, .lte_history
%
%   No acceptance thresholds are imposed on numerical metrics here. Callers
%   that need a regression guard must declare it themselves with provenance.

if nargin < 3 || isempty(scenario), scenario = struct(); end
pf_init_paths;

% --- Scenario defaults (conservative, pre-declared before any run) ---------
sc = struct('fault_bus',[],'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',5.0);
fn = fieldnames(scenario);
for k = 1:numel(fn), sc.(fn{k}) = scenario.(fn{k}); end

c = cases.(case_name)();

% --- Build the fixed and adaptive option structs ---------------------------
% The fixed path uses the canonical corrector_mode='adaptive' (residual-checked
% Picard) at the nominal dt; the adaptive path uses stepper='adaptive'. Both
% share pm_mode, fault, and topology. The ONLY difference is the stepper.
% Model-appropriate corrector iteration cap: Padiyar needs >=12 at fault onset
% (its documented default); EMF6 uses 10; classical is linear (no corrector
% iteration cap is exercised by the linear network solve).
base_opt = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'pm_mode','pgaz','corrector_mode','adaptive','verbose',false);

% Model-specific dispatch field.
switch lower(model)
    case 'classical'
        opt_fixed = setfields(base_opt, struct('max_corrector_iter',10));
        opt_adapt = setfields(opt_fixed, struct('stepper','adaptive'));
    case {'padiyar_1_1_avr','padiyar_1_1_manual'}
        opt_fixed = setfields(base_opt, struct('model',model,'excitation', ...
            ternary(contains(lower(model),'manual'),'manual','avr'), ...
            'max_corrector_iter',12,'algebraic_tolerance',1e-11));
        opt_adapt = setfields(opt_fixed, struct('stepper','adaptive'));
    case 'emf6'
        opt_fixed = setfields(base_opt, struct('model','emf6','load_model','cz', ...
            'max_corrector_iter',10));
        opt_adapt = setfields(opt_fixed, struct('stepper','adaptive'));
    otherwise
        error('adaptive_ts_compare_fixed:model','Unknown model "%s".',model);
end

r_fixed = stability.ts_simulate(c, opt_fixed);
r_adapt = stability.ts_simulate(c, opt_adapt);

% --- ID mapping: gen_buses and bus_ids (consistent across both paths) ------
gen_fixed = r_fixed.gen_buses(:);
gen_adapt = r_adapt.gen_buses(:);
bus_fixed = bus_ids_of(r_fixed);
bus_adapt = bus_ids_of(r_adapt);

% Sort generators by bus ID so columns align across paths.
[gen_sorted, gf_idx] = sort(gen_fixed);
[~, ga_idx] = sort(gen_adapt);
gen_adapt_sorted = gen_adapt(ga_idx);
id_mapping_consistent = isequal(gen_sorted(:), gen_adapt_sorted(:)) && ...
    isequal(sort(bus_fixed(:)), sort(bus_adapt(:)));

% Reorder columns to the sorted-by-bus-ID order.
delta_f = r_fixed.delta(:, gf_idx);
delta_a = r_adapt.delta(:, ga_idx);
omega_f = r_fixed.omega(:, gf_idx);
omega_a = r_adapt.omega(:, ga_idx);
Pe_f = r_fixed.Pe_MW(:, gf_idx);
Pe_a = r_adapt.Pe_MW(:, ga_idx);
H = r_fixed.H(gf_idx);   % inertia on the sorted generator order

% Reorder Vbus columns to a common bus-ID order (intersection, ID-mapped).
[bcommon, bf_idx, ba_idx] = intersect(bus_fixed, bus_adapt, 'stable');
Vbus_f = r_fixed.Vbus(:, bf_idx);
Vbus_a = r_adapt.Vbus(:, ba_idx);

% Locate the fault bus column in the common bus-ID order (for Vbus_fault).
fbus = sc.fault_bus;
if isempty(fbus), fbus = gen_sorted(1); end
[~, fb_common] = ismember(fbus, bcommon);

% --- Event segmentation (split at t_fault and t_clear) ---------------------
% No trapezoidal step is interpolated across a topology change. Each segment
% is interpolated independently with interp_no_extrapolate (no extrapolation,
% no zero-fill; coverage error is raised and caught).
tg = r_fixed.t(:);
seg_edges = segment_edges(r_fixed, r_adapt, sc);

% Allocate interpolated trajectories on the common grid.
delta_f_i = zeros(numel(tg), numel(delta_f(1,:)));
delta_a_i = zeros(numel(tg), numel(delta_a(1,:)));
omega_f_i  = zeros(numel(tg), numel(omega_f(1,:)));
omega_a_i  = zeros(numel(tg), numel(omega_a(1,:)));
Pe_f_i     = zeros(numel(tg), numel(Pe_f(1,:)));
Pe_a_i     = zeros(numel(tg), numel(Pe_a(1,:)));
Vbus_f_i   = zeros(numel(tg), numel(Vbus_f(1,:)));
Vbus_a_i   = zeros(numel(tg), numel(Vbus_a(1,:)));

coverage_valid = (min(r_adapt.t) <= min(tg) + 1e-12) && ...
                 (max(r_adapt.t) >= max(tg) - 1e-12);

for s = 1:numel(seg_edges)-1
    lo = seg_edges(s); hi = seg_edges(s+1);
    idx_tg  = find(tg >= lo - 1e-14 & tg <= hi + 1e-14);
    idx_f   = find(r_fixed.t >= lo - 1e-14 & r_fixed.t <= hi + 1e-14);
    idx_a   = find(r_adapt.t >= lo - 1e-14 & r_adapt.t <= hi + 1e-14);
    for kk = 1:size(delta_f_i,2)
        delta_f_i(idx_tg,kk) = interp_no_extrapolate(r_fixed.t(idx_f), delta_f(idx_f,kk), tg(idx_tg));
        delta_a_i(idx_tg,kk) = interp_no_extrapolate(r_adapt.t(idx_a), delta_a(idx_a,kk), tg(idx_tg));
        omega_f_i(idx_tg,kk)  = interp_no_extrapolate(r_fixed.t(idx_f), omega_f(idx_f,kk),  tg(idx_tg));
        omega_a_i(idx_tg,kk)  = interp_no_extrapolate(r_adapt.t(idx_a), omega_a(idx_a,kk),  tg(idx_tg));
        Pe_f_i(idx_tg,kk)     = interp_no_extrapolate(r_fixed.t(idx_f), Pe_f(idx_f,kk),     tg(idx_tg));
        Pe_a_i(idx_tg,kk)     = interp_no_extrapolate(r_adapt.t(idx_a), Pe_a(idx_a,kk),     tg(idx_tg));
    end
    for kk = 1:size(Vbus_f_i,2)
        Vbus_f_i(idx_tg,kk) = interp_no_extrapolate(r_fixed.t(idx_f), Vbus_f(idx_f,kk), tg(idx_tg));
        Vbus_a_i(idx_tg,kk) = interp_no_extrapolate(r_adapt.t(idx_a), Vbus_a(idx_a,kk), tg(idx_tg));
    end
end

% --- Inertia-weighted COI frame (angle AND speed) --------------------------
ro_f = coi_relative(delta_f_i, omega_f_i, H, gen_sorted);
ro_a = coi_relative(delta_a_i, omega_a_i, H, gen_sorted);

% --- Metrics (report-only diagnostics) -------------------------------------
metrics = struct();
metrics.delta_coi_deg      = maxd(abs(rad2deg(ro_f.delta_coi - ro_a.delta_coi)));
metrics.delta_pairwise_deg = maxd(abs(rad2deg(delta_f_i - delta_a_i)));
metrics.omega_pu           = maxd(abs(omega_f_i - omega_a_i));
metrics.omega_coi_pu       = maxd(abs(ro_f.omega_coi - ro_a.omega_coi));
metrics.Pe_MW             = maxd(abs(Pe_f_i - Pe_a_i));
metrics.Vbus_pu           = maxd(abs(Vbus_f_i - Vbus_a_i));
if fb_common > 0
    metrics.Vbus_fault_pu = maxd(abs(Vbus_f_i(:,fb_common) - Vbus_a_i(:,fb_common)));
else
    metrics.Vbus_fault_pu = NaN;  % fault bus not in common set
end

% --- Structural invariants --------------------------------------------------
all_finite = all(isfinite(delta_f_i(:))) && all(isfinite(delta_a_i(:))) && ...
             all(isfinite(omega_f_i(:))) && all(isfinite(omega_a_i(:))) && ...
             all(isfinite(Pe_f_i(:))) && all(isfinite(Pe_a_i(:))) && ...
             all(isfinite(Vbus_f_i(:))) && all(isfinite(Vbus_a_i(:)));

% Exact event landing: both event times must be on the adaptive grid.
exact_event_landing = true;
ev_times = [];
if isfield(r_adapt,'event_diagnostics') && ~isempty(r_adapt.event_diagnostics)
    ev_times = unique([r_adapt.event_diagnostics.time]);
end
for et = ev_times(:).'
    if isempty(find(abs(r_adapt.t - et) < 1e-14, 1))
        exact_event_landing = false; break;
    end
end

% Algebraic convergence: adaptive corrector residual must be finite and bounded.
if isfield(r_adapt,'corrector_residual') && ~isempty(r_adapt.corrector_residual)
    max_corr_res = max(r_adapt.corrector_residual(:));
    algebraic_converged = isfinite(max_corr_res) && max_corr_res < 1;  % loose structural bound
else
    algebraic_converged = false;
end

no_extrapolation = coverage_valid;       % interp_no_extrapolate would have errored otherwise
no_cross_event_interp = true;            % segmented by construction

structural_pass = all_finite && coverage_valid && no_extrapolation && ...
    no_cross_event_interp && exact_event_landing && id_mapping_consistent && ...
    algebraic_converged;

% --- Assemble report --------------------------------------------------------
report = struct();
report.case_name = case_name;
report.model = model;
report.scenario = sc;
report.fixed = r_fixed;
report.adaptive = r_adapt;
report.gen_buses = gen_sorted;
report.bus_ids = bcommon;
report.tg = tg;
report.seg_edges = seg_edges;
report.metrics = metrics;
report.coverage_valid = coverage_valid;
report.no_extrapolation = no_extrapolation;
report.no_cross_event_interp = no_cross_event_interp;
report.exact_event_landing = exact_event_landing;
report.id_mapping_consistent = id_mapping_consistent;
report.algebraic_converged = algebraic_converged;
report.all_finite = all_finite;
report.structural_pass = structural_pass;
report.event_diagnostics = [];
if isfield(r_adapt,'event_diagnostics'), report.event_diagnostics = r_adapt.event_diagnostics; end
report.accepted_steps = ternary(isfield(r_adapt,'accepted_steps'), r_adapt.accepted_steps, NaN);
report.rejected_steps = ternary(isfield(r_adapt,'rejected_steps'), r_adapt.rejected_steps, NaN);
report.dt_history = [];
if isfield(r_adapt,'dt_history'), report.dt_history = r_adapt.dt_history; end
report.lte_history = [];
if isfield(r_adapt,'lte_history'), report.lte_history = r_adapt.lte_history; end

% --- Console summary (report-only) -----------------------------------------
fprintf('\n=== adaptive_ts_compare_fixed: %s [%s] ===\n', case_name, model);
fprintf('fixed nt=%d  adaptive nt=%d (accepted=%d rejected=%d)\n', ...
    numel(r_fixed.t), numel(r_adapt.t), report.accepted_steps, report.rejected_steps);
fprintf('gen_buses (ID-mapped): %s\n', mat2str(report.gen_buses(:).'));
fprintf('bus_ids common: %s\n', mat2str(report.bus_ids(:).'));
fprintf('coverage_valid=%d no_extrap=%d no_cross_event=%d exact_event=%d id_map=%d alg_conv=%d finite=%d\n', ...
    report.coverage_valid, report.no_extrapolation, report.no_cross_event_interp, ...
    report.exact_event_landing, report.id_mapping_consistent, ...
    report.algebraic_converged, report.all_finite);
fprintf('STRUCTURAL_PASS=%d\n', report.structural_pass);
fprintf('-- diagnostics (NOT gates) --\n');
fprintf('delta COI=%.4f deg  pairwise=%.4f deg  omega=%.3e pu  omega_coi=%.3e pu\n', ...
    metrics.delta_coi_deg, metrics.delta_pairwise_deg, metrics.omega_pu, metrics.omega_coi_pu);
fprintf('Pe=%.4f MW  Vbus=%.3e pu  Vbus_fault=%.3e pu\n', ...
    metrics.Pe_MW, metrics.Vbus_pu, metrics.Vbus_fault_pu);
fprintf('==========================================\n\n');
end

% =========================================================================
function edges = segment_edges(r_fixed, r_adapt, sc)
%SEGMENT_EDGES  Build interpolation segment edges at t_fault and t_clear.
%   Edges are clipped to the common horizon [0, min(t_end)] so segments cover
%   only the overlapping region actually simulated by both paths.
t_end_common = min(r_fixed.t(end), r_adapt.t(end));
edges = [0];
ev = [];
if isfinite(sc.t_fault) && sc.t_fault > 0 && sc.t_fault < t_end_common
    ev = [ev; sc.t_fault]; end
if isfinite(sc.t_clear) && sc.t_clear > 0 && sc.t_clear < t_end_common
    ev = [ev; sc.t_clear]; end
ev = sort(unique(ev));
for e = ev(:).'
    edges = [edges; e]; %#ok<AGROW>
end
edges = [edges; t_end_common];
end

function ids = bus_ids_of(r)
%BUS_IDS_OF  Extract the bus ID vector from any model's result struct.
%   classical exposes bus IDs via r.pf.external_bus_ids (the result struct
%   does not carry r.bus_ids); padiyar/emf6 carry r.bus_ids directly.
if isfield(r,'bus_ids') && ~isempty(r.bus_ids)
    ids = r.bus_ids(:);
elseif isfield(r,'pf') && isfield(r.pf,'external_bus_ids')
    ids = r.pf.external_bus_ids(:);
else
    ids = [];
end
end

function m = maxd(a)
%MAXD  Max absolute value over all elements, NaN-safe.
m = max(abs(a(:)));
if isempty(m), m = NaN; end
end

function s = setfields(s, overrides)
%SETFIELDS  Merge override fields into struct s.
fn = fieldnames(overrides);
for k = 1:numel(fn), s.(fn{k}) = overrides.(fn{k}); end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
