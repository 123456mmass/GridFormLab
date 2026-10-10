function dec = ai_fallback_selector(feat, opts, why)
%AI_FALLBACK_SELECTOR  Deterministic mode selection when the model is unavailable.
%
%   DEC = ai.ai_fallback_selector(FEAT, OPTS, WHY)
%
%   Applies the same four rules the system prompt states, in code:
%     1  always name a primary -- an empty answer is never correct here
%     2  the primary is the weakest bus by window-median ESCR
%     3  a second bus ONLY when the voltage collapse is severe, i.e. the worst
%        bus voltage in the window is at or below OPTS.vmin_severe_pu
%     4  never a bus that is already forming
%
%   WHY HAVE THIS AT ALL. Not only as a network-failure path. A deterministic
%   rule that answers from the same features the model is shown is what makes
%   the model's verdict auditable: when the two disagree, the disagreement is
%   about judgement on identical inputs, not about which numbers were read. It
%   is also the only path that can run without a key, which is what lets the
%   contract tests cover the whole pipeline offline.
%
%   DEC.source is always "FALLBACK_RULE". WHY, when given, is folded into
%   primary_reason so the record shows what the fallback was standing in for.
%
%   See also ai.ai_parse_decision, ai.ai_extract_features.

arguments
    feat struct
    opts struct = ai.ai_supervisor_defaults()
    why (1,1) string = ""
end

dec = struct('action', "SWITCH_MODE", 'target_buses', [], ...
    'target_mode', "GFM", 'confidence', NaN, 'primary_reason', "", ...
    'warnings', strings(1,0), 'source', "FALLBACK_RULE");

% Candidates in ESCR order, already-forming excluded. A bus whose ESCR is NaN
% sorts last: an unknown strength must not be presented as the weakest bus.
forming = false(1, numel(feat.buses));
forming(feat.gfm_indices) = true;
order = feat.rank_by_escr;
order = order(~forming(order));
if isempty(order)
    dec.action = "NO_ACTION";
    dec.confidence = 1.0;
    dec.primary_reason = "Every IBR bus is already forming; no selection remains.";
    return;
end

primary = order(1);
targets = primary;

% Rule 3: the second bus is spent only on a severe collapse, never on a
% marginal one. Spending it is what the ceiling exists to ration.
severe = isfinite(feat.V_min_pu) && feat.V_min_pu <= opts.vmin_severe_pu;
if severe && numel(order) >= 2 && opts.max_gfm_buses >= 2
    targets = [primary, order(2)];
end

dec.target_buses = [feat.buses(targets).bus_id];

% Confidence is a fixed expression of how much of the evidence existed, NOT a
% probability. ESCR is the index rule 2 ranks on, so its absence is the one
% thing that makes this answer materially weaker.
if feat.escr_source == "unavailable"
    dec.confidence = 0.30;
elseif severe
    dec.confidence = 0.60;
else
    dec.confidence = 0.50;
end

parts = strings(1, numel(targets));
for k = 1:numel(targets)
    b = feat.buses(targets(k));
    parts(k) = sprintf('bus %d (ESCR %.3f, V %.3f pu)', b.bus_id, ...
        b.escr_median, b.V_median_pu);
end
% The window MINIMUM is stated alongside the median in every reason, because
% the two answer different questions and can differ by more than a per-unit.
% In the delivered SG-trip chronology the weakest bus sits at a median of
% 1.086 pu while the system minimum in the same window is 0.055 pu; a reason
% quoting only the median would describe that window as uneventful.
reason = "Rule-based selection: weakest bus by window-median ESCR is " + ...
    parts(1) + ". Window minimum bus voltage was " + ...
    sprintf('%.3f pu', feat.V_min_pu) + ".";
if numel(targets) == 2
    reason = reason + " A second bus, " + parts(2) + ...
        ", was added because that minimum is at or below the severe " + ...
        sprintf('threshold %.3f pu', opts.vmin_severe_pu) + ".";
end
if feat.escr_source == "unavailable"
    reason = reason + " ESCR was unavailable for this run, so the ranking " + ...
        "rested on the voltage evidence alone.";
end
if strlength(why) > 0
    reason = reason + " [fallback for: " + why + "]";
end
dec.primary_reason = reason;

if feat.escr_source == "unavailable"
    dec.warnings(end+1) = "ESCR unavailable; primary chosen on voltage evidence only";
end
end
