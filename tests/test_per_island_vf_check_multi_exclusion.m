function tests = test_per_island_vf_check_multi_exclusion()
%TEST_PER_ISLAND_VF_CHECK_MULTI_EXCLUSION  One gate, now excluding a LIST.
%   per_island_vf_check answers one question: after a device leaves service,
%   does every energized island still hold an online voltage-forming source? The
%   departing device must never be allowed to answer it about itself, which is
%   what the exclusion argument is for.
%
%   The argument was one SG ID. A converter outage needs the same gate for the
%   same reason, and a run can have BOTH a breaker-open machine and an outgoing
%   converter, so the argument became a list. That generalization is only safe if
%   two things hold, and this file falsifies both:
%
%     1. Every ID in the list is really excluded. If only the first were honoured
%        a converter outage would be certified by the very converter it removes,
%        which is the whole failure the gate exists to prevent.
%     2. The historical scalar call is UNCHANGED. trip_transaction still passes
%        one char SG ID (ts_simulate_ibr_hybrid.m:2168-2169) and
%        test_ieee14_ibr_sg_on_integration.m still asserts on that form, so a
%        scalar must remain exactly equivalent to a one-element list.
%
%   A synthetic two-island Ybus is used deliberately: the algorithm is a pure
%   function of (Y, mpc, devices, snapshot, exclusions), so a fixture small
%   enough to reason about by hand is stronger evidence than a full case where a
%   pass could come from somewhere else.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
end

% =========================================================================
% 1. Every ID in the list is excluded, not just the first.
% =========================================================================
function test_a_two_id_list_excludes_both(tc)
% Island A holds SG1 (synchronous) and IBR2 (gfm); island B holds IBR3 (gfm).
% Both islands therefore have a voltage-forming source and the gate passes with
% nothing excluded. Excluding BOTH island-A sources must fail island A alone.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();

tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs), ...
    'baseline: every island has a voltage-forming source');

[has_vf,failing] = stability.per_island_vf_check(Y,mpc,devs,hs,{'SG1','IBR2'});
tc.verifyFalse(has_vf, ...
    'excluding both of island A''s sources must leave island A without one');
tc.verifyEqual(failing,1, ...
    'island A (id 1) is the only island that lost its sources');
end

function test_excluding_only_the_first_id_is_not_enough_to_pass(tc)
% The discriminating case. If the implementation honoured only the first entry,
% IBR2 would still count and the previous test would pass for the WRONG reason.
% Excluding SG1 alone must therefore still PASS, which pins that IBR2 is what
% carries island A -- so the failure above can only come from excluding IBR2 too.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs,{'SG1'}), ...
    'IBR2 still forms island A when only SG1 is excluded');
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs,{'IBR2'}), ...
    'SG1 still forms island A when only IBR2 is excluded');
end

function test_the_outgoing_converter_cannot_certify_its_own_outage(tc)
% This is the ibr_trip path in miniature: island B is carried by IBR3 alone, so
% removing IBR3 must be refused. Without the exclusion the snapshot still shows
% IBR3 in gfm and the gate would wave the outage through -- the island would be
% left with no angle reference and the run would continue as if it had one.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();

[has_vf,failing] = stability.per_island_vf_check(Y,mpc,devs,hs,{'IBR3'});
tc.verifyFalse(has_vf, ...
    'IBR3 is island B''s only source; its outage must be refused');
tc.verifyEqual(failing,2,'island B (id 2) must be the failing island');

% And the same call WITHOUT the exclusion passes, which is precisely why the
% argument has to exist.
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs), ...
    'sanity: unexcluded, IBR3 answers the question about its own outage');
end

function test_vf_positions_omit_every_excluded_device(tc)
% The third output is what the caller logs as the surviving reference sources. An
% excluded device appearing here would make a diagnostic name a device that is
% gone.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
[~,~,pos] = stability.per_island_vf_check(Y,mpc,devs,hs,{'SG1','IBR3'});
tc.verifyEqual(sort(pos),2, ...
    'only IBR2 (bus position 2) may remain as a voltage-forming source');
end

% =========================================================================
% 2. The historical scalar call is unchanged.
% =========================================================================
function test_a_scalar_char_id_equals_a_one_element_list(tc)
% trip_transaction passes sched.sg_id, a char. Equality of ALL THREE outputs is
% the assertion: a scalar must not merely "also work", it must be the same call.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
[a1,a2,a3] = stability.per_island_vf_check(Y,mpc,devs,hs,'SG1');
[b1,b2,b3] = stability.per_island_vf_check(Y,mpc,devs,hs,{'SG1'});
tc.verifyEqual(a1,b1);
tc.verifyEqual(a2,b2);
tc.verifyEqual(a3,b3);
end

function test_a_string_scalar_and_a_string_array_are_accepted(tc)
% "IBR2" reaches this function as a string whenever a caller builds the ID from
% string(dev.device_id). Refusing it would be a type trap, not a safety gate.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
tc.verifyEqual(stability.per_island_vf_check(Y,mpc,devs,hs,"SG1"), ...
    stability.per_island_vf_check(Y,mpc,devs,hs,{'SG1'}));
tc.verifyEqual(stability.per_island_vf_check(Y,mpc,devs,hs,["SG1" "IBR2"]), ...
    stability.per_island_vf_check(Y,mpc,devs,hs,{'SG1','IBR2'}));
end

function test_an_omitted_or_empty_exclusion_excludes_nothing(tc)
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs));
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs,{}));
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs,''));
end

function test_an_unknown_id_in_the_list_excludes_nothing_silently(tc)
% Deliberate and worth pinning: the list is "do not let these answer", not "these
% must exist". A caller that names a device not in this DAE gets no exclusion,
% and the gate still reports the true state of the islands rather than erroring
% on a name it was merely asked to ignore.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs,{'IBR_NOT_IN_CASE'}));
end

function test_a_bad_exclusion_type_fails_closed_by_name(tc)
% A numeric index here would be a caller confusing POSITIONAL identity with ID
% identity. Silently coercing it would exclude nothing and quietly certify an
% outage, so it must fail closed with a named identifier.
[Y,mpc,devs] = two_island_fixture();
hs = all_online_snapshot();
tc.verifyError(@() stability.per_island_vf_check(Y,mpc,devs,hs,2), ...
    'stability:per_island_vf_check:badExcludedIds');
tc.verifyError(@() stability.per_island_vf_check(Y,mpc,devs,hs,struct('a',1)), ...
    'stability:per_island_vf_check:badExcludedIds');
end

% =========================================================================
% 3. Exclusion is not the only thing that disqualifies a source.
% =========================================================================
function test_an_offline_or_non_forming_device_never_counts(tc)
% The exclusion list is an ADDITIONAL disqualifier, not a replacement for the
% online flag and the mode. If either of those stopped being read, an outage
% could be certified by a device that is offline or merely following.
[Y,mpc,devs] = two_island_fixture();

hs = all_online_snapshot();
hs.device_online.IBR3 = false;      % offline, still recorded as gfm
[has_vf,failing] = stability.per_island_vf_check(Y,mpc,devs,hs);
tc.verifyFalse(has_vf,'an offline device is not a voltage-forming source');
tc.verifyEqual(failing,2);

hs = all_online_snapshot();
hs.device_modes.IBR3 = 'gfl';       % online, but following
[has_vf,failing] = stability.per_island_vf_check(Y,mpc,devs,hs);
tc.verifyFalse(has_vf,'a grid-following device is not a voltage-forming source');
tc.verifyEqual(failing,2);

hs = all_online_snapshot();
hs.device_modes.IBR3 = 'tripped';   % the mode an ibr_trip writes
[has_vf,failing] = stability.per_island_vf_check(Y,mpc,devs,hs);
tc.verifyFalse(has_vf,'a tripped converter is not a voltage-forming source');
tc.verifyEqual(failing,2);
end

function test_a_de_energized_island_is_not_required_to_have_a_source(tc)
% Bus 4 is split off with no load, no shunt and no device. It is de-energized, so
% demanding a reference there would refuse a physically fine transaction.
[Y,mpc,devs] = two_island_fixture();
% Cut the 3-4 branch in BOTH the admittance and the branch list: island_components
% cross-checks the two and fails closed if a listed branch is missing from Y.
Y(3,4) = 0; Y(4,3) = 0; Y(4,4) = 0;
mpc.branch(mpc.branch(:,1)==3 & mpc.branch(:,2)==4,:) = [];
mpc.bus(4,3:6) = 0;

hs = all_online_snapshot();
tc.verifyTrue(stability.per_island_vf_check(Y,mpc,devs,hs), ...
    'an empty isolated bus must not require a voltage-forming source');
end

% =========================================================================
% Fixture. Two islands, hand-checkable.
%
%   island A: bus 1 -- bus 2     SG1 at bus 1 (synchronous), IBR2 at bus 2 (gfm)
%   island B: bus 3 -- bus 4     IBR3 at bus 3 (gfm)
%
% Every bus carries load, so every island is energized and the energization rule
% is never what makes a test pass or fail.
% =========================================================================
function [Y,mpc,devs] = two_island_fixture()
Y = zeros(4);
Y(1,2) = -10i; Y(2,1) = -10i; Y(1,1) = 10i; Y(2,2) = 10i;
Y(3,4) = -5i;  Y(4,3) = -5i;  Y(3,3) = 5i;  Y(4,4) = 5i;
mpc = struct( ...
    'bus',    [1 1 20  6 0 0 1 1.0 0 0 0 0; ...
               2 1 30 10 0 0 1 1.0 0 0 0 0; ...
               3 1 25  8 0 0 1 1.0 0 0 0 0; ...
               4 1 15  5 0 0 1 1.0 0 0 0 0], ...
    'branch', [1 2 0 0.1 0 0 0 0 0 0 1; ...
               3 4 0 0.2 0 0 0 0 0 0 1]);
devs = repmat(struct('device_id','','bus_position',0, ...
    'capabilities',struct()),3,1);
devs(1).device_id = 'SG1';  devs(1).bus_position = 1;
devs(1).capabilities = struct('voltage_forming_modes','synchronous');
devs(2).device_id = 'IBR2'; devs(2).bus_position = 2;
devs(2).capabilities = struct('voltage_forming_modes','gfm');
devs(3).device_id = 'IBR3'; devs(3).bus_position = 3;
devs(3).capabilities = struct('voltage_forming_modes','gfm');
end

function hs = all_online_snapshot()
hs = struct( ...
    'device_online', struct('SG1',true,'IBR2',true,'IBR3',true), ...
    'device_modes',  struct('SG1','synchronous','IBR2','gfm','IBR3','gfm'));
end
