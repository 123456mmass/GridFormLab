function values = fillmissing_for_plot(values)
values(~isfinite(values)) = NaN;
end
