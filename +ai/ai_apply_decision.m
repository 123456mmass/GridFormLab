function [mode_table, entry] = ai_apply_decision(mode_table, dec, t_now, opts)
%AI_APPLY_DECISION  Apply a verdict to the supervisor's own mode table.
%
%   [MODE_TABLE, ENTRY] = ai.ai_apply_decision(MODE_TABLE, DEC, T_NOW, OPTS)
%
%   THIS WRITES TO A SHADOW TABLE, NOT TO A CONVERTER. The mode table is the
%   supervisor's own record of what it has committed; it is deliberately not
%   wired into stability.ts_simulate_ibr_hybrid, whose mode vector is owned by
%   its event schedule and its selector. Applying here changes what the
%   supervisor believes it has done, which is what makes the loop's subsequent
%   decisions meaningful, and nothing else.
%
%   MODE_TABLE fields:
%     device_ids  1-by-nd cellstr
%     ibr_buses   1-by-m bus numbers, aligned with the IBR devices
%     modes       m-by-1 cellstr, the current committed mode per IBR
%     history     struct array of every applied entry (may start empty)
%
%   ENTRY fields: t_s, buses, from_modes, to_mode, source, confidence, reason,
%   applied. A refused apply still returns an entry, with applied = false and
%   the reason naming the refusal, so a refusal is a record rather than a
%   silent no-op.
%
%   This is the last place the two-bus ceiling and the already-forming rule are
%   checked. They were checked when the reply was parsed; they are checked again
%   here because this is the function that would carry out the harm, and a
%   cheap second check at the point of action is worth more than the assumption
%   that every caller went through the parser.
%
%   See also ai.ai_parse_decision, ai.ai_fallback_selector.

arguments
    mode_table struct
    dec struct
    t_now (1,1) double {mustBeReal}
    opts struct = ai.ai_supervisor_defaults()
end

entry = struct('t_s', t_now, 'buses', [], 'from_modes', {{}}, ...
    'to_mode', "GFM", 'source', string(dec.source), ...
    'confidence', dec.confidence, 'reason', string(dec.primary_reason), ...
    'applied', false);

if ~strcmpi(string(dec.action), "SWITCH_MODE")
    entry.reason = "No apply: the decision action is " + string(dec.action) + ".";
    return;
end

targets = dec.target_buses(:)';
if isempty(targets)
    entry.reason = "No apply: the decision named no buses.";
    return;
end
if numel(targets) > opts.max_gfm_buses
    entry.reason = sprintf( ...
        'Refused: %d buses exceeds the ceiling of %d.', ...
        numel(targets), opts.max_gfm_buses);
    return;
end

rows = nan(1, numel(targets));
for k = 1:numel(targets)
    r = find(mode_table.ibr_buses == targets(k), 1);
    if isempty(r)
        entry.reason = sprintf( ...
            'Refused: bus %d carries no switchable IBR in this table.', targets(k));
        return;
    end
    if strcmpi(mode_table.modes{r}, "gfm")
        entry.reason = sprintf('Refused: bus %d is already forming.', targets(k));
        return;
    end
    rows(k) = r;
end

from_modes = mode_table.modes(rows);
for k = 1:numel(rows)
    mode_table.modes{rows(k)} = 'gfm';
end

entry.buses = targets;
entry.from_modes = from_modes;
entry.applied = true;
if ~isfield(mode_table, 'history') || isempty(mode_table.history)
    mode_table.history = entry;
else
    mode_table.history(end+1) = entry;
end
end
