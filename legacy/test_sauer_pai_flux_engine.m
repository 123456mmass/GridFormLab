function tests = test_sauer_pai_flux_engine()
%TEST_SAUER_PAI_FLUX_ENGINE Contract tests for the generic flux-state engine.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_pf_preserving_equilibrium_and_dae_structure(testCase)
case_data = cases.kundur_ex126_book_case();
r = stability.sauer_pai_flux_ssa(case_data, struct('fd_eps', 3e-6));

verifyEqual(testCase, numel(r.eigenvalues), 24);
verifyLessThan(testCase, norm(r.debug_residual_f, inf), 1e-8);
verifyLessThan(testCase, norm(r.debug_residual_g, inf), 1e-8);
verifyLessThan(testCase, r.angle_shift_residual, 1e-6);
verifyEqual(testCase, r.equilibrium_solver, 'fsolve');
verifyGreaterThanOrEqual(testCase, r.newton_iterations, 0);
end

function test_case_data_drives_the_generic_engine(testCase)
case_data = cases.kundur_ex126_book_case();
base = stability.sauer_pai_flux_ssa(case_data, struct('fd_eps', 3e-6));

perturbed_case = case_data;
perturbed_case.system_name = 'Perturbed generic flux-engine case';
perturbed_case.machines.units(1).H = 1.01 * perturbed_case.machines.units(1).H;
perturbed = stability.sauer_pai_flux_ssa(perturbed_case, struct('fd_eps', 3e-6));

verifyLessThan(testCase, norm(perturbed.debug_residual_f, inf), 1e-8);
verifyLessThan(testCase, norm(perturbed.debug_residual_g, inf), 1e-8);
verifyGreaterThan(testCase, norm(perturbed.Afull - base.Afull, 'fro'), 1e-6, ...
    'Changing case data must change the assembled state matrix.');
end
