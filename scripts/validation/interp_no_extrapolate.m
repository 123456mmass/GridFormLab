function y = interp_no_extrapolate(t_raw, y_raw, tg)
%INTERP_NO_EXTRAPOLATE  Linear interpolation onto tg with NO zero-fill /
%   extrapolation. Errors if tg extends beyond t_raw (coverage failure) or
%   if NaN/Inf appears in the result. Callers must catch the error and fail
%   the gate (never silently fill with 0). Guards the bug where interp1 with
%   a 0 fill created extrapolated values that were not real samples.
if min(t_raw) > min(tg) + 1e-12 || max(t_raw) < max(tg) - 1e-12
    error('interp_no_extrapolate:coverage', ...
        'common grid [%.3g,%.3g] not covered by raw [%.3g,%.3g] (extrapolation refused).', ...
        min(tg), max(tg), min(t_raw), max(t_raw));
end
[tu,ui] = unique(t_raw);
if numel(tu) < 2, error('interp_no_extrapolate:degenerate','raw grid has <2 unique points.'); end
y = interp1(tu, y_raw(ui,:), tg, 'linear');
if any(~isfinite(y(:)))
    error('interp_no_extrapolate:nan','interpolation produced NaN/Inf (refused).');
end
end
