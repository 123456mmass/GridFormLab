function tests = test_interpolation_no_extrapolation()
%TEST_INTERPOLATION_NO_EXTRAPOLATION  Verify interpolation never zero-fills
%   or extrapolates. Out-of-range common grid -> error (gate fails). NaN in
%   result -> error. Guards the bug where interp1(...,0) created fake values.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_in_range_interpolation_succeeds(testCase)
t_raw = (0:0.005:1).'; y_raw = sin(t_raw);
tg = (0:0.01:1).';
y = interp_no_extrapolate(t_raw, y_raw, tg);
testCase.verifyEqual(size(y,1), numel(tg), 'output length matches common grid');
testCase.verifyTrue(all(isfinite(y(:))), 'all finite');
end

function test_common_grid_beyond_raw_errors(testCase)
% Common grid extends past raw -> must error (no zero-fill extrapolation).
t_raw = (0:0.01:1).'; y_raw = sin(t_raw);
tg = (0:0.01:1.5).';   % extends to 1.5, raw only to 1.0
testCase.verifyError(@() interp_no_extrapolate(t_raw, y_raw, tg), ...
    'interp_no_extrapolate:coverage', 'out-of-range must error, not zero-fill');
end

function test_common_grid_before_raw_errors(testCase)
t_raw = (0.5:0.01:1.5).'; y_raw = sin(t_raw);
tg = (0:0.01:1).';   % starts at 0, raw starts at 0.5
testCase.verifyError(@() interp_no_extrapolate(t_raw, y_raw, tg), ...
    'interp_no_extrapolate:coverage', 'before-range must error');
end

function test_nan_in_raw_propagates_as_error(testCase)
t_raw = (0:0.01:1).'; y_raw = sin(t_raw); y_raw(5) = NaN;
tg = (0:0.01:1).';
testCase.verifyError(@() interp_no_extrapolate(t_raw, y_raw, tg), ...
    'interp_no_extrapolate:nan', 'NaN in result must error');
end

function test_no_zero_fill_artifact(testCase)
% Explicitly verify the old zero-fill behavior is gone: a value just past
% the raw range must NOT return 0; it must error.
t_raw = [0; 1]; y_raw = [0; 1];
testCase.verifyError(@() interp_no_extrapolate(t_raw, y_raw, [0; 0.5; 1.0001]), ...
    'interp_no_extrapolate:coverage', 'no silent 0 fill past range');
end
