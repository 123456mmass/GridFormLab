function tests = test_kundur_e123_calibrated_diagnostic()
%TEST_KUNDUR_E123_CALIBRATED_DIAGNOSTIC Quarantine the historical fit wrapper.
% The wrapper may remain for retrospective diagnostics only.  It must not
% supply an acceptance result for the physical book reconstruction.
tests = functiontests(localfunctions);
end

function test_wrapper_is_explicitly_marked_calibrated(testCase)
p = which('stability.kundur_ex126_book_e123_ssa');
source = fileread(p);
verifyNotEmpty(testCase,regexp(source,'Calibrated reproduction','once'));
verifyNotEmpty(testCase,regexp(source,'Effective corrections','once'));
verifyNotEmpty(testCase,regexp(source,'book_e123_scale','once'));
end
