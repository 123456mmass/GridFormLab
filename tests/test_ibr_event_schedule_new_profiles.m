function tests = test_ibr_event_schedule_new_profiles()
%TEST_IBR_EVENT_SCHEDULE_NEW_PROFILES  The three added profiles, and the four old ones.
%   The schedule is the gatekeeper: a sequence it accepts runs, a sequence it
%   rejects never reaches the solver. Three profiles were added to express
%   disturbance orders the delivered 'chronology' cannot, plus one new event
%   (ibr_trip). This file falsifies four things:
%
%     1. Each new profile ACCEPTS its intended order and REJECTS a wrong one
%        with a NAMED identifier. A profile that accepted any order would let a
%        mis-typed scenario run and report a result for a sequence nobody meant.
%     2. The four delivered profiles are UNCHANGED -- same event list, same
%        flags, same times. The capability table replaced a three-flag scheme,
%        and every published result comes from 'chronology', so a behavioural
%        change there would invalidate the delivered study.
%     3. Every event field a profile arms reaches the schedule OUTPUT. This is
%        the silent-no-op trap: the kernel builds its admittance stamps from
%        these fields, so a profile that arms load_step without publishing
%        load_step_factor produced a zero stamp while the event log still said
%        applied=true.
%     4. Coincident and duplicate times are refused for the NEW events too. The
%        duplicate check covered four fields; load_step, line_trip,
%        line_fault_clear and ibr_trip were outside it, so two events could be
%        scheduled at one instant and pass.
%
%   No figure, no solver: the schedule is a pure validation function, which is
%   why this can be a fast unit test.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data,s.resources,s.scenario_opt);
tc.TestData.case_data = s.case_data;
tc.TestData.devices = devices;
end

% =========================================================================
% 1. The three added profiles accept their order and refuse a wrong one.
% =========================================================================
function test_sg_load_cycle_accepts_its_order_and_publishes_its_events(tc)
s = sched(tc,sg_load_cycle_events());
tc.verifyEqual({s.events.type},{'sg_trip','load_step','sg_on'});
tc.verifyEqual([s.events.t],[20 50 80],'AbsTol',0);
tc.verifyTrue(s.has_load_step);
tc.verifyTrue(s.has_sg_trip);
tc.verifyTrue(s.has_sg_reclose);
tc.verifyFalse(s.has_fault);
tc.verifyFalse(s.has_line_trip);
tc.verifyFalse(s.has_line_fault_clear);
tc.verifyFalse(s.has_ibr_trip);
tc.verifyFalse(s.has_restore);
% has_chronology stays a PROFILE IDENTITY, not a capability: the kernel's
% sync-controller and stamp decisions were moved onto the capability flags
% precisely so this can be false while load_step still works.
tc.verifyFalse(s.has_chronology);
% The trap: the factor must reach the output, or the load stamp is zero.
tc.verifyEqual(s.load_step,50,'AbsTol',0);
tc.verifyEqual(s.load_step_factor,0.30,'AbsTol',0);
end

function test_sg_load_cycle_refuses_a_load_step_before_the_trip(tc)
ev = sg_load_cycle_events(); ev.load_step = 10;   % before sg_trip = 20
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_sg_load_cycle_refuses_a_reclose_before_the_load_step(tc)
ev = sg_load_cycle_events(); ev.sg_on = 40;       % before load_step = 50
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_sg_fault_cycle_accepts_its_order_and_publishes_its_events(tc)
s = sched(tc,sg_fault_cycle_events());
tc.verifyEqual({s.events.type},{'sg_trip','fault_on','fault_clear','sg_on'});
tc.verifyEqual([s.events.t],[20 50 50.15 80],'AbsTol',0);
tc.verifyTrue(s.has_fault);
tc.verifyTrue(s.has_sg_trip);
tc.verifyTrue(s.has_sg_reclose);
tc.verifyFalse(s.has_load_step);
tc.verifyFalse(s.has_line_fault_clear);
tc.verifyFalse(s.has_chronology);
tc.verifyEqual(s.fault_bus,9,'AbsTol',0);
tc.verifyEqual(s.Zf,0.01+0.01i,'AbsTol',0);
end

function test_sg_fault_cycle_refuses_a_fault_before_the_trip(tc)
% This order is the one the DELIVERED 'combined' profile requires
% (fault_clear <= sg_trip). Accepting it here would silently run 'combined'
% semantics under a name that promises the opposite.
ev = sg_fault_cycle_events();
ev.fault_on = 5; ev.fault_clear = 5.15;
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_sg_fault_cycle_refuses_a_clearing_after_the_reclose(tc)
ev = sg_fault_cycle_events(); ev.sg_on = 50.10;   % inside the fault
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_line_fault_relay_clear_accepts_its_order_and_arms_one_clearing(tc)
s = sched(tc,line_fault_events());
% ONE clearing event, not line_trip + fault_clear. The breakers at both ends of
% the faulted line open, so the line and the fault leave together; a two-event
% form would create a window in which the line is open and the fault is still on.
tc.verifyEqual({s.events.type},{'sg_trip','fault_on','line_fault_clear','sg_on'});
tc.verifyEqual([s.events.t],[20 50 50.15 90],'AbsTol',0);
tc.verifyTrue(s.has_fault);
tc.verifyTrue(s.has_line_fault_clear);
tc.verifyTrue(s.needs_line_stamp);
tc.verifyFalse(s.has_line_trip);
% No restore: the line does NOT come back. topology_restore is what would
% return it, and this profile never emits one.
tc.verifyFalse(s.has_restore);
tc.verifyFalse(isfield(s,'restore_time'));
tc.verifyTrue(isnan(s.fault_clear), ...
    'A relay-cleared line fault publishes no separate fault_clear instant.');
tc.verifyEqual(s.line_from_bus,9,'AbsTol',0);
tc.verifyEqual(s.line_to_bus,14,'AbsTol',0);
tc.verifyEqual(s.line_fault_clear,50.15,'AbsTol',0);
% The fault model is a documented approximation and must be stated in the
% artifact, not only in a comment.
tc.verifySubstring(lower(s.provenance.line_fault_model),'zero-distance');
end

function test_line_fault_relay_clear_refuses_a_clearing_before_the_fault(tc)
ev = line_fault_events(); ev.line_fault_clear = 45;   % before fault_on = 50
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_line_fault_relay_clear_refuses_a_reclose_before_the_clearing(tc)
ev = line_fault_events(); ev.sg_on = 50.10;
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_line_fault_relay_clear_requires_the_line_terminals(tc)
% Without both terminals the kernel cannot build the branch stamp, so the line
% would "open" by subtracting a zero matrix -- the silent no-op in its purest
% form. The required-field check must catch it here.
ev = line_fault_events(); ev = rmfield(ev,'line_to_bus');
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:missingField');
end

function test_former_outage_accepts_its_order_and_arms_the_converter_outage(tc)
s = sched(tc,former_outage_events());
tc.verifyEqual({s.events.type},{'sg_trip','ibr_trip'});
tc.verifyEqual([s.events.t],[20 60],'AbsTol',0);
tc.verifyTrue(s.has_ibr_trip);
tc.verifyTrue(s.has_sg_trip);
% No reclose is scheduled: the question is whether the CONVERTERS recover the
% reference, and offering the machine back would answer a different one.
tc.verifyFalse(s.has_sg_reclose);
tc.verifyTrue(isnan(s.sg_on));
tc.verifyFalse(s.has_fault);
tc.verifyFalse(s.has_load_step);
tc.verifyEqual(s.ibr_trip,60,'AbsTol',0);
% The COMMANDED target survives to the output as the token, not resolved to a
% device index: which converter owns the reference at t = 60 s is a run-time
% outcome of the severity supervisor and is not knowable at validation time.
tc.verifyEqual(s.ibr_trip_target,'reference_owner');
end

function test_former_outage_refuses_an_outage_before_the_trip(tc)
ev = former_outage_events(); ev.ibr_trip = 10;
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_former_outage_refuses_an_outage_past_the_horizon(tc)
% An event after t_end would be validated, reported in the schedule, and never
% reached -- a run that silently answers nothing.
ev = former_outage_events(); ev.ibr_trip = 130;   % t_end = 120
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_former_outage_refuses_a_target_that_is_not_a_converter(tc)
% Device 1 is the synchronous machine. The transaction has no transfer path for
% it and the machine already has its own breaker events, so this is refused at
% validation rather than at run time.
ev = former_outage_events(); ev.ibr_trip_target = 1;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:badIbrTripTarget');
end

function test_former_outage_refuses_an_out_of_range_target(tc)
ev = former_outage_events(); ev.ibr_trip_target = 99;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:badIbrTripTarget');
end

function test_former_outage_refuses_a_resource_id_string_as_target(tc)
% Device identity in this schedule is POSITIONAL everywhere else
% (selected_gfm_indices, reference_resource_index). Admitting an ID string here
% would open a second identity channel, which is the ownership confusion the
% selection_request contract was written to close.
ev = former_outage_events(); ev.ibr_trip_target = 'IBR2';
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:badIbrTripTarget');
end

function test_former_outage_accepts_an_explicit_converter_index(tc)
% The numeric form must work as well as the token: a scenario that wants a
% NON-owner converter out has no other way to say so.
ev = former_outage_events(); ev.ibr_trip_target = 3;
s = sched(tc,ev);
tc.verifyEqual(s.ibr_trip_target,3,'AbsTol',0);
end

function test_former_outage_requires_a_target(tc)
ev = former_outage_events(); ev = rmfield(ev,'ibr_trip_target');
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:missingField');
end

% =========================================================================
% 2. The four delivered profiles are unchanged.
%    Every published result comes from 'chronology'. The capability table
%    replaced a three-flag scheme, so this is the regression that matters most
%    in this file: same event list, same instants, same flags.
% =========================================================================
function test_chronology_is_unchanged(tc)
s = sched(tc,chronology_events());
tc.verifyEqual({s.events.type}, ...
    {'sg_trip','load_step','fault_on','fault_clear','line_trip', ...
     'topology_restore','sg_on'});
tc.verifyEqual([s.events.t],[20 50 85 85.15 110 145 145],'AbsTol',0);
tc.verifyTrue(s.has_chronology);
tc.verifyTrue(s.has_fault);
tc.verifyTrue(s.has_sg_cycle);
tc.verifyTrue(s.has_load_step);
tc.verifyTrue(s.has_line_trip);
tc.verifyTrue(s.has_restore);
tc.verifyTrue(s.has_sync_controller);
tc.verifyTrue(s.needs_line_stamp);
tc.verifyFalse(s.has_line_fault_clear);
tc.verifyFalse(s.has_ibr_trip);
tc.verifyEqual(s.load_step_factor,0.20,'AbsTol',0);
tc.verifyEqual(s.restore_time,145,'AbsTol',0);
end

function test_chronology_still_requires_restore_equal_to_sg_on(tc)
% The delivered contract is restore_time == sg_on EXACTLY. That equality is
% also why restore_time is excluded from the coincidence check, so if the
% equality stopped being enforced the exclusion would become a hole.
ev = chronology_events(); ev.restore_time = 144;
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_combined_is_unchanged(tc)
s = sched(tc,combined_events());
tc.verifyEqual({s.events.type},{'fault_on','fault_clear','sg_trip','sg_on'});
tc.verifyTrue(s.has_fault);
tc.verifyTrue(s.has_sg_cycle);
tc.verifyFalse(s.has_chronology);
tc.verifyFalse(s.has_load_step);
tc.verifyFalse(s.has_line_trip);
tc.verifyFalse(s.has_restore);
tc.verifyFalse(s.has_ibr_trip);
tc.verifyFalse(s.needs_line_stamp);
end

function test_combined_still_requires_the_clearing_no_later_than_the_trip(tc)
% This is the inequality that makes 'combined' different from the new
% sg_fault_cycle. If it were relaxed the two profiles would collapse into one.
ev = combined_events(); ev.fault_on = 0.05; ev.fault_clear = 0.06;
tc.verifyError(@() sched(tc,ev),'stability:ibr_event_schedule:badOrdering');
end

function test_fault_only_is_unchanged(tc)
s = sched(tc,fault_only_events());
tc.verifyEqual({s.events.type},{'fault_on','fault_clear'});
tc.verifyTrue(s.has_fault);
tc.verifyFalse(s.has_sg_cycle);
tc.verifyTrue(isnan(s.sg_trip));
tc.verifyTrue(isnan(s.sg_on));
tc.verifyFalse(s.has_ibr_trip);
tc.verifyFalse(s.has_load_step);
end

function test_sg_cycle_is_unchanged(tc)
s = sched(tc,sg_cycle_events());
tc.verifyEqual({s.events.type},{'sg_trip','sg_on'});
tc.verifyFalse(s.has_fault);
tc.verifyTrue(s.has_sg_cycle);
tc.verifyTrue(isnan(s.fault_bus));
tc.verifyTrue(isnan(s.Zf));
tc.verifyFalse(s.has_load_step);
tc.verifyFalse(s.needs_line_stamp);
end

function test_an_unknown_profile_is_refused_by_name(tc)
% validatestring owns this path and predates the added profiles, so the
% identifier is MATLAB's, not this module's. Expecting a module identifier here
% would be a test asserting a change nobody made: what matters is that an
% unknown profile CANNOT reach the solver, and it cannot.
ev = sg_cycle_events(); ev.event_profile = 'sg_load_cycle_v2';
tc.verifyError(@() sched(tc,ev),'MATLAB:unrecognizedStringChoice');
end

% =========================================================================
% 3. The new events joined the shared time list.
%    Before the capability flags, load_step / line_trip / line_fault_clear /
%    ibr_trip were validated only by an ordering inequality: they never entered
%    the finiteness gate nor the coincidence gate. Membership in that list is
%    what these tests falsify, through both gates it feeds.
%
%    Note on identifiers: on the FOUR ADDED profiles a pair set to one instant
%    is refused as badOrdering, not coincidentEvents, because each added
%    profile's rule demands a gap STRICTLY GREATER than tol and therefore fires
%    first. That is a stricter gate, not a hole. The coincidence gate is still
%    the only thing standing between a sub-tol gap and the solver, and the
%    chronology -- whose rule uses a bare '<' -- is where that is observable.
% =========================================================================
function test_a_load_step_on_the_trip_instant_is_refused(tc)
ev = sg_load_cycle_events(); ev.load_step = ev.sg_trip;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:badOrdering');
end

function test_a_line_clearing_on_the_fault_instant_is_refused(tc)
ev = line_fault_events(); ev.line_fault_clear = ev.fault_on;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:badOrdering');
end

function test_a_converter_outage_on_the_trip_instant_is_refused(tc)
ev = former_outage_events(); ev.ibr_trip = ev.sg_trip;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:badOrdering');
end

function test_a_load_step_a_hair_from_another_event_is_refused_as_coincident(tc)
% The gap is 1e-13: representable at t = 50 (eps(50) = 7.1e-15), smaller than
% tol = 1e-12, and large enough that the chronology's bare '<' accepts it. Only
% membership in times.values catches this, so this test fails if load_step is
% ever taken back out of that list.
ev = chronology_events(); ev.fault_on = ev.load_step + 1e-13;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:coincidentEvents');
end

function test_a_line_trip_a_hair_from_the_clearing_is_refused_as_coincident(tc)
ev = chronology_events(); ev.line_trip = ev.fault_clear + 1e-13;
tc.verifyError(@() sched(tc,ev), ...
    'stability:ibr_event_schedule:coincidentEvents');
end

function test_the_new_events_reach_the_finiteness_gate(tc)
% A NaN instant is the failure mode of a scenario table with a field left
% unset. Outside times.values it would sail past every numeric gate and be
% compared with '<' -- and every comparison against NaN is false, so an
% ordering rule cannot catch it either. This is the gate that does.
cases_to_check = { ...
    'load_step',        sg_load_cycle_events(); ...
    'line_fault_clear', line_fault_events(); ...
    'ibr_trip',         former_outage_events()};
for k = 1:size(cases_to_check,1)
    f = cases_to_check{k,1};
    ev = cases_to_check{k,2}; ev.(f) = NaN;
    tc.verifyError(@() sched(tc,ev), ...
        'stability:ibr_event_schedule:badTime', ...
        sprintf('%s = NaN was not refused by the finiteness gate',f));
    ev = cases_to_check{k,2}; ev.(f) = -1;
    tc.verifyError(@() sched(tc,ev), ...
        'stability:ibr_event_schedule:badTime', ...
        sprintf('%s = -1 was not refused by the nonnegativity gate',f));
end
end

% =========================================================================
% 4. Structural properties of the capability table itself.
% =========================================================================
function test_every_profile_publishes_every_capability_flag(tc)
% A consumer reads sched.has_<event> to decide whether to build an admittance
% stamp. A flag ABSENT on some profile would make that consumer fall back to a
% default, which is exactly how the silent no-op arose. Every profile must
% publish every flag, so the answer is always explicit.
FLAGS = {'has_fault','has_sg_cycle','has_chronology','has_sg_trip', ...
    'has_sg_reclose','has_load_step','has_line_trip','has_restore', ...
    'has_line_fault_clear','has_ibr_trip','has_sync_controller', ...
    'needs_line_stamp'};
all_ev = {chronology_events(),combined_events(),fault_only_events(), ...
    sg_cycle_events(),sg_load_cycle_events(),sg_fault_cycle_events(), ...
    line_fault_events(),former_outage_events()};
for k = 1:numel(all_ev)
    s = sched(tc,all_ev{k});
    for j = 1:numel(FLAGS)
        tc.verifyTrue(isfield(s,FLAGS{j}), ...
            sprintf('profile "%s" does not publish %s', ...
                s.event_profile,FLAGS{j}));
        tc.verifyTrue(islogical(s.(FLAGS{j})) && isscalar(s.(FLAGS{j})), ...
            sprintf('profile "%s" publishes a non-logical %s', ...
                s.event_profile,FLAGS{j}));
    end
end
end

function test_the_line_stamp_flag_is_the_union_of_its_two_events(tc)
% needs_line_stamp is what the kernel gates the branch stamp on. It must be
% true for BOTH events that remove a line, or one of them opens the line by
% subtracting a zero matrix.
tc.verifyTrue(sched(tc,chronology_events()).needs_line_stamp);   % line_trip
tc.verifyTrue(sched(tc,line_fault_events()).needs_line_stamp);   % line_fault_clear
tc.verifyFalse(sched(tc,sg_load_cycle_events()).needs_line_stamp);
tc.verifyFalse(sched(tc,former_outage_events()).needs_line_stamp);
end

function test_events_are_sorted_by_time_on_every_profile(tc)
all_ev = {chronology_events(),combined_events(),fault_only_events(), ...
    sg_cycle_events(),sg_load_cycle_events(),sg_fault_cycle_events(), ...
    line_fault_events(),former_outage_events()};
for k = 1:numel(all_ev)
    s = sched(tc,all_ev{k});
    tc.verifyTrue(issorted([s.events.t]), ...
        sprintf('profile "%s" emits unsorted events',s.event_profile));
end
end

% =========================================================================
% Fixtures. Each returns the event struct for ONE profile, at the instants the
% scenario suite actually requests, so a rule this file exercises is the rule
% the delivered runs are validated against.
% =========================================================================
function s = sched(tc,ev,t_end)
%SCHED  Validate one event struct at the horizon that profile needs.
%   The horizon is not one constant across profiles: the delivered chronology
%   recloses at 145 s and the two short legacy profiles finish inside 0.1 s, so
%   validating everything at 120 s would refuse valid sequences for a reason no
%   test here intends to exercise. horizon_for states each profile's own.
if nargin < 3, t_end = horizon_for(ev); end
s = stability.ibr_event_schedule(tc.TestData.case_data, ...
    tc.TestData.devices,ev,t_end,0.05);
end

function te = horizon_for(ev)
%HORIZON_FOR  The horizon each profile's fixture is written for.
%   Only the delivered chronology needs its own: its reclose is at 145 s, so
%   validating it at the suite's 120 s would refuse the delivered sequence for a
%   reason this file does not intend to test. Every other fixture fits in 120 s.
if strcmp(ev.event_profile,'chronology')
    te = 250;
else
    te = 120;
end
end

function ev = base_events()
% Automatic switching, so no manual GFM tuple is required: the selector table
% owns the choice. This is the mode every scenario in the suite runs in.
ev = struct('enabled',true,'automatic_gfm_switching',true);
end

function ev = sg_load_cycle_events()
ev = base_events();
ev.event_profile = 'sg_load_cycle';
ev.sg_trip = 20;
ev.load_step = 50;
ev.load_step_factor = 0.30;
ev.sg_on = 80;
end

function ev = sg_fault_cycle_events()
ev = base_events();
ev.event_profile = 'sg_fault_cycle';
ev.sg_trip = 20;
ev.fault_on = 50;
ev.fault_clear = 50.15;
ev.fault_bus = 9;
ev.Zf = 0.01+0.01i;
ev.sg_on = 80;
end

function ev = line_fault_events()
% Branch 9-14, chosen because bus 9's other incident branches are transformers
% (4-9 and 7-9) and because opening 9-14 strands no bus: bus 14 keeps 13-14 and
% bus 9 keeps three paths.
ev = base_events();
ev.event_profile = 'line_fault_relay_clear';
ev.sg_trip = 20;
ev.fault_on = 50;
ev.fault_bus = 9;
ev.Zf = 0.01+0.01i;
ev.line_fault_clear = 50.15;
ev.line_from_bus = 9;
ev.line_to_bus = 14;
ev.sg_on = 90;
end

function ev = former_outage_events()
ev = base_events();
ev.event_profile = 'sg_trip_then_former_outage';
ev.sg_trip = 20;
ev.ibr_trip = 60;
ev.ibr_trip_target = 'reference_owner';
end

function ev = chronology_events()
% The delivered chronology, at its delivered instants.
ev = base_events();
ev.event_profile = 'chronology';
ev.sg_trip = 20;
ev.load_step = 50;
ev.load_step_factor = 0.20;
ev.fault_on = 85;
ev.fault_clear = 85.15;
ev.fault_bus = 9;
ev.Zf = 0.01+0.01i;
ev.line_trip = 110;
ev.line_from_bus = 6;
ev.line_to_bus = 13;
ev.restore_time = 145;
ev.sg_on = 145;
end

function ev = combined_events()
% 'combined' requires fault_clear <= sg_trip, i.e. the fault is cleared before
% the machine goes, which is the opposite of sg_fault_cycle.
ev = base_events();
ev.event_profile = 'combined';
ev.fault_on = 0.02;
ev.fault_clear = 0.03;
ev.fault_bus = 4;
ev.Zf = 1i*0.1;
ev.sg_trip = 0.04;
ev.sg_on = 0.06;
end

function ev = fault_only_events()
ev = base_events();
ev.event_profile = 'fault_only';
ev.fault_on = 0.02;
ev.fault_clear = 0.03;
ev.fault_bus = 4;
ev.Zf = 1i*0.1;
end

function ev = sg_cycle_events()
ev = base_events();
ev.event_profile = 'sg_cycle';
ev.sg_trip = 20;
ev.sg_on = 80;
end
