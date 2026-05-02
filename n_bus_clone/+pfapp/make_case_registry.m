function [case_labels, case_loaders] = make_case_registry()
%MAKE_CASE_REGISTRY Build the case dropdown list. Uses auto-discovery with hardcoded fallback.

% Try auto-discovery first
cases_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+cases');
try
    [case_labels, case_loaders] = pfapp.discover_cases(cases_dir);
catch
    case_labels = {};
    case_loaders = {};
end

% If auto-discovery produced nothing, use hardcoded fallback
if isempty(case_labels)
    case_labels = {'5-bus demo', '14-bus demo', 'MATPOWER 300-bus reference', ...
        'Saadat 3-bus PQ', 'Saadat 3-bus PV', 'Saadat 30-bus reference', ...
        'Saadat OPF Ex 7.4', 'Saadat OPF Ex 7.5', 'Saadat OPF Ex 7.6'};
    case_loaders = {@case_ieee5bus, @case_ieee14bus, @case_ieee300bus, ...
        @case_saadat_example_6_7, @case_saadat_example_6_8, @case_saadat_ieee30bus, ...
        @case_saadat_opf_example_7_4, @case_saadat_opf_example_7_5, @case_saadat_opf_example_7_6};
end
end
