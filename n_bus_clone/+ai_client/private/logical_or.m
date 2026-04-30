function v = logical_or(s, field, default)
%LOGICAL_OR  Return field if logical, else default.
v = value_or(s, field, default);
if ~islogical(v), v = default; end
end
