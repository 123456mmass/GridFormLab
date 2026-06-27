function value = pf_get_option(options, field_name, default_value)
%PF_GET_OPTION Return an option value with a default fallback.

if isstruct(options) && isfield(options, field_name) && ~isempty(options.(field_name))
    value = options.(field_name);
else
    value = default_value;
end
end
