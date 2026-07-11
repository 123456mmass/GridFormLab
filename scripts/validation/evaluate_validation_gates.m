function [all_pass, report] = evaluate_validation_gates(g)
%EVALUATE_VALIDATION_GATES  Strict aggregate gate evaluation.
%   Given a struct of ALL required gate fields (each logical), returns
%   all_pass = true ONLY if every required gate is present, finite, logical,
%   and true. Missing field / empty / NaN / non-logical / false / exception
%   => all_pass = false. A skipped required gate is a failure, never a pass.
%
%   Required gate fields (flat or nested):
%     production_dependency, no_kundur_acceptance_target, regression,
%     emf6_no_fault, emf6_shared_model,
%     case14.contract, case14.mapping, case14.comparison_grid,
%       case14.event_grid, case14.sample_alignment, case14.extrapolation_used_false,
%       case14.psat_execution, case14.pgaz_execution, case14.ours_convergence,
%       case14.psat_comparison, case14.pgaz_plateau, case14.pgaz_comparison,
%     rts24.* (same set as case14)
%   case14.extrapolation_used_false and *.pgaz_comparison are required gates
%   (extrapolation must be false; plateau PGAz must match within tolerance).

required = { ...
 'production_dependency','no_kundur_acceptance_target','regression', ...
 'emf6_no_fault','emf6_shared_model', ...
 'case14.contract','case14.mapping','case14.comparison_grid','case14.event_grid', ...
 'case14.sample_alignment','case14.extrapolation_used_false','case14.psat_execution', ...
 'case14.pgaz_execution','case14.ours_convergence','case14.psat_comparison', ...
 'case14.pgaz_plateau','case14.pgaz_comparison', ...
 'rts24.contract','rts24.mapping','rts24.comparison_grid','rts24.event_grid', ...
 'rts24.sample_alignment','rts24.extrapolation_used_false','rts24.psat_execution', ...
 'rts24.pgaz_execution','rts24.ours_convergence','rts24.psat_comparison', ...
 'rts24.pgaz_plateau','rts24.pgaz_comparison'};

report = struct();
report.missing = {};
report.invalid = {};
report.false = {};
report.value = struct();
all_pass = true;
for i = 1:numel(required)
    path = strsplit(required{i}, '.');
    val = get_nested(g, path);
    if isempty(val)
        report.missing{end+1} = required{i}; all_pass = false; continue; %#ok<AGROW>
    end
    if ~islogical(val) && ~(isnumeric(val) && (val==0 || val==1))
        report.invalid{end+1} = required{i}; all_pass = false; continue; %#ok<AGROW>
    end
    if isnan(val)
        report.invalid{end+1} = required{i}; all_pass = false; continue; %#ok<AGROW>
    end
    report.value.(strrep(required{i},'.','_')) = val;
    if ~val
        report.false{end+1} = required{i}; all_pass = false; %#ok<AGROW>
    end
end
end

function val = get_nested(s, path)
val = [];
cur = s;
for k = 1:numel(path)
    if ~isstruct(cur) || ~isfield(cur, path{k}), return; end
    cur = cur.(path{k});
end
val = cur;
end
