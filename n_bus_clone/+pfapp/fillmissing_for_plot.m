function values = fillmissing_for_plot(values)
values(~isfinite(values)) = 0;
end
