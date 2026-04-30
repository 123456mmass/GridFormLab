function v = num_or(s, field, default)
%NUM_OR  Return field if numeric, else default.
v = value_or(s, field, default);
if ~isnumeric(v), v = default; end
end
