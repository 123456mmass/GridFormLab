function tests=test_ibr_support_supervisor_selection
% Pure falsification tests for SG-off AGSI support candidate ranking.
tests=functiontests(localfunctions);
end

function test_augmentation_chooses_smallest_strict_superset_then_margin(tc)
t=table_fixture();
[c,found,a]=stability.select_support_augmentation_candidate(t,5);
tc.verifyTrue(found);
tc.verifyEqual(c.selected_gfm_indices,[3 5]);
tc.verifyEqual(a.reason,'MINIMUM_AUTHENTICATED_FEASIBLE_SUPERSET');
end

function test_augmentation_skips_unready_and_can_jump_to_four(tc)
t=table_fixture();
t.sg_off.configurations(2).ready_to_commit=false;
t.sg_off.configurations(3).feasible=false;
[c,found]=stability.select_support_augmentation_candidate(t,5);
tc.verifyTrue(found);
tc.verifyEqual(c.selected_gfm_indices,[2 3 4 5]);
end

function test_release_keeps_nonempty_minimum_reference_set(tc)
t=table_fixture();
[c,found,a]=stability.select_support_release_candidate(t,[2 3 4 5]);
tc.verifyTrue(found);
tc.verifyEqual(c.selected_gfm_indices,5);
tc.verifyEqual(c.reference_resource_index,5);
tc.verifyEqual(a.reason,'MINIMUM_AUTHENTICATED_FEASIBLE_NONEMPTY_SUBSET');
end

function test_no_release_below_minimum(tc)
t=table_fixture();
[c,found,a]=stability.select_support_release_candidate(t,5);
tc.verifyFalse(found);
tc.verifyEmpty(fieldnames(c));
tc.verifyEqual(a.reason,'NO_STRICT_FEASIBLE_NONEMPTY_SUBSET');
end

function test_set_relation_prevents_unrelated_configuration(tc)
t=table_fixture();
[c,found]=stability.select_support_augmentation_candidate(t,2);
tc.verifyTrue(found);
% [2 5] is the smallest strict feasible superset; the relation rejects the
% unrelated [3 5] tuple but does not require an unnecessary jump to four.
tc.verifyEqual(c.selected_gfm_indices,[2 5]);
[c2,found2]=stability.select_support_release_candidate(t,[2 3]);
tc.verifyFalse(found2);
tc.verifyEmpty(fieldnames(c2));
end

function t=table_fixture()
cfg(1)=candidate(5,5,0.10,true,true);
cfg(2)=candidate([2 5],2,0.20,true,true);
cfg(3)=candidate([3 5],3,0.40,true,true);
cfg(4)=candidate([2 3 4 5],2,2.00,true,true);
% An empty SG-off tuple may exist in diagnostic tables, but release must
% never select it while the SG is offline.
cfg(5)=candidate([],[],3.00,true,true);
t=struct('selector_table_fingerprint','selector_table|test', ...
    'sg_off',struct('configurations',cfg));
end

function c=candidate(selected,ref,margin,feasible,ready)
c=struct('selected_gfm_indices',selected,'n_gfm_required',numel(selected), ...
    'reference_resource_index',ref,'margin',margin, ...
    'feasible',feasible,'ready_to_commit',ready);
end
