function values = fillmissing_for_plot(values)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
values(~isfinite(values)) = NaN;
end
