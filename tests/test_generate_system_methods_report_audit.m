function tests = test_generate_system_methods_report_audit
%TEST_GENERATE_SYSTEM_METHODS_REPORT_AUDIT MATLAB unit-test entry point.
tests = functiontests(localfunctions);
end

function test_equation_provenance_audit(~)
%TEST_GENERATE_SYSTEM_METHODS_REPORT_AUDIT  Fail-closed equation provenance audit.
%   Verifies that equation_register() + equation_audit() satisfy the mission
%   §N fail-closed rules: every equation has a register row, every symbol is
%   defined, every SOURCE_* row has an exact location, every PROJECT_DERIVED
%   names premises, every implemented equation maps to a real production
%   function, and no UNSOURCED equation supports a PASS/equivalence/readiness
%   claim. The final gate DOCUMENTATION_EQUATION_PROVENANCE_READY must be READY.

reg = equation_register();

% --- 1. Register is non-empty and covers all required chains ---
assert(~isempty(reg), 'equation_register returned empty.');
ids = {reg.equation_id};
chains = {'PF-','SG-C-','SG-P-','SG-E-','SSSA-','TS-F-','TS-A-','LFN-','CMP-'};
for c = 1:numel(chains)
    cnt = sum(startsWith(ids, chains{c}));
    assert(cnt > 0, ['No equations for chain ' chains{c}]);
end
fprintf('Register: %d equations across %d chains.\n', numel(reg), numel(chains));

% --- 2. Every equation ID is unique ---
assert(numel(unique(ids)) == numel(ids), 'Duplicate equation IDs in register.');

% --- 3. Audit passes (the real gate) ---
status = equation_audit(reg);
fprintf('Audit gates:\n');
gates = {'EQUATION_REGISTER_COMPLETE','EQUATION_SOURCE_COVERAGE', ...
    'DIMENSIONAL_AUDIT','CONVENTION_AUDIT','CODE_EQUATION_MATCH', ...
    'PROJECT_DERIVED_PREMISES','DOCUMENTATION_EQUATION_PROVENANCE_READY'};
for g = 1:numel(gates)
    fprintf('  %s = %s\n', gates{g}, status.(gates{g}));
end
assert(strcmp(status.DOCUMENTATION_EQUATION_PROVENANCE_READY, 'READY'), ...
    ['Equation provenance NOT_READY. Gaps:\n' format_gaps(status.gaps)]);

% --- 4. No UNSOURCED equation supports a runtime/validation claim ---
for i = 1:numel(reg)
    if ismember(reg(i).classification, {'UNSOURCED','EQUATION_LOCATION_PENDING'})
        assert(~ismember(reg(i).theory_runtime_label, ...
            {'RUNTIME_EQUATION','VALIDATION_ORACLE','RUNTIME_MODEL_INTERFACE'}), ...
            ['UNSOURCED equation ' reg(i).equation_id ' supports a claim.']);
    end
end

% --- 5. Negative test: a register with an UNSOURCED+RUNTIME row must fail ---
bad = reg(1);
bad.classification = 'UNSOURCED';
bad.theory_runtime_label = 'RUNTIME_EQUATION';
bad_reg = [reg; bad];
bad_status = equation_audit(bad_reg);
assert(strcmp(bad_status.CONVENTION_AUDIT, 'NOT_READY'), ...
    'Audit failed to detect UNSOURCED+RUNTIME_EQUATION.');
assert(strcmp(bad_status.DOCUMENTATION_EQUATION_PROVENANCE_READY, 'NOT_READY'), ...
    'Final gate failed to close on UNSOURCED runtime claim.');

% --- 6. Negative test: a register with a missing production_file must fail ---
bad2 = reg(1);
bad2.production_file = '+stability/nonexistent_file_xyz.m';
bad2_reg = [reg; bad2];
bad2_status = equation_audit(bad2_reg);
assert(strcmp(bad2_status.CODE_EQUATION_MATCH, 'NOT_READY'), ...
    'Audit failed to detect nonexistent production_file.');

% --- 7. Export artifacts can be generated without error ---
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@()rmdir(tmp,'s'));
equation_register_export(tmp);
assert(exist(fullfile(tmp,'equation_provenance.csv'),'file') == 2, 'CSV not written.');
assert(exist(fullfile(tmp,'table_equation_provenance.tex'),'file') == 2, 'TeX not written.');
assert(exist(fullfile(tmp,'equation_source_gaps.tex'),'file') == 2, 'gaps TeX not written.');
fprintf('Export artifacts written and verified in %s\n', tmp);

fprintf('test_generate_system_methods_report_audit: PASS\n');
end

function s = format_gaps(gaps)
s = '';
for i = 1:numel(gaps)
    s = [s sprintf('  %s [%s]: %s\n', gaps(i).equation_id, gaps(i).rule, gaps(i).detail)];
end
end
