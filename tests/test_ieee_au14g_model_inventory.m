function tests = test_ieee_au14g_model_inventory()
%TEST_IEEE_AU14G_MODEL_INVENTORY Track what is required before AU14G counts as accuracy benchmark.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_inventory_identifies_required_models(testCase)
    inv = stability.ieee_au14g_model_inventory(1);
    testCase.verifyEqual(inv.generator_count, 14);
    testCase.verifyEqual(inv.exciter_count, 14);
    gm = string({inv.generator_models.model}); gc = [inv.generator_models.count];
    testCase.verifyEqual(gc(gm=="GENROE"), 12);
    testCase.verifyEqual(gc(gm=="GENSAL"), 2);
    em = string({inv.exciter_models.model}); ec = [inv.exciter_models.count];
    testCase.verifyEqual(ec(em=="ESST1A"), 11);
    testCase.verifyEqual(ec(em=="ESAC1A"), 3);
    testCase.verifyFalse(inv.accuracy_benchmark_ready, ...
        'AU14G must not be marked ready until full parameter-to-A reconstruction is implemented.');
end
