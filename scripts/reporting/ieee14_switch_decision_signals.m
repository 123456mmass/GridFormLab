function d = ieee14_switch_decision_signals(r,opts)
%IEEE14_SWITCH_DECISION_SIGNALS  Switching-decision signal bundle for one run.
%
%   d = ieee14_switch_decision_signals(r)
%
% Assembles everything the decision figure plots, and FAILS CLOSED when the run
% did not publish it. The reference-AGSI overlay is opt-in and defaults OFF
% (ts_simulate_ibr_hybrid.m:1473), so a result produced without
% 'agsi_reference',true carries no sub-index at all; and the admittance log the
% overlay needs for J_SCR exists only under the same flag, so the terms cannot be
% recovered afterwards -- r.Y_log holds topology LABELS, not matrices
% (ts_simulate_ibr_hybrid.m:1240). Refusing here, with a named identifier, is the
% only honest option: a decision page with a silently blank panel is worse than
% no page.
%
% Decision contract, carried through to the figure so the reader cannot mistake
% it: the supervisor consumes S, J_V and J_f ONLY. J_R, J_P, J_lock and J_SCR are
% reference-only, entered no gate, and are classified ASSUMED_DIAGNOSTIC
% (agsi_reference_terms.m:11-16). No aggregate index is formed.
%
% S is reconstructed from the overlay's own J_V and J_f, which
% agsi_reference_terms documents as the trigger pair, using the same expression
% the engine evaluates at ts_simulate_ibr_hybrid.m:2973. The reconstruction is
% GATED on the overlay's centre-of-inertia frequency agreeing with the published
% one, because three independent COI computations exist in the kernel and this
% figure must not quietly pick whichever looks better.
%
% Classification: ASSUMED_DIAGNOSTIC presentation bundle. Nothing computed here
% feeds a solver, selector, controller or acceptance decision.

arguments
    r struct
    opts.coi_tol (1,1) double = 1e-9
    opts.gamma_on (1,1) double = 0.65
    opts.gamma_off (1,1) double = 0.35
end

TERMS = {'J_V','J_f','J_R','J_P','J_lock','J_SCR'};
SYSTEM_TERMS = {'J_f','J_R'};   % identical across devices by construction

% --- fail closed on a run that never published the overlay ----------------
if ~isfield(r,'agsi_reference')
    error('ieee14_switch_decision_signals:overlayAbsent', ...
        ['This result carries no r.agsi_reference. The reference-AGSI overlay ' ...
         'is opt-in and defaults false; re-run with ''agsi_reference'',true. ' ...
         'It cannot be recovered by post-processing because the admittance log ' ...
         'it needs is built only under the same option.']);
end
A = r.agsi_reference;
if ~isstruct(A) || ~isfield(A,'status')
    error('ieee14_switch_decision_signals:overlayMalformed', ...
        'r.agsi_reference is present but carries no status field.');
end
status = char(string(A.status));
if ~strcmp(status,'OK')
    error('ieee14_switch_decision_signals:overlayNotOk', ...
        ['r.agsi_reference.status is "%s", not "OK". A decision page with a ' ...
         'blank sub-index panel would misrepresent the run.'],status);
end
for k = 1:numel(TERMS)
    if ~isfield(A,'terms') || ~isfield(A.terms,TERMS{k})
        error('ieee14_switch_decision_signals:overlayIncomplete', ...
            'r.agsi_reference.terms lacks %s.',TERMS{k});
    end
end

nt = numel(A.t);
if isfield(r,'t') && numel(r.t) ~= nt
    error('ieee14_switch_decision_signals:sampleCountMismatch', ...
        'Overlay has %d samples but the trajectory has %d.',nt,numel(r.t));
end

% --- COI cross-check gate --------------------------------------------------
% Flatten BOTH series before comparing. The overlay publishes a column and
% add_diagnostics publishes a row; logical indexing preserves each source's own
% orientation, so indexing them unflattened implicit-expands into a matrix and
% the residual silently becomes a vector.
coi_ov = A.f_coi_Hz(:);
coi_pub = NaN(nt,1);
if isfield(r,'coi_frequency_Hz'), coi_pub = r.coi_frequency_Hz(:); end
if numel(coi_pub) ~= nt
    error('ieee14_switch_decision_signals:coiLengthMismatch', ...
        'Published COI has %d samples but the overlay has %d.',numel(coi_pub),nt);
end
both = isfinite(coi_ov) & isfinite(coi_pub);
coi_resid = 0;
if any(both)
    coi_resid = max(abs(coi_ov(both)-coi_pub(both)));
end
if coi_resid > opts.coi_tol
    error('ieee14_switch_decision_signals:coiDisagreement', ...
        ['The overlay COI and the published COI differ by %.3e (> %.3e). The ' ...
         'severity reconstruction is not trustworthy until that is explained.'], ...
        coi_resid,opts.coi_tol);
end

% --- device mapping: overlay columns -> result rows ------------------------
ibr_ids = cellstr(string(A.device_ids));
m = numel(ibr_ids);
all_ids = {};
if isfield(r,'device_ids'), all_ids = cellstr(string(r.device_ids)); end
didx = NaN(1,m);
for q = 1:m
    j = find(strcmp(all_ids,ibr_ids{q}),1);
    if isempty(j)
        error('ieee14_switch_decision_signals:deviceMappingFailed', ...
            'Overlay device "%s" is not in r.device_ids.',ibr_ids{q});
    end
    didx(q) = j;
end

% --- severity, exactly as the engine forms it -----------------------------
JV = A.terms.J_V; Jf = A.terms.J_f;
S = min(1,max(0,0.5*JV + 0.5*Jf));

% --- mode and reference ownership, per accepted sample --------------------
mode_gfm = false(nt,m);
if isfield(r,'device_modes_history') && ~isempty(r.device_modes_history)
    H = r.device_modes_history;
    for q = 1:m
        mode_gfm(:,q) = strcmpi(H(didx(q),1:nt).','gfm');
    end
end
[ref_code,ref_owner_count] = reference_owner_trace(r,nt,didx);

% --- bundle ---------------------------------------------------------------
d = struct();
d.t = A.t(:);
d.device_ids = ibr_ids;
d.device_bus_ids = bus_ids_for(r,didx);
d.device_result_rows = didx;
d.S = S;
d.terms = A.terms;
d.term_names = TERMS;
d.system_terms = SYSTEM_TERMS;
d.online = A.online;
d.mode_raw = A.mode;
d.mode_gfm = mode_gfm;
d.ref_code = ref_code;
d.ref_owner_count = ref_owner_count;
d.f_coi_Hz = A.f_coi_Hz(:);
d.rocof_Hz_s = A.rocof_Hz_s(:);
d.scr = A.scr;
d.in_band = A.in_band;
d.bases = A.bases;
% severity_gamma_on/off are top-level run options and are NOT republished in
% result.metadata, so they cannot be recovered from the result. The caller passes
% them from the recorded option signature; the defaults here are the frozen
% contract values (ts_simulate_ibr_hybrid.m:1450).
d.gamma_on  = opts.gamma_on;
d.gamma_off = opts.gamma_off;
d.gamma_source = 'caller (run option signature); default = frozen contract 0.65/0.35';
d.diagnostics = struct('coi_residual_Hz',coi_resid,'coi_tol_Hz',opts.coi_tol, ...
    'n_samples',nt,'n_devices',m, ...
    'multi_island_samples',sum(ref_owner_count > 1), ...
    'J_SCR_finite_per_device',sum(isfinite(A.terms.J_SCR),1), ...
    'J_R_finite_samples',sum(isfinite(A.terms.J_R(:,1))));
d.decision_contract = struct( ...
    'consumed_by_supervisor',{{'S','J_V','J_f'}}, ...
    'reference_only',{{'J_R','J_P','J_lock','J_SCR'}}, ...
    'aggregate_index','NOT_FORMED_BY_DESIGN', ...
    'classification','ASSUMED_DIAGNOSTIC', ...
    'source','stability.agsi_reference_terms + ts_simulate_ibr_hybrid.m:2973');

if d.diagnostics.multi_island_samples > 0
    warning('ieee14_switch_decision_signals:multiIslandOwnership', ...
        ['%d sample(s) report more than one reference owner. The trace keeps ' ...
         'the first; the count is published in d.ref_owner_count.'], ...
        d.diagnostics.multi_island_samples);
end
end

% ==========================================================================
function [ref_code,n_owner] = reference_owner_trace(r,nt,didx)
%REFERENCE_OWNER_TRACE  Per-sample island angle reference owner.
%   Read from the accepted hybrid-state history, NOT inferred from "the first
%   GFM": mode and reference ownership are different contracts once several GFM
%   units are online. r.reference_owner_indices is the FINAL snapshot only, so it
%   cannot serve here.
%   Codes: 0 = SG (device row 1), 1..m = the IBR at didx(j), -1 = no owner.
ref_code = -ones(nt,1);
n_owner  = zeros(nt,1);
sgonline = true(nt,1);
if isfield(r,'device_online_history') && ~isempty(r.device_online_history)
    sgonline = logical(r.device_online_history(1,1:nt)).';
end
has_ctx = isfield(r,'event_context_history');
for k = 1:nt
    hs = struct();
    if has_ctx && numel(r.event_context_history) >= k && ...
            isstruct(r.event_context_history{k}) && ...
            isfield(r.event_context_history{k},'hybrid_state')
        hs = r.event_context_history{k}.hybrid_state;
    end
    if isfield(hs,'reference_owner_indices') && ~isempty(hs.reference_owner_indices)
        n_owner(k) = numel(hs.reference_owner_indices);
        owner = hs.reference_owner_indices(1);
        if owner == 1
            ref_code(k) = 0;
        else
            j = find(didx == owner,1);
            if ~isempty(j), ref_code(k) = j; end
        end
    elseif sgonline(k)
        ref_code(k) = 0;
        n_owner(k)  = 1;
    end
end
end

% ==========================================================================
function b = bus_ids_for(r,didx)
b = NaN(1,numel(didx));
if isfield(r,'device_bus_ids') && ~isempty(r.device_bus_ids)
    ids = r.device_bus_ids;
    ok = didx >= 1 & didx <= numel(ids);
    b(ok) = ids(didx(ok));
end
end

function B = collect_bases(A) %#ok<DEFNU>
% Retained for callers that pass an older overlay struct without .bases.
B = struct();
for f = {'dV_base','df_base_Hz','rocof_base_Hz_s','dP_base_pu', ...
        'scr_floor','vq_base_pu','bases'}
    if isfield(A,f{1}), B.(f{1}) = A.(f{1}); end
end
end

function v = num_or(s,name,default) %#ok<DEFNU>
v = default;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)) && ...
        isnumeric(s.(name)) && isscalar(s.(name))
    v = double(s.(name));
end
end
