function tests = test_identity_reference_handback()
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
tc.addTeardown(@() rmpath(root));
pf_init_paths();
end

function test_only_owner_metadata_changes(tc)
hs = struct('selected_gfm_indices',[2 3],'reference_resource_index',2);
p = struct('x',[1;2],'y',[1;0],'u',[.2;.1], 'V',[1;0], ...
    'I',[.2;-.1], 'P',.2,'Q',-.1);
[out,a] = stability.identity_reference_handback(hs,1,p,p);
tc.verifyEqual(out.selected_gfm_indices,hs.selected_gfm_indices);
tc.verifyEqual(out.reference_owner_indices,1);
tc.verifyTrue(isnan(out.gfm_reference_resource_indices));
tc.verifyEmpty(out.reference_resource_index);
tc.verifyTrue(a.identity_only && a.physical_unchanged);
tc.verifyFalse(a.state_reset || a.angle_rotation || a.kcl_mutation);
end

function test_physical_change_fails_closed(tc)
p = struct('x',1,'y',1);
q = p; q.y = 1+1e-3;
tc.verifyError(@() stability.identity_reference_handback(struct(),1,p,q), ...
    'stability:identity_reference_handback:physicalChange');
end
