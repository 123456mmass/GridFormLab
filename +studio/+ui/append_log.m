function append_log(h, line)
%APPEND_LOG  Append one line to a log uitextarea (no timestamps).
%   studio.ui.append_log(h, line) appends LINE (char or string) to the Value
%   of the read-only log box h.  Empty lines are preserved; no timestamp is
%   added so output stays deterministic for tests.
%
%   See also: studio.ui.READONLY_TEXTAREA.

line = char(line);
old = h.Value;
if ischar(old) || isstring(old)
    old = cellstr(old);
end
if numel(old) == 1 && isempty(strtrim(old{1}))
    h.Value = {line};
else
    h.Value = [old(:); {line}];
end
end
