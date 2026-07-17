function text = render_section_h_report(report, opt)
%RENDER_SECTION_H_REPORT  Render a Section H report struct to text.
%
%   text = ibr.render_section_h_report(report, opt) returns a plain-text
%   rendering of the 12 mandatory Section H sections + spectrum tables +
%   participation + TS tables + counters + fingerprint. Read-only: does
%   NOT write files, does NOT call solvers, does NOT mutate the report.

arguments
    report struct
    opt struct = struct()
end

lines = {};
lines = append_line(lines, '================================================================');
lines = append_line(lines, 'SECTION H REPORT');
lines = append_line(lines, sprintf('schema_version: %s', report.schema_version));
lines = append_line(lines, sprintf('status: %s', report.status));
lines = append_line(lines, sprintf('GFL_PLL_PARTICIPATION: %s', report.gfl_pll_participation));
lines = append_line(lines, '================================================================');

% 12 sections
for k = 1:numel(report.sections)
    s = report.sections(k);
    lines = append_line(lines, '');
    lines = append_line(lines, sprintf('--- %d. %s ---', s.section_id, s.title));
    lines = append_line(lines, sprintf('applicability: %s', s.applicability));
    lines = append_line(lines, sprintf('status: %s', s.status));
    if ~isempty(s.reason)
        lines = append_line(lines, sprintf('reason: %s', s.reason));
    end
    if isfield(s,'summary') && isstruct(s.summary) && ~isempty(fieldnames(s.summary))
        lines = append_line(lines, 'summary:');
        fns = fieldnames(s.summary);
        for j = 1:numel(fns)
            v = s.summary.(fns{j});
            lines = append_line(lines, sprintf('  %s = %s', fns{j}, format_val(v)));
        end
    end
end

% Full state eigenvalues
lines = append_line(lines, '');
lines = append_line(lines, '=== FULL STATE EIGENVALUES ===');
lines = append_line(lines, sprintf('status: %s', report.full_state_eigenvalues.status));
if strcmp(report.full_state_eigenvalues.status, 'AVAILABLE')
    rows = report.full_state_eigenvalues.rows;
    lines = append_line(lines, sprintf('Mode | raw | pair | eigenvalue (formatted)        | right_res   | left_res    | status'));
    for k = 1:numel(rows)
        r = get_row(rows, k);
        lines = append_line(lines, sprintf('%4d | %4d | %4d | %s | %.3e | %.3e | %s', ...
            r.display_mode_number, r.raw_eigen_index, r.conjugate_pair_id, ...
            r.formatted_eigenvalue, r.right_residual, r.left_residual, ...
            r.participation_status));
    end
    lines = append_line(lines, sprintf('row_count=%d  size_Ared=%d  cardinality_check=%s', ...
        report.validation.full_state_eigenvalues_count, report.validation.size_Ared, ...
        format_val(report.validation.cardinality_check)));
end

% Physical decision eigenvalues
lines = append_line(lines, '');
lines = append_line(lines, '=== PHYSICAL DECISION EIGENVALUES ===');
lines = append_line(lines, sprintf('status: %s', report.physical_decision_eigenvalues.status));
if strcmp(report.physical_decision_eigenvalues.status, 'AVAILABLE')
    rows = report.physical_decision_eigenvalues.rows;
    lines = append_line(lines, sprintf('Mode | raw | pair | eigenvalue (formatted)        | status'));
    for k = 1:numel(rows)
        r = get_row(rows, k);
        lines = append_line(lines, sprintf('%4d | %4d | %4d | %s | %s', ...
            r.display_mode_number, r.raw_eigen_index, r.conjugate_pair_id, ...
            r.formatted_eigenvalue, r.participation_status));
    end
end

% Participation
lines = append_line(lines, '');
lines = append_line(lines, '=== PARTICIPATION FACTORS ===');
lines = append_line(lines, sprintf('status: %s', report.participation.status));
if strcmp(report.participation.status, 'AVAILABLE')
    lines = append_line(lines, sprintf('GFL_PLL_PARTICIPATION: %s', report.participation.summary.gfl_pll_participation));
    rows = report.participation.rows;
    lines = append_line(lines, sprintf('Mode | raw | pair | status                       | reason                       | part_sum'));
    for k = 1:numel(rows)
        r = get_row(rows, k);
        lines = append_line(lines, sprintf('%4d | %4d | %4d | %-28s | %-28s | %.4f', ...
            r.display_mode_number, r.raw_eigen_index, r.conjugate_pair_id, ...
            r.participation_status, r.participation_reason, r.participation_sum));
    end
end

% TS tables
lines = append_line(lines, '');
lines = append_line(lines, '=== TS SAMPLES ===');
lines = append_line(lines, sprintf('status: %s', report.ts_samples.status));
if strcmp(report.ts_samples.status, 'AVAILABLE')
    lines = append_line(lines, sprintf('n_samples: %d', report.ts_samples.summary.n_samples));
end
lines = append_line(lines, '');
lines = append_line(lines, '=== TS EVENTS ===');
lines = append_line(lines, sprintf('status: %s', report.ts_events.status));
if strcmp(report.ts_events.status, 'AVAILABLE')
    lines = append_line(lines, sprintf('n_events: %d', report.ts_events.summary.n_events));
end

% Execution counters
lines = append_line(lines, '');
lines = append_line(lines, '=== EXECUTION COUNTERS ===');
rows = report.execution_counters.rows;
lines = append_line(lines, sprintf('counter                          | value       | status'));
for k = 1:numel(rows)
    r = get_row(rows, k);
    lines = append_line(lines, sprintf('%-32s | %11.4g | %s', r.name, r.value, r.status));
end

% Convergence summary
lines = append_line(lines, '');
lines = append_line(lines, '=== CONVERGENCE/FAILURE SUMMARY ===');
rows = report.convergence_summary.rows;
for k = 1:numel(rows)
    r = get_row(rows, k);
    lines = append_line(lines, sprintf('%s: converged=%s', r.analysis, format_val(r.converged)));
end

% analysis_fingerprint
lines = append_line(lines, '');
lines = append_line(lines, '=== ANALYSIS FINGERPRINT ===');
fp = report.analysis_fingerprint;
fns = fieldnames(fp);
for k = 1:numel(fns)
    v = fp.(fns{k});
    lines = append_line(lines, sprintf('%s: %s', fns{k}, format_val(v)));
end

text = strjoin(lines, newline);
end

function lines = append_line(lines, s)
lines{end+1} = s;
end

function r = get_row(rows, k)
% Handle both cell array of structs and struct array.
if iscell(rows)
    r = rows{k};
else
    r = rows(k);
end
end

function s = format_val(v)
if islogical(v)
    s = string(v);
elseif isnumeric(v)
    if isnan(v)
        s = 'NaN';
    else
        s = num2str(v, 6);
    end
elseif ischar(v)
    s = v;
elseif isstring(v)
    s = char(v);
elseif isstruct(v)
    s = '[struct]';
else
    s = char(string(v));
end
end
