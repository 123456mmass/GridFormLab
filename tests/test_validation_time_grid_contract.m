function tests = test_validation_time_grid_contract()
%TEST_VALIDATION_TIME_GRID_CONTRACT  Verify the time-grid semantics separate
%   raw_grid_equal, comparison_grid_valid, coverage_valid, event_grid_valid.
%   PSAT (1509 pts) vs Ours (1501 pts) must give raw_grid_equal=false, but a
%   valid comparison grid with coverage still passes the comparison gate.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_raw_grids_unequal_when_counts_differ(testCase)
% PSAT 1509 vs Ours 1501 -> raw_grid_equal must be false.
tg = (0:0.01:15).';            % 1501 points
t_psat = [tg(1:110); tg(110:end)+0.005];  % 1502 points (extra event sample)
info = validate_time_grid(t_psat, tg, 1.0, 1.1);
testCase.verifyFalse(info.raw_grid_equal, 'raw grids unequal (1502 vs 1501) must be false');
testCase.verifyEqual(info.raw_nt, 1502);
testCase.verifyEqual(info.common_nt, 1501);
end

function test_different_raw_but_covering_common_passes_comparison(testCase)
% Raw grids differ but the raw trajectory covers the common grid ->
% comparison_grid_valid and coverage_valid are true (interpolation allowed).
tg = (0:0.01:15).';
t_psat = [tg(1:110); tg(110:end)+0.005];
info = validate_time_grid(t_psat, tg, 1.0, 1.1);
testCase.verifyTrue(info.comparison_grid_valid, 'comparison grid valid');
testCase.verifyTrue(info.coverage_valid, 'raw covers common grid');
testCase.verifyTrue(info.event_grid_valid, 'event timestamps on grid');
end

function test_raw_shorter_than_common_fails_coverage(testCase)
tg = (0:0.01:15).';
t_short = (0:0.01:10).';   % raw ends at 10, common ends at 15
info = validate_time_grid(t_short, tg, 1.0, 1.1);
testCase.verifyFalse(info.coverage_valid, 'raw shorter than common -> coverage fails');
end

function test_missing_event_timestamp_fails(testCase)
tg = (0:0.01:15).';
% A grid that ends before t_clear=1.1 cannot contain the clear event.
tg_bad = (0:0.01:1.0).';
info = validate_time_grid(tg_bad, tg_bad, 1.0, 1.1);
testCase.verifyFalse(info.event_grid_valid, 'grid ending before t_clear -> event_grid fails');
end

function test_raw_grid_equal_when_identical(testCase)
tg = (0:0.01:15).';
info = validate_time_grid(tg, tg, 1.0, 1.1);
testCase.verifyTrue(info.raw_grid_equal, 'identical grids -> raw_grid_equal true');
end
