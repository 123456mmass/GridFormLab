function info = validate_time_grid(t_raw, tg, t_fault, t_clear)
%VALIDATE_TIME_GRID  Pure time-grid contract checks for cross-validation.
%   Separates the distinct concepts:
%     raw_grid_equal      : true ONLY if t_raw and tg have equal length and
%                           every timestamp matches (within tol). PSAT 1509
%                           vs Ours 1501 => false.
%     comparison_grid_valid: tg is strictly monotonic, covers [0,t_end],
%                           and contains the fault/clear event timestamps.
%     coverage_valid      : t_raw covers the whole common grid tg (no
%                           extrapolation needed). If false, interpolation
%                           would have to extrapolate -> gate must fail.
%     event_grid_valid    : t_fault and t_clear appear in tg (within dt/2).
%   NO interpolation is performed here; this only validates grids. Use
%   interp_no_extrapolate for the actual interpolation (which rejects
%   out-of-range / NaN).

info = struct();
info.raw_nt = numel(t_raw);
info.common_nt = numel(tg);
info.raw_grid_equal = (numel(t_raw)==numel(tg)) && all(abs(t_raw(:)-tg(:)) <= 1e-9);
info.comparison_grid_valid = numel(tg)>=2 && all(diff(tg)>0) && abs(tg(1))<1e-12;
info.coverage_valid = (min(t_raw) <= min(tg) + 1e-12) && (max(t_raw) >= max(tg) - 1e-12);
if nargin>=3 && ~isempty(t_fault)
    info.event_grid_valid = any(abs(tg-t_fault) <= (tg(2)-tg(1))/2 + 1e-12) && ...
                            any(abs(tg-t_clear) <= (tg(2)-tg(1))/2 + 1e-12);
else
    info.event_grid_valid = true;
end
end

