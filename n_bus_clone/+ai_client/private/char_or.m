function v = char_or(s, field, default)
%CHAR_OR  Return field as char, or default if not a char vector.
v = value_or(s, field, default);
if ~ischar(v), v = default; end
end
