function safe_name = make_safe_name(name)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
safe_name = regexprep(char(name), '[^A-Za-z0-9_]+', '_');
safe_name = regexprep(safe_name, '_+', '_');
safe_name = regexprep(safe_name, '^_|_$', '');
end
