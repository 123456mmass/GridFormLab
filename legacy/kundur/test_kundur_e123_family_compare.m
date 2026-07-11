function tests = test_kundur_e123_family_compare()
%TEST_KUNDUR_E123_FAMILY_COMPARE Validate family-based diagnostic plumbing.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_reference_has_all_printed_roots(testCase)
ref = stability.kundur_e123_reference();
verifyEqual(testCase,numel(ref.eigenvalues),24);
verifyEqual(testCase,ref.families(1).eigenvalues(1),-0.76e-3+1i*0.22e-2);
end

function test_book_flux_spectrum_classifies_without_cross_family_matching(testCase)
r = stability.kundur_ex126_book_flux_ssa();
q = stability.kundur_e123_family_compare(r);
verifyEqual(testCase,numel(q.rows),24);
verifyEqual(testCase,q.rank_A,23);
verifyEqual(testCase,q.rank_A2,22);
verifyLessThan(testCase,q.common_angle_residual,1e-6);
verifyEqual(testCase,sum(strcmp({q.rows.family},'interarea')),2);
verifyEqual(testCase,sum(strcmp({q.rows.family},'q_amortisseur')),4);
verifyEqual(testCase,sum(strcmp({q.rows.family},'d_amortisseur_pairs')),4);
end
