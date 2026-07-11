function tests = test_kundur_zero_mode_structure()
%TEST_KUNDUR_ZERO_MODE_STRUCTURE Verify Kundur's two redundant states.
% With no infinite bus, no governor, and K_D=0, the common rotor-angle
% direction is a zero eigenvector.  The common-speed direction is its
% generalized eigenvector, so the zero eigenvalue has algebraic multiplicity
% two but geometric multiplicity one (a size-two Jordan chain).  Therefore
% an SVD of A alone must not be used to reject the second zero mode.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_common_angle_is_null_direction(testCase)
% Structural property of the autonomous EMF6 DAE (no infinite bus, no
% governor, K_D=0): a common rotor-angle rotation leaves it unchanged.
r = stability.synchronous_emf6_ssa(cases.kundur_ex126_book_case(), ...
    struct('load_model','cc_p_cz_q'));
A = r.Afull;
vangle = zeros(size(A,1),1);
vangle(1:6:end) = 1;

testCase.verifyLessThan(norm(A*vangle), 1e-7, ...
    'A common rotation must leave the autonomous DAE unchanged.');
end

function test_zero_mode_has_jordan_chain(testCase)
% The common-angle zero eigenvalue has algebraic multiplicity two but
% geometric multiplicity one (a size-two Jordan chain): A has one null
% vector while A^2 has two. Verified on the operational EMF6 model.
r = stability.synchronous_emf6_ssa(cases.kundur_ex126_book_case(), ...
    struct('load_model','cc_p_cz_q'));
A = r.Afull;
testCase.verifyEqual(rank(A,1e-6), 23);
testCase.verifyEqual(rank(A*A,1e-6), 22);
end
