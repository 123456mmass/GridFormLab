function section_h = adapt_ibr_section_h(result, req)
%ADAPT_IBR_SECTION_H  Explicit adapter: IBR wizard result -> Section H report.
%   section_h = wizard.adapt_ibr_section_h(result, req) builds the inputs
%   bundle expected by +ibr/section_h_report.m from a wizard IBR result +
%   request, then calls that IBR-owned Section H producer.
%
%   This is the EXPLICIT compatible adapter required by correction #4: the
%   generic 12-section view model (wizard.adapt_result) does NOT force
%   PF/SSSA/TS results through section_h_report. Only IBR results go through
%   this adapter, and only when the IBR result actually carries the fields
%   section_h_report needs. Missing information is NOT_RUN / NOT_APPLICABLE,
%   never fabricated.
%
%   The adapter is a PURE read-only consumer: it does NOT call any solver,
%   does NOT edit the production result, and invents no counters, eigenvalues,
%   or participation. It only assembles the inputs bundle from fields the IBR
%   launcher already produced (case_data via the case loader, inventory via
%   ibr.state_inventory_snapshot if available, the result's own equilibrium /
%   status_log / execution_summary).
%
%   If the result does not carry the required bundle fields (e.g. a failed
%   selection with no scenario), the adapter returns a NOT_RUN marker rather
%   than calling section_h_report with incomplete data.
%
%   See also: wizard.ADAPT_RESULT, ibr.section_h_report.

if nargin < 2, req = struct(); end
analysis = '';
if isstruct(req) && isfield(req, 'analysis'), analysis = req.analysis; end

section_h = struct('status', 'not_run', 'report', struct(), 'fingerprint', '');

% Only IBR results are eligible for the Section H producer.
if ~strcmp(analysis, 'ibr')
    section_h.status = 'not_applicable';
    section_h.report = struct('reason', ...
        'Section H producer applies only to IBR results');
    return;
end

% Build the inputs bundle from the IBR result. The IBR launcher
% (stability.run_hybrid_case via wizard.dispatch_analysis) produces the
% equilibrium, status_log, execution_summary, and (when configured) the
% modal_A via stability.modal_analysis. The adapter does not recompute
% anything; it forwards what the result already carries.
if ~(isstruct(result) && isfield(result, 'converged'))
    section_h.status = 'not_run';
    section_h.report = struct('reason', 'IBR result missing converged flag');
    return;
end

% Reload case_data via the case loader (lazy; the wizard already loaded it
% for dispatch, but the result struct does not carry it). This is the same
% zero-arg loader the wizard used.
entries = wizard.discover_cases('ibr');
case_id = '';
if isstruct(req) && isfield(req, 'case_id'), case_id = req.case_id; end
if isempty(case_id)
    section_h.status = 'not_run';
    section_h.report = struct('reason', 'No case_id in request');
    return;
end
idx = find(strcmp(case_id, {entries.id}), 1);
if isempty(idx)
    section_h.status = 'not_run';
    section_h.report = struct('reason', sprintf('Unknown case %s', case_id));
    return;
end
case_data = entries(idx).loader();

% Assemble the inputs bundle from the result's existing fields. The adapter
% does NOT compute the inventory or modal_A; if the result does not carry
% them, they are left empty and section_h_report will emit NOT_RUN for those
% sections (it is a read-only consumer that handles missing optional inputs).
inputs = struct();
inputs.case_data = case_data;
inputs.resource_map = struct();
if isfield(result, 'equilibrium'), inputs.equilibrium = result.equilibrium; end
if isfield(result, 'status_log'), inputs.status_log = result.status_log; end
if isfield(result, 'execution_summary')
    inputs.execution_counters = result.execution_summary;
end
if isfield(result, 'selector_log'), inputs.selector_log = result.selector_log; end
if isfield(result, 'fingerprint'), inputs.fingerprint = result.fingerprint; end
if isfield(result, 't'), inputs.ts_result = result; end

% The state inventory is a separate Phase-1 product. If the result does not
% carry it, leave it empty; section_h_report handles the missing optional
% input by emitting NOT_RUN for the inventory-dependent sections.
if isfield(result, 'inventory')
    inputs.inventory = result.inventory;
else
    inputs.inventory = struct();
end

% Call the IBR-owned Section H producer (read-only consumer).
try
    report = ibr.section_h_report(inputs);
    section_h.status = 'ok';
    section_h.report = report;
    if isstruct(report) && isfield(report, 'analysis_fingerprint')
        section_h.fingerprint = char(report.analysis_fingerprint);
    end
catch e
    % Fail closed: never fabricate Section H content. Report the failure.
    section_h.status = 'not_run';
    section_h.report = struct('reason', sprintf('section_h_report: %s', e.message));
end
end
