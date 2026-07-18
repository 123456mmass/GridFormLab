function view = adapt_result(result, req)
%ADAPT_RESULT  Pure adapter: production result -> wizard view model.
%   view = wizard.adapt_result(result, req) builds a GENERIC twelve-section
%   view model from a production launcher result. The production result is
%   NEVER mutated (correction: "Result schemas unchanged; the result adapter
%   may add a separate view model without mutating the production result").
%
%   This is a GENERIC view model (correction #4): it does NOT force PF/SSSA/TS
%   results through +ibr/section_h_report.m. The IBR Section-H producer is
%   reused ONLY through an explicit compatible adapter (see
%   wizard.adapt_ibr_section_h). Missing information is NOT_RUN / NOT_APPLICABLE
%   and is NEVER fabricated.
%
%   The 12 sections (indexed 1..12) are a uniform presentation contract across
%   all analyses; each section's content depends on what the production result
%   actually provides:
%     1.  Analysis summary      - analysis ID, case, converged, launcher
%     2.  Case manifest         - schema, base, network size (if available)
%     3.  PF verification       - PF result fields (PF only; else NOT_RUN)
%     4.  SSSA verification     - eigenvalues/stability (SSSA only; else NOT_RUN)
%     5.  TS verification       - samples/time range/voltage (TS/IBR; else NOT_RUN)
%     6.  State inventory       - dynamic states (if available)
%     7.  Execution counts      - execution_summary (all analyses)
%     8.  Events / schedule     - event list or EVENT_FREE/NOT_APPLICABLE
%     9.  Convergence           - residual/iterations (if available)
%    10.  Stability/validity    - physical classification (if available)
%    11.  Plots                 - figure file paths (if produced)
%    12.  Log                   - log file path + status tokens
%
%   Each section has: index, title, status ('ok'|'not_run'|'not_applicable'),
%   and a content struct (analysis-specific). Missing data => 'not_run' or
%   'not_applicable', never empty/fabricated.
%
%   See also: wizard.DISPATCH_ANALYSIS, wizard.ADAPT_IBR_SECTION_H.

if nargin < 2, req = struct(); end
analysis = '';
if isstruct(req) && isfield(req, 'analysis'), analysis = req.analysis; end
if isempty(analysis) && isstruct(result) && isfield(result, 'launcher') ...
        && isfield(result.launcher, 'analysis')
    analysis = result.launcher.analysis;
end

view = struct();
view.analysis = analysis;
view.sections = repmat(section_template(), 12, 1);
view.sections = set_section(view.sections, 1, 'Analysis summary', ...
    section_analysis_summary(result, analysis));
view.sections = set_section(view.sections, 2, 'Case manifest', ...
    section_case_manifest(result));
view.sections = set_section(view.sections, 3, 'PF verification', ...
    section_pf(result, analysis));
view.sections = set_section(view.sections, 4, 'SSSA verification', ...
    section_sssa(result, analysis));
view.sections = set_section(view.sections, 5, 'TS verification', ...
    section_ts(result, analysis));
view.sections = set_section(view.sections, 6, 'State inventory', ...
    section_state_inventory(result));
view.sections = set_section(view.sections, 7, 'Execution counts', ...
    section_execution_counts(result));
view.sections = set_section(view.sections, 8, 'Events / schedule', ...
    section_events(result, req));
view.sections = set_section(view.sections, 9, 'Convergence', ...
    section_convergence(result));
view.sections = set_section(view.sections, 10, 'Stability / validity', ...
    section_stability(result, analysis));
view.sections = set_section(view.sections, 11, 'Plots', ...
    section_plots(result));
view.sections = set_section(view.sections, 12, 'Log', ...
    section_log(result));
end

function s = section_template()
s = struct('index', 0, 'title', '', 'status', 'not_run', 'content', struct());
end

function sections = set_section(sections, idx, title, content)
sections(idx).index = idx;
sections(idx).title = title;
sections(idx).status = content.status;
sections(idx).content = content.data;
end

function c = make_content(status, data)
c.status = status;
c.data = data;
end

% --- Section builders ---

function c = section_analysis_summary(result, analysis)
converged = [];
if isstruct(result) && isfield(result, 'converged')
    converged = logical(result.converged);
end
launcher = '';
log_file = '';
case_id = '';
case_label = '';
if isstruct(result) && isfield(result, 'launcher')
    l = result.launcher;
    if isfield(l, 'analysis'), launcher = l.analysis; end
    if isfield(l, 'log_file'), log_file = l.log_file; end
    if isfield(l, 'case_id'), case_id = l.case_id; end
    if isfield(l, 'case_label'), case_label = l.case_label; end
end
data = struct('analysis', analysis, 'converged', converged, ...
    'launcher', launcher, 'case_id', case_id, 'case_label', case_label, ...
    'log_file', log_file);
c = make_content('ok', data);
end

function c = section_case_manifest(result)
schema = ''; base_mva = []; freq_hz = []; nbus = []; nbranch = [];
if isstruct(result)
    if isfield(result, 'base_values')
        if isfield(result.base_values, 'S_base_MVA'), base_mva = result.base_values.S_base_MVA; end
        if isfield(result.base_values, 'frequency_Hz'), freq_hz = result.base_values.frequency_Hz; end
    end
    if isfield(result, 'bus_voltage'), nbus = numel(result.bus_voltage); end
    if isfield(result, 'line_endpoints'), nbranch = size(result.line_endpoints, 1); end
end
if isempty(nbus) && isempty(nbranch)
    c = make_content('not_run', struct());
    return;
end
data = struct('schema', schema, 'base_MVA', base_mva, 'frequency_Hz', freq_hz, ...
    'n_bus', nbus, 'n_branch', nbranch);
c = make_content('ok', data);
end

function c = section_pf(result, analysis)
if ~strcmp(analysis, 'pf')
    c = make_content('not_applicable', struct('reason', 'PF section applies only to pf analysis'));
    return;
end
if ~(isstruct(result) && isfield(result, 'converged'))
    c = make_content('not_run', struct());
    return;
end
data = struct('converged', logical(result.converged));
if isfield(result, 'iterations'), data.iterations = result.iterations; end
if isfield(result, 'max_mismatch'), data.max_mismatch = result.max_mismatch; end
if isfield(result, 'bus_voltage')
    data.voltage_min = min(result.bus_voltage);
    data.voltage_max = max(result.bus_voltage);
end
if isfield(result, 'bus_angle_deg')
    data.angle_min = min(result.bus_angle_deg);
    data.angle_max = max(result.bus_angle_deg);
end
if isfield(result, 'metadata') && isfield(result.metadata, 'method_executed')
    data.method_executed = result.metadata.method_executed;
end
c = make_content('ok', data);
end

function c = section_sssa(result, analysis)
if ~strcmp(analysis, 'sssa')
    c = make_content('not_applicable', struct('reason', 'SSSA section applies only to sssa analysis'));
    return;
end
if ~(isstruct(result) && isfield(result, 'eigenvalues'))
    c = make_content('not_run', struct());
    return;
end
lam = result.eigenvalues(:);
data = struct('eigenvalue_count', numel(lam), ...
    'max_real', max(real(lam)));
if isfield(result, 'stability_status'), data.stability_status = result.stability_status; end
if isfield(result, 'root_counts'), data.root_counts = result.root_counts; end
if isfield(result, 'state_names'), data.state_names = result.state_names; end
c = make_content('ok', data);
end

function c = section_ts(result, analysis)
if ~ismember(analysis, {'ts','ibr'})
    c = make_content('not_applicable', struct('reason', 'TS section applies only to ts/ibr analysis'));
    return;
end
if ~(isstruct(result) && isfield(result, 't')) || isempty(result.t)
    c = make_content('not_run', struct());
    return;
end
data = struct('n_samples', numel(result.t), ...
    't_start', result.t(1), 't_end', result.t(end));
if isfield(result, 'Vbus')
    data.voltage_min = min(result.Vbus, [], 'all');
end
if isfield(result, 'integrator'), data.integrator = result.integrator; end
c = make_content('ok', data);
end

function c = section_state_inventory(result)
names = {};
if isstruct(result)
    if isfield(result, 'state_names') && ~isempty(result.state_names)
        names = result.state_names;
    elseif isfield(result, 'equilibrium') && isstruct(result.equilibrium) ...
            && isfield(result.equilibrium, 'state_names') && ~isempty(result.equilibrium.state_names)
        names = result.equilibrium.state_names;
    end
end
if isempty(names)
    c = make_content('not_run', struct());
    return;
end
data = struct('state_count', numel(names), 'state_names', names);
c = make_content('ok', data);
end

function c = section_execution_counts(result)
if ~(isstruct(result) && isfield(result, 'execution_summary'))
    c = make_content('not_run', struct());
    return;
end
c = make_content('ok', result.execution_summary);
end

function c = section_events(result, req)
events_policy = '';
if isstruct(req) && isfield(req, 'events_policy')
    events_policy = req.events_policy;
end
switch events_policy
    case 'not_applicable'
        c = make_content('not_applicable', struct('reason', 'Events NOT_APPLICABLE to this analysis'));
    case 'event_free'
        n_tx = 0;
        if isstruct(result) && isfield(result, 'execution_summary') ...
                && isfield(result.execution_summary, 'event_transactions')
            n_tx = result.execution_summary.event_transactions;
        end
        c = make_content('ok', struct('policy', 'EVENT_FREE_NORMAL_OPERATION', ...
            'event_transactions', n_tx));
    case 'configured'
        n_tx = NaN;
        if isstruct(result) && isfield(result, 'execution_summary') ...
                && isfield(result.execution_summary, 'event_transactions')
            n_tx = result.execution_summary.event_transactions;
        end
        c = make_content('ok', struct('policy', 'CONFIGURED', ...
            'event_transactions', n_tx));
    otherwise
        c = make_content('not_run', struct());
end
end

function c = section_convergence(result)
data = struct();
status = 'not_run';
if isstruct(result)
    if isfield(result, 'converged')
        data.converged = logical(result.converged);
        status = 'ok';
    end
    if isfield(result, 'newton_residual'), data.newton_residual = result.newton_residual; end
    if isfield(result, 'iterations'), data.iterations = result.iterations; end
    if isfield(result, 'max_mismatch'), data.max_mismatch = result.max_mismatch; end
    if isfield(result, 'nonconverged_step_count')
        data.nonconverged_step_count = result.nonconverged_step_count;
    end
end
c = make_content(status, data);
end

function c = section_stability(result, analysis)
switch analysis
    case 'sssa'
        if isstruct(result) && isfield(result, 'stability_status')
            c = make_content('ok', struct('classification', result.stability_status, ...
                'tolerance', result.stability_tolerance));
        else
            c = make_content('not_run', struct());
        end
    case {'ts','ibr'}
        if isstruct(result) && isfield(result, 'converged')
            if logical(result.converged)
                cls = 'CONVERGED (numerical)';
            else
                cls = 'FAILED CLOSED (numerical)';
            end
            c = make_content('ok', struct('classification', cls));
        else
            c = make_content('not_run', struct());
        end
    case 'pf'
        if isstruct(result) && isfield(result, 'converged')
            if logical(result.converged)
                cls = 'CONVERGED';
            else
                cls = 'FAILED CLOSED';
            end
            c = make_content('ok', struct('classification', cls));
        else
            c = make_content('not_run', struct());
        end
    otherwise
        c = make_content('not_applicable', struct('reason', 'No stability classification for this analysis'));
end
end

function c = section_plots(result)
figs = {};
if isstruct(result)
    if isfield(result, 'figure_files'), figs = result.figure_files; end
    if isfield(result, 'figure_file'), figs{end+1} = result.figure_file; end %#ok<AGROW>
end
figs = figs(:).';
if isempty(figs)
    c = make_content('not_run', struct());
else
    c = make_content('ok', struct('figure_files', figs));
end
end

function c = section_log(result)
log_file = '';
status_token = '';
if isstruct(result) && isfield(result, 'launcher') && isfield(result.launcher, 'log_file')
    log_file = result.launcher.log_file;
end
if isempty(log_file)
    c = make_content('not_run', struct());
    return;
end
data = struct('log_file', log_file);
% Do not read the file here (keeps the adapter pure and fast); the UI reads
% stable tokens on demand. Record whether the file exists.
data.exists = (exist(log_file, 'file') == 2);
c = make_content('ok', data);
end
