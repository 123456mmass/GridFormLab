function result = run_analysis(analysis, case_data, opt)
%RUN_ANALYSIS  The studio's pure dispatch: analysis + case_data -> result.
%   result = studio.run_analysis(analysis, case_data, opt) executes exactly
%   the production call sites of the ONE shared request dispatcher.  Three
%   switch arms, each reproducing its call site verbatim:
%
%     'pf'   -> pfsolver.pf_resolve_method + pfsolver.pf_method_strategy
%               (...).solve          (dispatch_analysis.m pf arm)
%     'sssa' -> stability.multicase_sssa(case_data, opt)
%     'ts'   -> stability.ts_simulate(case_data, opt)
%
%   This function performs NO case loading, NO default merging, NO event
%   construction, NO diary, NO stdout capture and NO PNG dumping -- a GUI
%   button must not create log files.  Options are the caller's; events are
%   folded into opt at the UI layer before this call.  Diagnostics are
%   written only via studio.save_diagnostics when opt.save_diagnostics is
%   set (a separate explicit action).
%
%   'ibr' is deliberately NOT routed here: the studio runs PF / SSSA / TS
%   only.  Unknown analysis IDs fail closed.
%
%   See also: studio.DETECT_RESOURCES, studio.SAVE_DIAGNOSTICS.

if nargin < 3 || isempty(opt), opt = struct(); end
if ~isstruct(opt)
    error('studio:run_analysis:badOptions', 'opt must be a struct.');
end
if ~isstruct(case_data)
    error('studio:run_analysis:badCase', 'case_data must be a struct.');
end

switch lower(char(analysis))
    case 'pf'
        [pf_method_name, pf_selection_source] = pfsolver.pf_resolve_method(opt);
        pf_strat = pfsolver.pf_method_strategy(pf_method_name);
        result = pf_strat.solve(case_data, opt);
    case 'sssa'
        result = stability.multicase_sssa(case_data, opt);
    case 'ts'
        result = stability.ts_simulate(case_data, opt);
    otherwise
        error('studio:run_analysis:unknownAnalysis', ...
            ['Unknown analysis ID %s. The studio runs pf, sssa and ts only ' ...
             '(the owner: PF / SSSA / TS).'], char(analysis));
end
end
