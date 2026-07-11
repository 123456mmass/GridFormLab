function tests = test_coi_weighting()
%TEST_COI_WEIGHTING  Verify the COI frame uses inertia-weighted averaging
%   for BOTH rotor angle and speed (not arithmetic mean). Guards the bug
%   where speed-relative used omega - mean(omega,2).

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_asymmetric_H_arithmetic_mean_differs(testCase)
% With asymmetric H, the inertia-weighted COI must NOT equal the arithmetic
% mean. (If they were equal, the weighting would be a no-op.)
delta = [10 20; 30 40]; omega = [0.01 0.02; 0.03 0.04];
H = [5 10];   % asymmetric
rel = coi_relative(delta, omega, H);
arith_mean_delta = mean(delta,2);
arith_mean_omega = mean(omega,2);
testCase.verifyGreaterThan(max(abs(rel.delta_coi - arith_mean_delta)), 1e-12, ...
    'inertia-weighted delta_coi must differ from arithmetic mean (asymmetric H)');
testCase.verifyGreaterThan(max(abs(rel.omega_coi - arith_mean_omega)), 1e-12, ...
    'inertia-weighted omega_coi must differ from arithmetic mean (asymmetric H)');
end

function test_hand_computed_inertia_weighted_result(testCase)
% Hand-computed check: H=[5 10], delta=[10 20] -> coi = (5*10+10*20)/15 = 250/15.
delta = [10 20]; omega = [0.01 0.02];
H = [5 10];
rel = coi_relative(delta, omega, H);
expected_delta_coi = (5*10 + 10*20) / 15;
expected_omega_coi = (5*0.01 + 10*0.02) / 15;
testCase.verifyEqual(rel.delta_coi(1), expected_delta_coi, 'AbsTol', 1e-12, ...
    'delta_coi = sum(H.*delta)/sum(H) (hand-computed)');
testCase.verifyEqual(rel.omega_coi(1), expected_omega_coi, 'AbsTol', 1e-12, ...
    'omega_coi = sum(H.*omega)/sum(H) (hand-computed)');
testCase.verifyEqual(rel.delta_rel(1,1), 10 - expected_delta_coi, 'AbsTol', 1e-12, ...
    'delta_rel = delta - delta_coi');
testCase.verifyEqual(rel.omega_rel(1,2), 0.02 - expected_omega_coi, 'AbsTol', 1e-12, ...
    'omega_rel = omega - omega_coi');
end

function test_column_order_invariant_after_bus_mapping(testCase)
% Reordering generator columns must give the same COI after mapping by bus
% ID (the COI is a physical quantity, independent of column order).
H = [5 10 8]; gbus = [1 3 6];
delta = [1 2 3; 4 5 6]; omega = [0.001 0.002 0.003; 0.004 0.005 0.006];
rel1 = coi_relative(delta, omega, H, gbus);
% Permute columns 1<->3.
perm = [3 1 2];
rel2 = coi_relative(delta(:,perm), omega(:,perm), H(perm), gbus(perm));
testCase.verifyEqual(rel1.delta_coi, rel2.delta_coi, 'AbsTol', 1e-12, ...
    'delta_coi invariant under column permutation (bus-ID mapping)');
testCase.verifyEqual(rel1.omega_coi, rel2.omega_coi, 'AbsTol', 1e-12, ...
    'omega_coi invariant under column permutation (bus-ID mapping)');
end

function test_common_shift_removed(testCase)
% A common shift in all angles/speeds must be removed by the COI frame.
H = [5 10 8];
delta = [1 2 3; 4 5 6]; omega = [0.01 0.02 0.03; 0.04 0.05 0.06];
shift_d = 7.3; shift_w = 0.123;
rel = coi_relative(delta + shift_d, omega + shift_w, H);
testCase.verifyLessThan(max(abs(rel.delta_rel - (delta - sum(delta.*H,2)/sum(H)))), 1e-12, ...
    'common angle shift removed');
testCase.verifyLessThan(max(abs(rel.omega_rel - (omega - sum(omega.*H,2)/sum(H)))), 1e-12, ...
    'common speed shift removed');
end

function test_coi_weighted_sum_of_relative_near_zero(testCase)
% sum(H .* delta_rel) must be ~0 (definition of COI).
H = [5 10 8];
delta = [1 2 3; 4 5 6]; omega = [0.01 0.02 0.03; 0.04 0.05 0.06];
rel = coi_relative(delta, omega, H);
Hb = repmat(H, size(delta,1), 1);
testCase.verifyLessThan(max(abs(sum(Hb .* rel.delta_rel, 2))), 1e-12, ...
    'sum(H.*delta_rel) ~ 0');
testCase.verifyLessThan(max(abs(sum(Hb .* rel.omega_rel, 2))), 1e-12, ...
    'sum(H.*omega_rel) ~ 0');
end
