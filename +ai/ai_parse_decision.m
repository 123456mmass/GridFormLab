function [dec, ok, why] = ai_parse_decision(raw_text, feat, opts)
%AI_PARSE_DECISION  Validate a model reply against the supervisor's schema.
%
%   [DEC, OK, WHY] = ai.ai_parse_decision(RAW_TEXT, FEAT, OPTS)
%
%   A reply is ACCEPTED only if every one of these holds:
%     action is "SWITCH_MODE"
%     target_mode is "GFM"
%     target_buses names 1..OPTS.max_gfm_buses buses
%     every named bus is on the candidate list
%     no named bus is already forming
%     confidence is a finite number in [0,1]
%     primary_reason is a non-empty string
%
%   WHY THIS IS STRICT. The failure mode that matters is not a refusal -- a
%   refusal is caught here and falls back to the rule-based selector, which
%   always answers. It is a reply that LOOKS valid and names a bus with no
%   converter, or three buses instead of two, or a bus that is already forming.
%   Every one of those would be applied literally by a permissive parser, and
%   the second and third are exactly the circulating-current conditions the
%   design rules exist to prevent. So nothing is repaired silently: each repair
%   that IS made (a markdown fence, a scalar where an array was asked for) is
%   recorded in DEC.warnings and the decision still has to pass every check.
%
%   DEC.source is always "LLM" on success. The caller sets "FALLBACK_RULE" when
%   it substitutes ai.ai_fallback_selector, so a downstream reader can always
%   tell which produced the verdict.
%
%   See also ai.ai_call_llm, ai.ai_fallback_selector.

arguments
    raw_text (1,1) string
    feat struct
    opts struct = ai.ai_supervisor_defaults()
end

dec = empty_decision();
ok = false;

txt = strtrim(raw_text);
if strlength(txt) == 0
    why = "Model reply was empty.";
    return;
end

% A markdown fence is a formatting artefact, not a wrong decision, so it is
% removed rather than refused -- but it is recorded, because a model that
% ignores the output contract repeatedly is worth seeing.
warnings = strings(1, 0);
fenced = strip_fence(txt);
if fenced ~= txt
    warnings(end+1) = "reply was wrapped in a markdown fence";
    txt = fenced;
end

try
    d = jsondecode(char(txt));
catch
    why = "Model reply is not valid JSON.";
    return;
end
if ~isstruct(d)
    why = "Model reply is not a JSON object.";
    return;
end

% --- action ---------------------------------------------------------------
if ~isfield(d, 'action')
    why = "Reply has no action field.";
    return;
end
if ~strcmpi(string(d.action), "SWITCH_MODE")
    why = sprintf('action must be "SWITCH_MODE", got "%s".', string(d.action));
    return;
end
dec.action = "SWITCH_MODE";

% --- target_mode ----------------------------------------------------------
if ~isfield(d, 'target_mode')
    why = "Reply has no target_mode field.";
    return;
end
if ~strcmpi(string(d.target_mode), "GFM")
    why = sprintf('target_mode must be "GFM", got "%s".', string(d.target_mode));
    return;
end
dec.target_mode = "GFM";

% --- target_buses ---------------------------------------------------------
if ~isfield(d, 'target_buses') || isempty(d.target_buses)
    why = "Reply names no target_buses.";
    return;
end
raw_buses = d.target_buses;
if ~iscell(raw_buses)
    raw_buses = num2cell(raw_buses);
end
buses = nan(1, numel(raw_buses));
for k = 1:numel(raw_buses)
    [b, warn] = to_bus_number(raw_buses{k}, feat);
    if strlength(warn) > 0
        warnings(end+1) = warn; %#ok<AGROW>
    end
    if ~isfinite(b)
        why = sprintf('target_buses entry %d ("%s") is not a candidate bus.', ...
            k, string(raw_buses{k}));
        return;
    end
    buses(k) = b;
end
if numel(unique(buses)) ~= numel(buses)
    why = "target_buses repeats a bus.";
    return;
end
if numel(buses) > opts.max_gfm_buses
    why = sprintf(['target_buses names %d buses but the ceiling is %d. ' ...
        'Above two forming converters the circulating-current and ' ...
        'power-oscillation risk the design rules bound is no longer bounded.'], ...
        numel(buses), opts.max_gfm_buses);
    return;
end
for k = 1:numel(buses)
    for q = 1:numel(feat.buses)
        if feat.buses(q).bus_id ~= buses(k), continue; end
        if any(feat.gfm_indices == q)
            why = sprintf(['Bus %d is already forming; selecting it spends ' ...
                'the selection on a no-op.'], buses(k));
            return;
        end
    end
end
dec.target_buses = buses;

% --- confidence -----------------------------------------------------------
if ~isfield(d, 'confidence')
    why = "Reply has no confidence field.";
    return;
end
c = d.confidence;
if ~isnumeric(c) || ~isscalar(c) || ~isfinite(c) || c < 0 || c > 1
    why = "confidence must be a finite number in [0,1].";
    return;
end
dec.confidence = double(c);

% --- primary_reason -------------------------------------------------------
if ~isfield(d, 'primary_reason')
    why = "Reply has no primary_reason field.";
    return;
end
r = strtrim(string(d.primary_reason));
if strlength(r) == 0
    why = "primary_reason is empty.";
    return;
end
dec.primary_reason = r;

dec.warnings = warnings;
dec.source = "LLM";
ok = true;
why = "";
end

% =========================================================================
function dec = empty_decision()
%EMPTY_DECISION  The shape the caller may always index, valid or not.
dec = struct('action', "", 'target_buses', [], 'target_mode', "", ...
    'confidence', NaN, 'primary_reason', "", 'warnings', strings(1,0), ...
    'source', "");
end

function t = strip_fence(t)
%STRIP_FENCE  Remove one surrounding ```json ... ``` block if present.
t = regexprep(t, '^\s*```[a-zA-Z]*\s*', '');
t = regexprep(t, '\s*```\s*$', '');
t = strtrim(t);
end

function [b, warn] = to_bus_number(v, feat)
%TO_BUS_NUMBER  A candidate bus number from a number, a numeric string, or a
%   device id. The last two are repairs: the contract asks for bus numbers, and
%   each repair is reported so it is visible rather than absorbed.
b = NaN;
warn = "";
if isnumeric(v) && isscalar(v) && isfinite(v)
    b = double(v);
elseif ischar(v) || isstring(v)
    s = strtrim(string(v));
    n = str2double(s);
    if isfinite(n)
        b = n;
        warn = sprintf('"%s" was given as text, not a number', s);
    else
        for q = 1:numel(feat.buses)
            if strcmpi(feat.buses(q).device_id, s)
                b = feat.buses(q).bus_id;
                warn = sprintf('"%s" was given as a device id, not a bus number', s);
                return;
            end
        end
    end
end
if ~isfinite(b)
    return;
end
% Only a listed candidate is admissible; a valid-looking number that is not on
% the list is the exact failure this check exists for.
if ~any([feat.buses.bus_id] == b)
    b = NaN;
    warn = "";
end
end
