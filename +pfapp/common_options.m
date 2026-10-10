function options = common_options(tolerance)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%COMMON_OPTIONS Build a base solver options struct.

options = struct( ...
    'tolerance', tolerance, ...
    'plot_results', false, ...
    'verbose', false);
end
