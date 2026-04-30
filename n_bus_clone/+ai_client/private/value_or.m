function v = value_or(s, field, default)
%VALUE_OR  Return field value if present and non-empty, else default.
if isfield(s, field) && ~isempty(s.(field))
    v = s.(field);
else
    v = default;
end
end
