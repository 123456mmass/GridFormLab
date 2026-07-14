function tests = test_sssa_launcher_eigenvalue_table()
%TEST_SSSA_LAUNCHER_EIGENVALUE_TABLE  Complete, ordered SSSA display contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
cd(root);
pf_init_paths;
txt = evalc(['launcher_result = solve_case(''analysis'',''sssa'',' ...
    '''case'',''padiyar_two_area'',''options'',' ...
    'struct(''verbose'',false,''fd_eps'',1e-6));']);
testCase.TestData.text = txt;
testCase.TestData.launcher_result = launcher_result;
testCase.TestData.rows = extract_table_rows(txt);
rts_text = evalc([ ...
    'rts_result = solve_case(''analysis'',''sssa'',' ...
    '''case'',''rts24'',''options'',struct(''verbose'',false));']);
testCase.TestData.rts_text = rts_text;
testCase.TestData.rts_result = rts_result;
testCase.TestData.rts_rows = extract_table_rows(rts_text);
end

function test_all_twenty_roots_are_printed(testCase)
rows = testCase.TestData.rows;
testCase.verifyNumElements(rows, 20, ...
    'The launcher must print one row per eigenvalue, including both conjugates.');
for k = 1:20
    token = regexp(rows{k}, '^\s*(\d+)\s+', 'tokens', 'once');
    testCase.verifyNotEmpty(token);
    testCase.verifyEqual(str2double(token{1}), k);
end
end

function test_two_decimal_scientific_notation(testCase)
% Real, imaginary, frequency, and damping columns all use x.xx e +/-yy.
rows = testCase.TestData.rows;
number_pattern = '[+-]?\d\.\d{2}e[+-]\d{2}';
for k = 1:numel(rows)
    values = regexp(rows{k}, number_pattern, 'match');
    testCase.verifyNumElements(values, 4, ...
        sprintf('row %d must contain four two-decimal scientific values', k));
end
end

function test_padiyar_reference_row_order(testCase)
rows = testCase.TestData.rows;
testCase.verifySubstring(testCase.TestData.text, ...
    'Display order   : Padiyar Table 9.5 one-to-one match (diagnostic only)');
testCase.verifySubstring(rows{1},  '-4.00e+01');
testCase.verifySubstring(rows{2},  '-3.95e+01');
testCase.verifySubstring(rows{15}, '-4.57e+00');
testCase.verifySubstring(rows{20}, '-4.24e+00');
end

function test_conjugates_and_mode_labels_are_not_collapsed(testCase)
rows = testCase.TestData.rows;
testCase.verifySubstring(rows{9},  '+7.32e+00');
testCase.verifySubstring(rows{9},  'Swing 1');
testCase.verifySubstring(rows{10}, '-7.32e+00');
testCase.verifySubstring(rows{10}, 'Swing 1');
testCase.verifySubstring(rows{11}, '+6.71e+00');
testCase.verifySubstring(rows{11}, 'Swing 2');
testCase.verifySubstring(rows{12}, '-6.71e+00');
testCase.verifySubstring(rows{12}, 'Swing 2');
testCase.verifySubstring(rows{13}, '+4.46e+00');
testCase.verifySubstring(rows{13}, 'Inter-area');
testCase.verifySubstring(rows{14}, '-4.46e+00');
testCase.verifySubstring(rows{14}, 'Inter-area');
testCase.verifySubstring(rows{18}, '+3.66e-05');
testCase.verifySubstring(rows{18}, 'reference/gauge');
testCase.verifySubstring(rows{19}, '-3.66e-05');
testCase.verifySubstring(rows{19}, 'reference/gauge');
end

function test_display_does_not_change_computed_eigenvalue_set(testCase)
c = cases.case_padiyar_two_area_4m_avr();
direct = stability.padiyar_model11_ssa(c, ...
    struct('excitation','avr','fd_eps',1e-6));
launcher = testCase.TestData.launcher_result;
got = sortrows([real(launcher.eigenvalues(:)), imag(launcher.eigenvalues(:))]);
expected = sortrows([real(direct.eigenvalues(:)), imag(direct.eigenvalues(:))]);
testCase.verifyEqual(got, expected, 'AbsTol', 1e-12);
testCase.verifyEqual(launcher.Afull, direct.Afull, 'AbsTol', 1e-12);
end

function test_coi_case_still_prints_full_state_eigenvalues(testCase)
% RTS-24 has 22 full states and 20 COI-relative decision roots. The only
% eigenvalue table must contain all 22 full roots; the reduced count is
% metadata, not a replacement table.
testCase.verifyEqual(numel(testCase.TestData.rts_result.eigenvalues), 22);
testCase.verifyEqual(numel(testCase.TestData.rts_result.reduced_eigenvalues), 20);
testCase.verifyNumElements(testCase.TestData.rts_rows, 22);
testCase.verifySubstring(testCase.TestData.rts_text, 'FULL STATE EIGENVALUES');
testCase.verifySubstring(testCase.TestData.rts_text, ...
    'Decision basis  : COI-relative set (20 roots)');
testCase.verifySubstring(testCase.TestData.rts_text, ...
    'Eigenvalue set  : 22 roots');
testCase.verifyFalse(contains(testCase.TestData.rts_text, ...
    'COI-REDUCED RELATIVE MODES'));
end

function rows = extract_table_rows(txt)
header = '  No  Dominant state';
i0 = strfind(txt, header);
if isempty(i0)
    rows = {};
    return;
end
block = txt(i0(end):end);
i1 = strfind(block, sprintf('\nSTATUS:'));
if ~isempty(i1), block = block(1:i1(1)-1); end
lines = cellstr(splitlines(string(block)));
is_row = ~cellfun('isempty', regexp(lines, '^\s+\d+\s+', 'once'));
rows = lines(is_row);
rows = rows(:);
end
