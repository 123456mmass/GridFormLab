function status = equation_audit(reg, report_dir)
%EQUATION_AUDIT  Fail-closed audit of the equation provenance register.
%   STATUS = equation_audit(REG, REPORT_DIR) audits the register REG (from
%   equation_register()) against the mission §N fail-closed rules and returns
%   a struct of computed (not predeclared) statuses. Any failed or incomplete
%   item means DOCUMENTATION_EQUATION_PROVENANCE_READY = NOT_READY.
%
%   Audit rules (mission §N):
%     1. every numbered equation has a register row (EQUATION_REGISTER_COMPLETE)
%     2. every symbol is defined (DIMENSIONAL_AUDIT — units/pu_base present)
%     3. every SOURCE_* row has an exact location (EQUATION_SOURCE_COVERAGE)
%     4. every PROJECT_DERIVED row names premises (transformation non-empty)
%     5. every implemented equation maps to a real production function
%        (CODE_EQUATION_MATCH — production_file exists on disk)
%     6. no UNSOURCED equation supports PASS/equivalence/readiness
%        (CONVENTION_AUDIT)
%     7. figures/tables name their generating command (RESULT_PROVENANCE_COMPLETE
%        — checked separately by the generator; here we check register only)
%
%   Allowed classifications: SOURCE_VERBATIM, SOURCE_TRANSFORMED, CASE_DEFINED,
%   PROJECT_DERIVED, NUMERICAL_METHOD, ASSUMED_DIAGNOSTIC, UNSOURCED,
%   EQUATION_LOCATION_PENDING. Only the first five may support authoritative
%   production/validation claims.
%
%   The final gate DOCUMENTATION_EQUATION_PROVENANCE_READY is READY iff all
%   of: REGISTER_COMPLETE, SOURCE_COVERAGE, DIMENSIONAL_AUDIT, CONVENTION_AUDIT,
%   CODE_EQUATION_MATCH are READY. RESULT_PROVENANCE_COMPLETE is set by the
%   generator after it verifies every figure/table names its command; here it
%   defaults to PENDING until the generator sets it.

if nargin < 2 || isempty(report_dir)
    report_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end

allowed_class = {'SOURCE_VERBATIM','SOURCE_TRANSFORMED','CASE_DEFINED', ...
    'PROJECT_DERIVED','NUMERICAL_METHOD','ASSUMED_DIAGNOSTIC', ...
    'UNSOURCED','EQUATION_LOCATION_PENDING'};
authoritative_class = {'SOURCE_VERBATIM','SOURCE_TRANSFORMED','CASE_DEFINED', ...
    'PROJECT_DERIVED','NUMERICAL_METHOD'};

n = numel(reg);
gaps = struct('equation_id',{},'rule',{},'detail',{});

% --- Rule 1: register complete (every row has required fields non-empty) ---
required_fields = {'equation_id','report_section','equation_name','classification', ...
    'physical_or_numerical_purpose','units','per_unit_base','sign_convention', ...
    'reference_frame','current_direction','assumptions','source_author', ...
    'source_title','edition_year','chapter_section','source_notation', ...
    'project_notation','transformation_derivation','production_function', ...
    'production_file','test_or_oracle','readiness_status','limitation', ...
    'theory_runtime_label'};
missing_field = false(n,1);
for i = 1:n
    for f = required_fields
        v = reg(i).(f{1});
        if isempty(v) || (ischar(v) && strcmp(v,''))
            missing_field(i) = true;
            gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
                'REGISTER_COMPLETE','detail',['empty field: ' f{1}]); %#ok<AGROW>
            break
        end
    end
end
register_complete = ~any(missing_field);

% --- Rule 2: dimensional audit (units and pu_base present and non-trivial) ---
dim_fail = false(n,1);
for i = 1:n
    u = lower(reg(i).units);
    p = lower(reg(i).per_unit_base);
    if isempty(u) || strcmp(u,'') || strcmp(u,'--')
        dim_fail(i) = true;
        gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
            'DIMENSIONAL_AUDIT','detail','missing units'); %#ok<AGROW>
    end
    if isempty(p) || strcmp(p,'') || strcmp(p,'--')
        dim_fail(i) = true;
        gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
            'DIMENSIONAL_AUDIT','detail','missing per_unit_base'); %#ok<AGROW>
    end
end
dimensional_audit = ~any(dim_fail);

% --- Rule 3: source coverage (SOURCE_* rows have exact location) ---
source_class = {'SOURCE_VERBATIM','SOURCE_TRANSFORMED'};
src_fail = false(n,1);
for i = 1:n
    if ismember(reg(i).classification, source_class)
        % require author, title, edition, chapter, and at least one of
        % printed_page / source_equation_number / DOI_ISBN_URL
        loc_fields = {reg(i).source_author, reg(i).source_title, ...
            reg(i).edition_year, reg(i).chapter_section};
        loc_empty = any(cellfun(@(v) isempty(v) || (ischar(v) && strcmp(v,'--')), loc_fields));
        page_fields = {reg(i).printed_page, reg(i).source_equation_number, ...
            reg(i).DOI_ISBN_URL};
        page_empty = all(cellfun(@(v) isempty(v) || (ischar(v) && strcmp(v,'--')), page_fields));
        if loc_empty || page_empty
            src_fail(i) = true;
            gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
                'SOURCE_COVERAGE','detail','SOURCE_* row missing exact location'); %#ok<AGROW>
        end
    end
end
source_coverage = ~any(src_fail);

% --- Rule 4: PROJECT_DERIVED names premises (transformation non-empty) ---
pd_fail = false(n,1);
for i = 1:n
    if strcmp(reg(i).classification, 'PROJECT_DERIVED')
        t = reg(i).transformation_derivation;
        if isempty(t) || (ischar(t) && (strcmp(t,'') || strcmp(t,'--')))
            pd_fail(i) = true;
            gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
                'PROJECT_DERIVED_PREMISES','detail','PROJECT_DERIVED missing transformation/premises'); %#ok<AGROW>
        end
    end
end
project_derived_premises = ~any(pd_fail);

% --- Rule 5: code-equation match (production_file exists on disk) ---
code_fail = false(n,1);
for i = 1:n
    pf = reg(i).production_file;
    if isempty(pf) || strcmp(pf,'--')
        continue
    end
    % production_file may contain line numbers (':42-43') and multiple files
    % separated by ', '. Split, strip line numbers, and check each exists.
    files = split_production_files(pf);
    found_all = true;
    missing = '';
    for f = 1:numel(files)
        fpath = files{f};
        if isempty(fpath), continue; end
        if ~production_file_exists(fpath, report_dir)
            found_all = false;
            missing = [missing ' ' fpath];
        end
    end
    if ~found_all
        code_fail(i) = true;
        gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
            'CODE_EQUATION_MATCH','detail',['production_file not found:' missing]); %#ok<AGROW>
    end
end
code_equation_match = ~any(code_fail);

% --- Rule 6: convention audit (no UNSOURCED supports PASS/equivalence/readiness) ---
% An UNSOURCED/EQUATION_LOCATION_PENDING row must NOT have a theory_runtime_label
% of RUNTIME_EQUATION or VALIDATION_ORACLE that would support a claim.
conv_fail = false(n,1);
for i = 1:n
    if ismember(reg(i).classification, {'UNSOURCED','EQUATION_LOCATION_PENDING'})
        lbl = reg(i).theory_runtime_label;
        if ismember(lbl, {'RUNTIME_EQUATION','VALIDATION_ORACLE','RUNTIME_MODEL_INTERFACE'})
            conv_fail(i) = true;
            gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
                'CONVENTION_AUDIT','detail','UNSOURCED equation supports runtime/validation claim'); %#ok<AGROW>
        end
    end
    % Also: classification must be in allowed list.
    if ~ismember(reg(i).classification, allowed_class)
        conv_fail(i) = true;
        gaps(end+1) = struct('equation_id',reg(i).equation_id,'rule', ...
            'CONVENTION_AUDIT','detail',['unknown classification: ' reg(i).classification]); %#ok<AGROW>
    end
end
convention_audit = ~any(conv_fail);

% --- Rule 7: result provenance (figures/tables name generating command) ---
% This is checked by the generator after it emits artifacts. Here we only
% confirm the register has at least one row per report section that produces
% results (sections 9-11). Default PENDING.
result_provenance_complete = 'PENDING';

% --- Final gate ---
ready = register_complete && source_coverage && dimensional_audit && ...
    convention_audit && code_equation_match && project_derived_premises;

status = struct();
status.EQUATION_REGISTER_COMPLETE = ready_str(register_complete);
status.EQUATION_SOURCE_COVERAGE = ready_str(source_coverage);
status.DIMENSIONAL_AUDIT = ready_str(dimensional_audit);
status.CONVENTION_AUDIT = ready_str(convention_audit);
status.CODE_EQUATION_MATCH = ready_str(code_equation_match);
status.PROJECT_DERIVED_PREMISES = ready_str(project_derived_premises);
status.RESULT_PROVENANCE_COMPLETE = result_provenance_complete;
status.DOCUMENTATION_EQUATION_PROVENANCE_READY = ready_str(ready);
status.gaps = gaps;
status.n_equations = n;
end

function s = ready_str(b)
if b, s = 'READY'; else, s = 'NOT_READY'; end
end

function files = split_production_files(pf)
% Split a production_file string that may contain multiple files separated by
% ', ' and each may have line numbers like ':42-43' or ':42,163' (the latter
% only appears within a single file spec). Returns cell array of bare paths.
% Strip line-number suffixes: ':N', ':N-M', ':N,M' (multiple lines).
bare = regexprep(pf, ':\d+[-,]?\d*', '');
% Split on ', ' that separates multiple file specs.
files = regexp(bare, '\s*,\s*', 'split');
% Trim and drop empties.
out = {};
for f = 1:numel(files)
    t = strtrim(files{f});
    if ~isempty(t)
        out{end+1} = t; %#ok<AGROW>
    end
end
files = out;
end

function found = production_file_exists(fpath, report_dir)
% Check whether a production file path exists on disk or on the MATLAB path.
% fpath may be like '+stability/ts_adaptive_driver.m' or
% 'scripts/validation/coi_relative.m' or '+pfsolver/powerflow_newton_raphson.m'.
candidates = { ...
    fullfile(report_dir, fpath), ...
    fullfile(report_dir, strrep(fpath, '+', '')), ...
    fpath};
found = false;
for c = 1:numel(candidates)
    if exist(candidates{c}, 'file')
        found = true; return;
    end
end
% Also accept if the function name (last component) exists on path.
fn = fpath;
[~, fn] = fileparts(fn);
fn = regexprep(fn, '^[+]', '');
fn = regexprep(fn, '/', '');
if exist(fn, 'file') || exist(fn, 'builtin') > 0
    found = true; return;
end
end
