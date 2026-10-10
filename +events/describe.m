function lines = describe(ev)
%EVENTS.DESCRIBE  Human-readable rendering of an event configuration.
%   LINES = events.describe(EV) returns a cellstr of display lines: the case,
%   the profile, the four editable values, and the DERIVED fault-clearing
%   instant, labelled as derived. It is a DISPLAY helper -- it loads no case,
%   calls no solver, and does NOT validate.
%
%   It deliberately does not throw on an unset field: the whole point is to
%   let a user see what a half-edited file currently says. An unset value is
%   rendered as <unset>, and an unset derived instant is rendered as
%   <underivable>. Call events.validate for the fail-closed verdict.
%
%   See also: events.LIST, events.LOAD, events.VALIDATE.

lines = {};
if ~isstruct(ev) || ~isscalar(ev)
    lines = {sprintf('Event configuration: <not a struct: %s>', class(ev))};
    return;
end

t_fault = value_of(ev, 't_fault');
ds = value_of(ev, 'ds');
if isnumeric(t_fault) && isscalar(t_fault) && isnumeric(ds) && isscalar(ds) && ...
        ~isempty(t_fault) && ~isempty(ds)
    clear_text = sprintf('%s s  (DERIVED = t_fault + ds; never stored)', ...
        num2str(t_fault + ds, '%.15g'));
else
    clear_text = '<underivable: t_fault and ds must both be set>';
end

lines{end+1} = sprintf('Case           : %s', text_of(ev, 'case_id'));
lines{end+1} = sprintf('Profile        : %s', text_of(ev, 'profile'));
lines{end+1} = sprintf('Fault bus      : %s', num_of(ev, 'fault_bus'));
lines{end+1} = sprintf('Fault on       : %s s', num_of(ev, 't_fault'));
lines{end+1} = sprintf('Fault duration : %s s   (ds, the SINGLE authoritative duration)', ...
    num_of(ev, 'ds'));
lines{end+1} = sprintf('Fault cleared  : %s', clear_text);
lines{end+1} = sprintf('Machine trip   : %s', instant_of(ev, 'trip'));
lines{end+1} = sprintf('Reclose (sg_on): %s', instant_of(ev, 'sg_on'));
lines{end+1} = sprintf('Fault Zf       : %s pu', complex_of(ev, 'Zf'));

% Notes, if the file carries any. Blank lines are dropped so an empty notes
% cell does not add noise to the GUI band.
if isfield(ev, 'notes') && ~isempty(ev.notes)
    if ischar(ev.notes), notes = {ev.notes}; else, notes = cellstr(ev.notes); end
    for k = 1:numel(notes)
        n = strtrim(notes{k});
        if ~isempty(n)
            lines{end+1} = sprintf('Note           : %s', n); %#ok<AGROW>
        end
    end
end
end

% =========================================================================
function v = value_of(ev, name)
v = [];
if isfield(ev, name), v = ev.(name); end
end

function s = text_of(ev, name)
v = value_of(ev, name);
if isempty(v)
    s = '<unset>';
elseif ischar(v) || (isstring(v) && isscalar(v))
    s = char(v);
else
    s = sprintf('<%s>', class(v));
end
end

function s = num_of(ev, name)
v = value_of(ev, name);
if isempty(v)
    s = '<unset>';
elseif isnumeric(v) && isscalar(v) && isreal(v)
    s = num2str(v, '%.15g');
else
    s = sprintf('<%s>', class(v));
end
end

function s = complex_of(ev, name)
v = value_of(ev, name);
if isempty(v)
    s = '<unset>';
elseif isnumeric(v) && isscalar(v)
    if isreal(v)
        s = num2str(v, '%.15g');
    else
        % Numeric format, not %s: a '+' flag on %s is not a valid conversion
        % and silently eats the sign.
        s = sprintf('%.15g%+.15gj', real(v), imag(v));
    end
else
    s = sprintf('<%s>', class(v));
end
end

function s = instant_of(ev, name)
% [] means "this event is not armed" for trip and sg_on.
v = value_of(ev, name);
if isempty(v)
    s = 'none ([] = not armed)';
elseif isnumeric(v) && isscalar(v) && isreal(v)
    s = sprintf('%s s', num2str(v, '%.15g'));
else
    s = sprintf('<%s>', class(v));
end
end
