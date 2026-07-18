function result = solve_case(varargin)
%SOLVE_CASE Interactive in-house PF / SSSA / TS / IBR launcher.
%   RESULT = SOLVE_CASE() opens the analysis wizard (base-MATLAB UI).
%   RESULT = SOLVE_CASE('analysis',ID,'case',ID,'options',OPT) is the
%   non-interactive (programmatic) form. Production: project solvers only.
%
%   This is a THIN WRAPPER (Wizard Phase 3, Extract + delegate). The pure
%   responsibilities live in +wizard/*:
%     - programmatic path -> wizard.build_request -> wizard.validate_request
%                             -> wizard.dispatch_analysis (single shared
%                             dispatcher used by BOTH the wizard UI and the
%                             programmatic path, G4)
%     - interactive / partial path -> wizard.show (opens the wizard UI with
%                             supplied selections pre-populated; NEVER
%                             auto-executes, correction #3)
%
%   ABI, result schemas, failure IDs, log-file behavior, and the headless
%   path are preserved (frozen by tests/test_wizard_characterization.m).
%   The no-argument interactive surface is an intentional UI replacement
%   (correction #2): it does not reproduce the old dialog sequence.

pf_init_paths();

p = inputParser;
addParameter(p, 'analysis', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'case', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'options', struct(), @isstruct);
parse(p, varargin{:});
analysis = lower(char(p.Results.analysis));
case_id = lower(char(p.Results.case));
user_opt = p.Results.options;

% Determine whether this is an interactive (UI) or programmatic invocation.
% Partial invocation (analysis given, case omitted — or both omitted) opens
% the wizard UI with supplied selections pre-populated and never auto-executes
% (correction #3).
interactive = isempty(analysis) || isempty(case_id);

if interactive
    % Wizard UI path. The wizard collects the remaining selections and, on
    % Run, calls wizard.dispatch_analysis (the same dispatcher as below).
    result = wizard.show('analysis', analysis, 'case', case_id, ...
        'options', user_opt);
    return;
end

% Programmatic path: build -> validate -> dispatch (single shared dispatcher).
req = wizard.build_request(analysis, case_id, 'options', user_opt);
req = wizard.validate_request(req);
result = wizard.dispatch_analysis(req);
end
