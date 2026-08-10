function tests = test_c1_smoothstep_handback()
%TEST_C1_SMOOTHSTEP_HANDBACK  Pure oracle for the staged handback schedule.
%   The cubic is an algebraic PROJECT_DERIVED contract; this test does not
%   assert a trajectory or tune a controller threshold.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
tc.addTeardown(@() rmpath(root));
pf_init_paths();
end

function test_endpoints_derivatives_and_monotonicity(tc)
t = linspace(-1,3,1001);
[a,ad,s] = stability.c1_smoothstep(t,0,2);
tc.verifyEqual(a(1),0,'AbsTol',0);
tc.verifyEqual(a(end),1,'AbsTol',0);
tc.verifyEqual(ad(1),0,'AbsTol',0);
tc.verifyEqual(ad(end),0,'AbsTol',0);
tc.verifyEqual(a(t==0),0,'AbsTol',0);
tc.verifyEqual(a(t==2),1,'AbsTol',0);
tc.verifyEqual(ad(t==0),0,'AbsTol',0);
tc.verifyEqual(ad(t==2),0,'AbsTol',0);
tc.verifyTrue(all(diff(a)>=-10*eps));
tc.verifyTrue(all(s>=0 & s<=1));
end

function test_invalid_duration_fails_closed(tc)
tc.verifyError(@() stability.c1_smoothstep(0,0,0), ...
    'stability:c1_smoothstep:badDuration');
tc.verifyError(@() stability.c1_smoothstep(NaN,0,1), ...
    'stability:c1_smoothstep:badTime');
end
