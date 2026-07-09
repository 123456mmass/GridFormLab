function tests = test_kundur_book_flux_path()
%TEST_KUNDUR_BOOK_FLUX_PATH Guardrails for the independent book-flux path.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_unsaturated_flux_equations_recover_legacy_limit(testCase)
opt = struct('load_model','cc_p_cz_q','use_saturation',false);
legacy = stability.kundur_ex126_kundur_ssa('options',opt);
flux = stability.kundur_ex126_book_flux_ssa('options',opt);
testCase.verifyLessThan(norm(flux.debug_residual_f), 1e-8);
testCase.verifyLessThan(norm(flux.debug_residual_g), 1e-8);
testCase.verifyLessThan(norm(flux.Afull-legacy.Afull,'fro'), 1e-6, ...
    'Flux reconstruction must reduce exactly to the unsaturated E'' model.');
end

function test_book_flux_saturation_has_consistent_equilibrium(testCase)
flux = stability.kundur_ex126_book_flux_ssa();
testCase.verifyEqual(flux.init.newton_iterations, 0, ...
    'Initialization must preserve the verified PF operating point; no DAE/PF refinement is allowed.');
testCase.verifyLessThan(flux.newton_residual, 1e-8);
testCase.verifyTrue(all(isfinite(flux.eigenvalues)));
end
