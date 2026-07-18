function s = format_value(v)
%FORMAT_VALUE  Render an option value as a compact string for the table.
if islogical(v) && isscalar(v)
    if v, s = 'true'; else, s = 'false'; end
elseif isnumeric(v) && isscalar(v)
    if isreal(v), s = sprintf('%.12g', v);
    else, s = sprintf('%.12g%+.12gj', real(v), imag(v)); end
elseif ischar(v) || (isstring(v) && isscalar(v))
    s = char(v);
elseif isempty(v)
    s = '[]';
else
    s = sprintf('<%s>', class(v));
end
end
