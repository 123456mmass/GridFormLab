function tests = test_ieee14_switch_event_marks()
%TEST_IEEE14_SWITCH_EVENT_MARKS  Event-marker table contract (no graphics).
%   Falsification targets:
%     1. A hard-coded chronology instant. Every disturbance time must be READ
%        from r.sched, so moving a fixture time must move the mark.
%     2. Label collision. Near-coincident marks must merge to one label, and
%        distant marks must not.
%     3. Loss of markers on a truncated arm. The disturbance family comes from
%        r.sched, which stays populated even when the run never reached the
%        events, so a fail-closed arm must still get the full set.
%
%   Nothing here renders a figure: the marker table is a pure function, which is
%   exactly why it is separated from the drawing helper.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
tc.TestData.r = fixture();
end

% =========================================================================
function test_disturbance_times_are_read_from_the_schedule(tc)
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
t_of = @(MM,src) MM.marks(strcmp({MM.marks.source},src)).t;
tc.verifyEqual(t_of(M,'r.sched.sg_trip'),      r.sched.sg_trip,      'AbsTol',0);
tc.verifyEqual(t_of(M,'r.sched.load_step'),    r.sched.load_step,    'AbsTol',0);
tc.verifyEqual(t_of(M,'r.sched.fault_on'),     r.sched.fault_on,     'AbsTol',0);
tc.verifyEqual(t_of(M,'r.sched.fault_clear'),  r.sched.fault_clear,  'AbsTol',0);
tc.verifyEqual(t_of(M,'r.sched.line_trip'),    r.sched.line_trip,    'AbsTol',0);
tc.verifyEqual(t_of(M,'r.sched.restore_time'), r.sched.restore_time, 'AbsTol',0);
tc.verifyEqual(t_of(M,'r.actual_reclose_time'),r.actual_reclose_time,'AbsTol',0);
end

function test_moving_a_scheduled_time_moves_its_mark(tc)
% This is the assertion that fails if anyone writes 85 into the generator.
r = tc.TestData.r;
r.sched.fault_on = 91.25;
r.sched.fault_clear = 91.40;
M = ieee14_switch_event_marks(r);
t = M.marks(strcmp({M.marks.source},'r.sched.fault_on')).t;
tc.verifyEqual(t,91.25,'AbsTol',0);
tc.verifyEqual(M.regions(1).t0,91.25,'AbsTol',0);
tc.verifyEqual(M.regions(1).t1,91.40,'AbsTol',0);
end

function test_labels_for_the_fault_pair_merge_into_one_group(tc)
% 85.00 and 85.15 are 0.06 % of a 250 s axis: one group, one label.
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
i1 = find(strcmp({M.marks.source},'r.sched.fault_on'),1);
i2 = find(strcmp({M.marks.source},'r.sched.fault_clear'),1);
tc.verifyEqual(M.marks(i1).group,M.marks(i2).group);
labelled = [M.marks.is_group_label] & [M.marks.group] == M.marks(i1).group;
tc.verifyEqual(sum(labelled),1);
end

function test_distant_marks_are_not_merged(tc)
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
i1 = find(strcmp({M.marks.source},'r.sched.line_trip'),1);
i2 = find(strcmp({M.marks.source},'r.sched.restore_time'),1);
tc.verifyNotEqual(M.marks(i1).group,M.marks(i2).group);
end

function test_every_labelled_group_is_at_least_tau_apart_or_on_another_row(tc)
% Collision-freedom must be a property of the construction, not of this
% particular event list.
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
lab = M.marks([M.marks.is_group_label]);
[~,ord] = sort([lab.t]); lab = lab(ord);
for k = 2:numel(lab)
    gap_ok = (lab(k).t - lab(k-1).t) > M.tau - 1e-12;
    row_ok = lab(k).row ~= lab(k-1).row;
    tc.verifyTrue(gap_ok || row_ok, ...
        sprintf('labels at t=%g and t=%g collide on row %d', ...
            lab(k-1).t,lab(k).t,lab(k).row));
end
end

function test_supervisor_marks_carry_their_applied_flag(tc)
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
sup = M.marks(strcmp({M.marks.family},'supervisor'));
tc.verifyNotEmpty(sup);
tc.verifyTrue(any(~[sup.applied]), ...
    'a refused supervisor transaction must survive into the marker table');
tc.verifyTrue(any([sup.applied]));
end

function test_supervisor_mark_coincident_with_a_disturbance_is_folded_in(tc)
% Two lines at the same instant in two styles is visual noise; the fact is kept
% on the disturbance mark instead of being discarded.
r = tc.TestData.r;
r.event_log(end+1) = struct('type','gfm_support_augment', ...
    't',r.sched.load_step,'applied',true);
M = ieee14_switch_event_marks(r);
j = find(strcmp({M.marks.source},'r.sched.load_step'),1);
tc.verifyTrue(M.marks(j).has_supervisor_commit);
tc.verifyEqual(sum([M.marks.t] == r.sched.load_step),1);
end

function test_truncated_arm_keeps_every_scheduled_mark_and_gains_an_exit(tc)
% A fail-closed arm has one unapplied sg_trip in its event log and nothing after
% it, yet the page must still show where the later events would have been.
r = tc.TestData.r;
r.t = (0:0.5:20)';
r.event_log = struct('type',{'sg_trip'},'t',{20},'applied',{false});
r.failure_id = 'ts_simulate_ibr_hybrid:noVoltageFormingSource';
M = ieee14_switch_event_marks(r,t_end=250);
dist = M.marks(strcmp({M.marks.family},'disturbance'));
tc.verifyEqual(numel(dist),7);
ex = M.marks(strcmp({M.marks.family},'validity'));
tc.verifyEqual(numel(ex),1);
tc.verifyEqual(ex.t,20,'AbsTol',0);
tc.verifySubstring(ex.label,'noVoltageFormingSource');
end

function test_missing_reclose_drops_exactly_one_mark(tc)
r = tc.TestData.r;
n1 = numel(ieee14_switch_event_marks(r).marks);
r.actual_reclose_time = NaN;
n2 = numel(ieee14_switch_event_marks(r).marks);
tc.verifyEqual(n2,n1-1);
r2 = tc.TestData.r; r2 = rmfield(r2,'actual_reclose_time');
tc.verifyEqual(numel(ieee14_switch_event_marks(r2).marks),n1-1);
end

function test_marks_are_sorted_and_markers_are_achromatic(tc)
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
tc.verifyTrue(issorted([M.marks.t]));
for k = 1:numel(M.marks)
    c = M.marks(k).color;
    if strcmp(M.marks(k).family,'validity'), continue; end
    tc.verifyEqual(c(1),c(2),'AbsTol',1e-12);
    tc.verifyEqual(c(2),c(3),'AbsTol',1e-12);
end
end

function test_empty_schedule_does_not_error(tc)
M = ieee14_switch_event_marks(struct('t',(0:0.1:1)'));
tc.verifyEqual(numel(M.marks),0);
tc.verifyEqual(numel(M.regions),0);
end

% =========================================================================
% merge_span: a zoom page needs its own tolerance reference. The default must
% stay a fraction of the FULL horizon, because pages already delivered were
% grouped that way and must not move.
function test_default_merge_span_is_the_full_horizon(tc)
r = tc.TestData.r;
M = ieee14_switch_event_marks(r);
tc.verifyEqual(M.merge_span,M.t_range(2)-M.t_range(1),'AbsTol',0);
tc.verifyEqual(M.tau,0.01*(M.t_range(2)-M.t_range(1)),'AbsTol',0);
end

function test_merge_span_scales_tau_without_touching_the_default(tc)
r = tc.TestData.r;
M_full = ieee14_switch_event_marks(r);
M_zoom = ieee14_switch_event_marks(r,merge_span=41);
tc.verifyEqual(M_zoom.tau,0.01*41,'AbsTol',0);
tc.verifyLessThan(M_zoom.tau,M_full.tau);
% Same call again without the option must reproduce the default exactly.
M_again = ieee14_switch_event_marks(r);
tc.verifyEqual(M_again.tau,M_full.tau,'AbsTol',0);
tc.verifyEqual(M_again.n_groups,M_full.n_groups);
end

function test_a_tighter_merge_span_separates_marks_the_default_merges(tc)
% The supervisor augment at 22.05 sits 2.05 s after the SG trip at 20. With the
% default tolerance (2.5 s on a 250 s horizon) the two share a group; with a
% zoom-sized span they must not.
r = tc.TestData.r;
M_full = ieee14_switch_event_marks(r);
g = @(MM,src) MM.marks(strcmp({MM.marks.source},src)).group;
trip_full = g(M_full,'r.sched.sg_trip');
aug_full  = [M_full.marks(strcmp({M_full.marks.family},'supervisor')).group];
tc.verifyTrue(ismember(trip_full,aug_full), ...
    'fixture no longer exercises the merge: adjust the augment time');

M_zoom = ieee14_switch_event_marks(r,merge_span=20);   % tau = 0.2 s
trip_zoom = g(M_zoom,'r.sched.sg_trip');
aug_zoom  = [M_zoom.marks(strcmp({M_zoom.marks.family},'supervisor')).group];
tc.verifyFalse(ismember(trip_zoom,aug_zoom));
tc.verifyGreaterThan(M_zoom.n_groups,M_full.n_groups);
end

function test_non_finite_or_non_positive_merge_span_falls_back_to_default(tc)
r = tc.TestData.r;
M_full = ieee14_switch_event_marks(r);
for bad = [NaN 0 -5]
    M = ieee14_switch_event_marks(r,merge_span=bad);
    tc.verifyEqual(M.tau,M_full.tau,'AbsTol',0);
    tc.verifyEqual(M.n_groups,M_full.n_groups);
end
end

% =========================================================================
function r = fixture()
r = struct();
r.sched = struct('t_end',250,'sg_trip',20,'load_step',50, ...
    'load_step_factor',0.20,'fault_on',85,'fault_clear',85.15, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13,'restore_time',145);
r.actual_reclose_time = 159.3436;
r.t = (0:0.5:250)';
r.event_log = struct( ...
    'type',{'sg_trip','gfm_support_augment','gfm_support_augment','gfm_support_release'}, ...
    't',{20,22.05,53.4025,148.2}, ...
    'applied',{true,true,false,true});
end
