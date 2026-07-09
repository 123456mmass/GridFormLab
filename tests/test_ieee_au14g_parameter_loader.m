function tests = test_ieee_au14g_parameter_loader()
%TEST_IEEE_AU14G_PARAMETER_LOADER Ensure AU14G validation starts from parameters.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_case01_raw_dyr_parameters_parse(testCase)
    c = cases.ieee_au14g_case(1);
    testCase.verifyEqual(c.sbase, 100);
    testCase.verifyGreaterThan(numel(c.raw.buses), 50);
    testCase.verifyEqual(c.generator_count, 14, ...
        'AU14G should parse 14 synchronous generator dynamic records, excluding SVC records.');
    models = string({c.dyn.generators.model});
    testCase.verifyEqual(sum(models == "GENSAL"), 2);
    testCase.verifyEqual(sum(models == "GENROE"), 12);
    testCase.verifyEqual(numel(c.dyn.exciters), 14);
    testCase.verifyTrue(all(ismember(string({c.dyn.exciters.model}), ["ESST1A","ESAC1A"])));
    testCase.verifyGreaterThanOrEqual(numel(c.dyn.pss), 10);
end

function test_loader_does_not_use_published_state_space(testCase)
    src = fileread(which('cases.ieee_au14g_case'));
    testCase.verifyFalse(contains(src, 'ABCD_Rev3_Matlab'));
    testCase.verifyFalse(contains(src, 'Eigs_Rev3_Matlab'));
    testCase.verifyTrue(contains(src, 'PSSE_DYN_Case'));
    testCase.verifyTrue(contains(src, 'LF_Case'));
end
