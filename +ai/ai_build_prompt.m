function [system_prompt, user_payload, payload] = ai_build_prompt(feat, opts, context)
%AI_BUILD_PROMPT  The supervisor's system prompt and the per-event user payload.
%
%   [SYSTEM_PROMPT, USER_PAYLOAD, PAYLOAD] = ai.ai_build_prompt(FEAT, OPTS, CONTEXT)
%
%   CONTEXT carries what is true of the decision rather than of the grid:
%     scenario_id, trigger_time_s, trigger_reason
%
%   Two properties of this prompt are load-bearing and neither is cosmetic:
%
%   1. The candidate list is CLOSED. The model may only name a bus that appears
%      in payload.candidates. A model free to name any bus in the network can
%      name one with no converter on it, and the reply would be unusable at
%      exactly the moment it is needed.
%
%   2. Missing data must not be filled in. ESCR is NaN for a run whose cache
%      predates result.agsi_reference; an unavailable index is passed through
%      as null and the prompt tells the model that a lower confidence is the
%      correct answer, not an invented number. A fabricated ESCR is worse than
%      no ESCR, because it is indistinguishable from a measured one downstream.
%
%   See also ai.ai_call_llm, ai.ai_parse_decision.

arguments
    feat struct
    opts struct = ai.ai_supervisor_defaults()
    context struct = struct()
end

n_cand = numel(feat.buses);
forming = strings(1, numel(feat.gfm_indices));
for k = 1:numel(feat.gfm_indices)
    forming(k) = string(feat.buses(feat.gfm_indices(k)).device_id);
end

system_prompt = strjoin([
    "You are the supervisory mode-selection evaluator for a high-IBR power"
    "system. A synchronous machine that served as the grid reference has been"
    "lost or is at risk, and the island is now dominated by grid-following"
    "(GFL) inverters with little or no inertia. Your decision is which"
    "inverter(s), if any, must be switched to grid-forming (GFM) to arrest the"
    "frequency excursion and hold voltage, without provoking inter-inverter"
    "power hunting."
    ""
    "PHYSICS YOU MUST USE"
    "- RoCoF is the rate of change of the centre-of-inertia frequency, in Hz/s."
    "  A large negative value means inertia has been lost and the reference is"
    "  gone; that is the emergency this controller exists for."
    "- ESCR is the local effective short-circuit ratio at a bus:"
    "  ESCR = |V|^2 / (|Z_th| * S_rated). A LOWER ESCR means a WEAKER bus, i.e."
    "  the bus whose GFL inverter is closest to losing phase lock and where a"
    "  GFM anchor buys the most. Lower is the target, not higher."
    "- V_drop_pu is how far the bus voltage has fallen from its pre-disturbance"
    "  value. The deepest drop marks where voltage support is most needed."
    ""
    "HARD RULES, IN ORDER OF PRECEDENCE"
    "1. CRITICAL TRIGGER. If RoCoF has collapsed (|RoCoF| at or beyond the"
    "   stated threshold, or the frequency trace shows a sharp dive), treat the"
    "   island as having lost its reference and select exactly ONE bus as the"
    "   primary GFM immediately. Do not answer with an empty list."
    "2. SPATIAL / STRENGTH SELECTION. The primary must be the candidate with the"
    "   lowest ESCR, or the one in the zone of deepest voltage drop -- the local"
    "   anchor. Where the two disagree, prefer the weaker bus (lower ESCR) and"
    "   say in primary_reason that the criteria conflicted."
    "3. DAMPING AND STABILITY CONSTRAINT. Never select more than the stated"
    "   maximum number of buses. Two is the absolute ceiling; three or more"
    "   forming converters on this network produce circulating current and power"
    "   oscillations. A second bus is justified ONLY when the voltage collapse"
    "   is severe enough that one anchor cannot hold the zone, and you must say"
    "   so explicitly."
    "4. NEVER name a bus that is already forming, and never name a bus outside"
    "   the candidate list. Only the listed candidates exist."
    ""
    "DATA HONESTY"
    "A null index means the value was not available for this run. Do not"
    "estimate it, do not infer it from another bus, and do not present a"
    "substitute. Choose using the indices you do have and lower your confidence"
    "accordingly. If every index you would need is null, still name a primary"
    "from the candidate list and set confidence below 0.5, with a"
    "primary_reason that states the data was unavailable."
    ""
    "OUTPUT"
    "Reply with a single JSON object and nothing else. No prose, no markdown"
    "fence, no commentary before or after. The exact schema is:"
    '{"action": "SWITCH_MODE", "target_buses": [<bus numbers>],'
    ' "target_mode": "GFM", "confidence": <0..1>,'
    ' "primary_reason": "<one or two sentences citing the indices you used>"}'
    "target_buses must be a non-empty array of bus NUMBERS drawn from the"
    "candidates, ordered with the primary first, and no longer than the stated"
    "maximum."], newline);

% --- payload --------------------------------------------------------------
payload = struct();
payload.task = "select_grid_forming_buses";
if isfield(context,'scenario_id')
    payload.scenario_id = string(context.scenario_id);
end
payload.trigger = struct( ...
    'time_s', value_or_null(context, 'trigger_time_s'), ...
    'reason', string(value_or_null(context, 'trigger_reason')), ...
    'rocof_threshold_Hz_s', opts.rocof_threshold_Hz_s, ...
    'vmin_threshold_pu', opts.vmin_threshold_pu);
payload.window = struct( ...
    't_start_s', feat.t_start_s, 't_end_s', feat.t_end_s, ...
    'n_samples', feat.n_samples);
payload.system_state = struct( ...
    'f0_Hz', feat.f0_Hz, ...
    'f_end_Hz', feat.f_end_Hz, ...
    'f_nadir_Hz', feat.f_nadir_Hz, ...
    'rocof_peak_Hz_s', feat.rocof_peak_Hz_s, ...
    'rocof_end_Hz_s', feat.rocof_end_Hz_s, ...
    'rocof_source', strjoin(feat.rocof_source, "+"), ...
    'V_min_pu', feat.V_min_pu, ...
    't_vmin_s', feat.t_vmin_s);

cand = repmat(struct('bus', NaN, 'device_id', "", 'escr', NaN, ...
    'escr_min', NaN, 'escr_max', NaN, 'V_pu', NaN, 'V_drop_pu', NaN, ...
    'already_forming', false), 1, n_cand);
for k = 1:n_cand
    b = feat.buses(k);
    cand(k).bus = b.bus_id;
    cand(k).device_id = b.device_id;
    cand(k).escr = b.escr_median;
    cand(k).escr_min = b.escr_min;
    cand(k).escr_max = b.escr_max;
    cand(k).V_pu = b.V_median_pu;
    cand(k).V_drop_pu = b.V_drop_pu;
    cand(k).already_forming = any(feat.gfm_indices == k);
end
payload.candidates = cand;
payload.constraints = struct( ...
    'max_gfm_buses', opts.max_gfm_buses, ...
    'already_forming', forming, ...
    'already_forming_buses', feat.buses(feat.gfm_indices));

payload.data_quality = struct( ...
    'escr_source', string(feat.escr_source), ...
    'notes', feat.notes);
payload.required_schema = struct( ...
    'action', "SWITCH_MODE", 'target_buses', "array of bus numbers", ...
    'target_mode', "GFM", 'confidence', "number in [0,1]", ...
    'primary_reason', "string");

user_payload = jsonencode(payload);
end

% =========================================================================
function v = value_or_null(s, f)
%VALUE_OR_NULL  Field value when present and finite, else [] (JSON null).
v = [];
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
end
end
