function tests = test_multimachine_common_engine()
%TEST_MULTIMACHINE_COMMON_ENGINE Ensure benchmarks use the shared SSA engine.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_kundur_and_sauer_pai_use_common_engine(testCase)
    kundur = stability.kundur_ex126_kundur_ssa();
    sauer = stability.sauer_pai_ex83_ssa();

    testCase.verifyEqual(kundur.metadata.engine, 'stability.multimachine_ssa');
    testCase.verifyEqual(sauer.metadata.engine, 'stability.multimachine_ssa');
    testCase.verifyEqual(numel(kundur.eigenvalues), 24, 'Kundur full system should be 4 machines x 6 states');
    testCase.verifyEqual(numel(sauer.eigenvalues), 21, 'Sauer-Pai full system should be 3 machines x 7 states');
end
