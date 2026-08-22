function s = pf_tex_sci(v,opts)
%PF_TEX_SCI  Format a number as LaTeX scientific notation, never as %e.
%
%   s = pf_tex_sci(v)
%   s = pf_tex_sci(v, digits=3, signed=false)
%
% AGENTS.md forbids a programming-language exponent form (4.448e-08) anywhere in
% report tables or text; powers of ten must be written $a\times10^{n}$. A
% generator that emits %e into a table is a defect, so every numeric that may be
% small or large goes through here.
%
% Non-finite input returns '--', which is the repository's convention for "not
% applicable / not reached" in a comparison table. It never returns 'NaN'.

arguments
    v (1,1) double
    opts.digits (1,1) double = 3
    opts.signed (1,1) logical = false
    opts.plain_range (1,2) double = [1e-3 1e4]
end

if ~isfinite(v), s = '--'; return; end
if v == 0, s = '$0$'; return; end

a = abs(v);
if a >= opts.plain_range(1) && a < opts.plain_range(2)
    % Inside the comfortable range a plain decimal reads better and is still
    % exponent-free, so it satisfies the same rule.
    if opts.signed
        s = sprintf('$%+.*f$',opts.digits,v);
    else
        s = sprintf('$%.*f$',opts.digits,v);
    end
    return;
end

e = floor(log10(a));
m = v/10^e;
if opts.signed
    s = sprintf('$%+.*f\\times10^{%d}$',opts.digits,m,e);
else
    s = sprintf('$%.*f\\times10^{%d}$',opts.digits,m,e);
end
end
