function safe_name = make_safe_name(name)
safe_name = regexprep(char(name), '[^A-Za-z0-9_]+', '_');
safe_name = regexprep(safe_name, '_+', '_');
safe_name = regexprep(safe_name, '^_|_$', '');
end
