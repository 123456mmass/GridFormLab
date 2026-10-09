function screen = ibr_candidate_screen(spec, resources, cheap, opt)
%IBR_CANDIDATE_SCREEN  Cheap, SOUND necessary-condition screen for one GFM subset.
%
%   SCREEN = stability.ibr_candidate_screen(SPEC, RESOURCES, CHEAP, OPT) applies
%   only CHEAP, PROVABLY-NECESSARY rejection conditions. It can only REJECT
%   ('INFEASIBLE') or DECLINE ('UNKNOWN'); it can NEVER certify a candidate.
%
%   THREE-VALUED CONTRACT
%     'INFEASIBLE'  a PROVEN necessary condition is violated and the full
%                   evaluator would reject this subset -> skipping is EXACT.
%     'UNKNOWN'     cheap evidence is insufficient -> the subset MUST be sent
%                   to the full evaluator.
%
%   HARD RULES
%     * LOW-SCR IS NOT A HARD CONSTRAINT UNLESS THE ORIGINATING CONTRACT SAYS IT
%       APPLIES. The WECC SCR>3 threshold applies only when
%       per_resource.threshold_applicable == true (scr_profile ==
%       'wecc_regca_strong_grid'). For the project full-state families
%       (eecon49_dual) and the source-aware path, threshold_applicable is false
%       and a measured low SCR is a DIAGNOSTIC only: verdict stays 'UNKNOWN',
%       never 'INFEASIBLE'. We never borrow SCR>3 for a family it was not
%       written for.
%     * NO-SOURCE / ISLAND INVALIDITY IS DISTINCT FROM A LOW-SCR DIAGNOSTIC.
%       A singular/islanded Y ('topology') or an explicit WHOLE-ISLAND
%       no-voltage-source declaration ('source', cheap.no_source_island) are
%       hard invalidities with their own stages/ids. A per-resource
%       'source_available' flag is NOT used as a hard constraint (a GFM forms
%       its own voltage). A merely low SCR is not.
%     * NO SURROGATE RESERVE CERTIFICATE. An MW reserve is never inferred from
%       a DC-power-flow discriminant or an apparent-power margin; those fields
%       are recorded and ignored, and reserve is declared as required evidence.
%
%   CHEAP struct:
%     .is_singular          logical (Ybus singular/islanded)
%     .topology_ok          logical (false == inadmissible topology)
%     .Y_rcond              scalar (diagnostic)
%     .scr_available        logical
%     .source_aware         logical (source-aware metrics in use)
%     .scr_per_resource     struct array with .resource_index, .online, .is_gfl,
%                           .eligible_for_scr, .threshold_applicable, .pass,
%                           .source_available, .status, .reason, .failure_id
%     .sg_online            logical (context; default from OPT)
%     Tolerated-and-ignored surrogates: .dc_discriminant, .apparent_margin,
%     .reserve_MW, .margin.
%
%   OPT: .sg_online, .reference_resource_index (pinned IBR reference, SG_OFF).
%
%   SCREEN: .verdict, .stage, .necessary, .failure_id, .reason, .certifies
%     (ALWAYS false), .required_evidence, .ignored_surrogates, .diagnostics.
%
%   Classification: logical contract PROJECT_DERIVED. No external solver.

arguments
    spec struct
    resources struct
    cheap struct = struct()
    opt struct = struct()
end

screen = blank_screen();

screen.required_evidence = {'equilibrium_converged', 'full_kcl_residual', ...
    'sssa_gate', 'current_pq_limits', 'dc_reserve_mw', 'synchronism_margin'};

% --- surrogate guard: name what we refuse to use ---------------------
surrogates = {'dc_discriminant', 'apparent_margin', 'reserve_MW', 'margin'};
ignored = {};
for k = 1:numel(surrogates)
    if isfield(cheap, surrogates{k}) && ~isempty(cheap.(surrogates{k}))
        ignored{end+1} = surrogates{k}; %#ok<AGROW>
    end
end
screen.ignored_surrogates = ignored;

sg_online = false;
if isfield(opt, 'sg_online') && ~isempty(opt.sg_online)
    sg_online = logical(opt.sg_online);
elseif isfield(cheap, 'sg_online') && ~isempty(cheap.sg_online)
    sg_online = logical(cheap.sg_online);
end

nr = numel(resources);
eligible = eligible_mask(resources);

% --- stage 'malformed' ------------------------------------------------
sel = reshape(spec.selected_gfm_indices, 1, []);
n_req = spec.n_gfm_required;
if ~isnumeric(sel) || any(~isfinite(sel)) || any(sel ~= fix(sel)) || ...
        any(sel < 1) || any(sel > nr) || numel(unique(sel)) ~= numel(sel)
    screen = set_infeasible(screen, 'malformed', ...
        'stability:ibr_candidate_screen:malformedSubset', ...
        'selected_gfm_indices must be unique valid resource indices.');
    return;
end
if ~isnumeric(n_req) || ~isscalar(n_req) || n_req ~= fix(n_req) || n_req < 0 || ...
        n_req ~= numel(sel)
    screen = set_infeasible(screen, 'malformed', ...
        'stability:ibr_candidate_screen:malformedCount', ...
        'n_gfm_required must equal numel(selected_gfm_indices).');
    return;
end
if any(~eligible(sel))
    screen = set_infeasible(screen, 'malformed', ...
        'stability:ibr_candidate_screen:ineligibleSelected', ...
        'A selected index is not an eligible switchable GFM-capable IBR.');
    return;
end

% --- stage 'reference' (SG_OFF only) ---------------------------------
if ~sg_online && isfield(opt, 'reference_resource_index') && ...
        ~isempty(opt.reference_resource_index) && ...
        isscalar(opt.reference_resource_index) && ...
        ~ismember(opt.reference_resource_index, sel)
    screen = set_infeasible(screen, 'reference', ...
        'stability:ibr_candidate_screen:referenceNotInSubset', ...
        'The pinned IBR angle reference is absent from the subset.');
    return;
end

% --- stage 'topology' (hard, distinct from low SCR) ------------------
if (isfield(cheap, 'is_singular') && logical(cheap.is_singular)) || ...
        (isfield(cheap, 'topology_ok') && ~logical(cheap.topology_ok))
    screen = set_infeasible(screen, 'topology', ...
        'stability:ibr_candidate_screen:singularY', ...
        'Network Ybus is singular/islanded; no subset can form voltage.');
    return;
end

% --- stage 'source': WHOLE-island no-source invalidity ----------------
% Only an EXPLICIT whole-island no-source declaration is a hard rejection.
% A per-resource 'source_available' flag is NOT a hard constraint for a GFM
% subset: a GFM converter forms voltage itself, and the source-aware metric is
% built around synchronous sources, so a GFM PCC legitimately shows
% source_available == false. Rejecting on that would be a FALSE constraint
% (it would drop every valid GFM selection). Keep it diagnostic only.
if isfield(cheap, 'no_source_island') && logical(cheap.no_source_island)
    screen = set_infeasible(screen, 'source', ...
        'stability:ibr_candidate_screen:noSourceIsland', ...
        'The energized island has no voltage-forming source.');
    return;
end

% --- stage 'scr' (hard ONLY when threshold_applicable) ---------------
scr_available = isfield(cheap, 'scr_available') && logical(cheap.scr_available);
if scr_available
    diags = {};
    for k = 1:nr
        r = resources(k);
        if ~isfield(r, 'initial_online') || ~logical(r.initial_online)
            continue;
        end
        rt = 'ibr';
        if isfield(r, 'resource_type'), rt = lower(char(r.resource_type)); end
        if ~strcmp(rt, 'ibr'), continue; end
        if ismember(k, sel), continue; end   % selected -> GFM, SCR gate N/A
        pr = find_scr_entry(cheap, k);
        if isempty(pr)
            % Evidence gap: cannot decide cheaply. Do NOT reject.
            screen.required_evidence{end+1} = sprintf('scr_metrics_index_%d', k);
            diags{end+1} = sprintf('index %d: no SCR entry', k); %#ok<AGROW>
            continue;
        end
        applicable = isfield(pr, 'threshold_applicable') && ...
            logical(pr.threshold_applicable);
        if applicable
            if isfield(pr, 'pass') && ~isempty(pr.pass) && ~logical(pr.pass)
                fid = 'stability:ibr_candidate_screen:scrWeak';
                if isfield(pr, 'failure_id') && ~isempty(pr.failure_id)
                    fid = pr.failure_id;
                end
                reason = 'GFL remainder fails the applicable SCR gate.';
                if isfield(pr, 'reason') && ~isempty(pr.reason)
                    reason = char(pr.reason);
                end
                screen = set_infeasible(screen, 'scr', fid, reason);
                return;
            end
        else
            % Threshold not applicable for this family/model: a low SCR is a
            % diagnostic, NOT a hard constraint.
            diags{end+1} = sprintf('index %d: SCR diagnostic only (threshold not applicable)', k); %#ok<AGROW>
        end
    end
    screen.diagnostics = diags;
else
    screen.required_evidence{end+1} = 'scr_metrics';
end

% --- nothing cheap proved infeasible -> UNKNOWN ---------------------
screen.verdict = 'UNKNOWN';
screen.stage = '';
screen.necessary = false;
screen.failure_id = '';
screen.reason = 'No cheap necessary condition violated; full evaluation required.';
end

% =====================================================================
function screen = blank_screen()
screen = struct('verdict', 'UNKNOWN', 'stage', '', 'necessary', false, ...
    'failure_id', '', 'reason', '', 'certifies', false, ...
    'required_evidence', {{}}, 'ignored_surrogates', {{}}, 'diagnostics', {{}});
end

function screen = set_infeasible(screen, stage, fid, reason)
screen.verdict = 'INFEASIBLE';
screen.stage = stage;
screen.necessary = true;
screen.failure_id = fid;
screen.reason = reason;
screen.certifies = false;
end

function pr = find_scr_entry(cheap, idx)
pr = [];
if ~isfield(cheap, 'scr_per_resource') || isempty(cheap.scr_per_resource)
    return;
end
for p = 1:numel(cheap.scr_per_resource)
    if isfield(cheap.scr_per_resource(p), 'resource_index') && ...
            cheap.scr_per_resource(p).resource_index == idx
        pr = cheap.scr_per_resource(p);
        return;
    end
end
end

function eligible = eligible_mask(resources)
nr = numel(resources);
eligible = false(1, nr);
for k = 1:nr
    r = resources(k);
    if ~isfield(r, 'initial_online') || ~logical(r.initial_online), continue; end
    rt = 'ibr';
    if isfield(r, 'resource_type'), rt = lower(char(r.resource_type)); end
    if ~strcmp(rt, 'ibr'), continue; end
    if ~isfield(r, 'can_switch_mode') || ~logical(r.can_switch_mode), continue; end
    supported = supported_modes_of(r);
    if ~(any(strcmpi(supported, 'gfl')) && any(strcmpi(supported, 'gfm')))
        continue;
    end
    if isfield(r, 'voltage_forming_modes')
        vfc = cellstr(string(r.voltage_forming_modes));
        if ~any(strcmpi(vfc, 'gfm')), continue; end
    else
        continue;
    end
    eligible(k) = true;
end
end

function modes = supported_modes_of(r)
modes = {};
if isfield(r, 'capabilities') && isstruct(r.capabilities) && ...
        isfield(r.capabilities, 'supported_modes')
    modes = cellstr(string(r.capabilities.supported_modes));
elseif isfield(r, 'supported_modes')
    modes = cellstr(string(r.supported_modes));
end
end
