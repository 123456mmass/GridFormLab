function tests = test_ieee14_event_execution()
%TEST_IEEE14_EVENT_EXECUTION  Scheduled-vs-executed accounting for scenario runs.
%
% What is under test is a distinction the expectation tokens cannot draw: an
% event the schedule ARMED against an event the kernel APPLIED. The scenario
% suite reports both, because a run can satisfy TRAJECTORY_THEN_ANY and still
% never reach the disturbance it exists to exercise -- and two of the four
% delivered scenarios do exactly that.
%
% The fixtures are synthetic, and deliberately so: they must be able to express
% a REFUSED event and a schedule with an unreachable tail, which a real 68 MB
% cache cannot be trimmed to without becoming a different run.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
here = fileparts(mfilename('fullpath'));
tc.TestData.restore = addpath(fullfile(here,'..','scripts','reporting'));
end

function teardownOnce(tc)
path(tc.TestData.restore);
end

% ==========================================================================
% 1. The two facts it must separate.
% ==========================================================================

function test_a_run_that_reached_everything_reports_nothing_unreached(tc)
r = run_fixture({'sg_trip','load_step','sg_on'}, ...
                {'sg_trip',true;'gfm_support_augment',true; ...
                 'load_step',true;'sg_on',true;'sg_reclose',true});
[ex,nx,def,ok] = ieee14_event_execution(r,arm('load_step'));
tc.verifyEqual(ex,{'sg_trip','load_step','sg_on'});
tc.verifyEmpty(nx);
tc.verifyEqual(def,'load_step');
tc.verifyTrue(ok);
end

function test_a_run_stopped_early_names_the_events_it_never_reached(tc)
% The sg_fault_bus9 shape: the fault applied, the clearing never did.
r = run_fixture({'sg_trip','fault_on','fault_clear','sg_on'}, ...
                {'sg_trip',true;'gfm_support_release',true;'fault_on',true});
[ex,nx,def,ok] = ieee14_event_execution(r,arm('fault_clear'));
tc.verifyEqual(ex,{'sg_trip','fault_on'});
tc.verifyEqual(nx,{'fault_clear','sg_on'});
tc.verifyEqual(def,'fault_clear');
tc.verifyFalse(ok, ...
    'the defining event was never applied, so it must not report as executed');
end

function test_the_defining_event_can_execute_while_later_events_do_not(tc)
% The former_outage shape, and the case that makes the two outputs independent:
% its own event committed, and the run still stopped short of the horizon. A
% helper that keyed defining_ok off "reached the end" would get this wrong.
r = run_fixture({'sg_trip','ibr_trip'}, ...
                {'sg_trip',true;'ibr_trip',true});
[~,nx,~,ok] = ieee14_event_execution(r,arm('ibr_trip'));
tc.verifyEmpty(nx);
tc.verifyTrue(ok);
end

% ==========================================================================
% 2. A refusal is not an execution.
% ==========================================================================

function test_an_event_logged_but_refused_counts_as_not_executed(tc)
% The discriminating test for decision 2 in the helper's header. If applied were
% ignored, this would report the outage as exercised when the transaction
% actually declined it -- reporting a capability as demonstrated by the very run
% that refused to demonstrate it.
r = run_fixture({'sg_trip','ibr_trip'}, ...
                {'sg_trip',true;'ibr_trip',false});
[ex,nx,~,ok] = ieee14_event_execution(r,arm('ibr_trip'));
tc.verifyEqual(ex,{'sg_trip'});
tc.verifyEqual(nx,{'ibr_trip'});
tc.verifyFalse(ok);
end

function test_a_refused_then_reapplied_event_counts_as_executed(tc)
% The supervisor logs a rejected attempt and a later applied one under the same
% type (gfm_support_augment does this at t=51.3 then t=53.3 in sg_load_step30).
% ANY applied entry is enough; requiring all of them would misreport that run.
r = run_fixture({'sg_trip','load_step'}, ...
                {'sg_trip',true;'load_step',false;'load_step',true});
[ex,nx,~,ok] = ieee14_event_execution(r,arm('load_step'));
tc.verifyEqual(ex,{'sg_trip','load_step'});
tc.verifyEmpty(nx);
tc.verifyTrue(ok);
end

% ==========================================================================
% 3. Only scheduled events are classified.
% ==========================================================================

function test_supervisor_entries_are_never_reported_as_unreached(tc)
% gfm_support_augment, gfm_support_release, sg_reclose and sg_reselection are
% outcomes, not requests. If the helper classified log types instead of
% scheduled types, every run would report phantom misses.
r = run_fixture({'sg_trip'}, ...
                {'sg_trip',true;'gfm_support_augment',true; ...
                 'gfm_support_release',true;'sg_reclose',true; ...
                 'sg_reselection',false});
[ex,nx] = ieee14_event_execution(r,arm(''));
tc.verifyEqual(ex,{'sg_trip'});
tc.verifyEmpty(nx, ...
    'a refused sg_reselection is a supervisor outcome, not an unreached request');
end

% ==========================================================================
% 4. Declaration errors fail closed rather than reporting a phantom miss.
% ==========================================================================

function test_a_defining_event_the_schedule_never_armed_is_an_error(tc)
% Without this the contradiction shows up as a permanent unexplained
% NOT EXECUTED, which reads as a physics result rather than a typo.
r = run_fixture({'sg_trip','fault_on'},{'sg_trip',true;'fault_on',true});
tc.verifyError(@() ieee14_event_execution(r,arm('line_fault_clear')), ...
    'ieee14_event_execution:definingEventNotScheduled');
end

function test_the_error_names_both_the_declared_event_and_the_schedule(tc)
r = run_fixture({'sg_trip','fault_on'},{'sg_trip',true;'fault_on',true});
try
    ieee14_event_execution(r,arm('line_fault_clear'));
    tc.verifyFail('expected an error');
catch me
    tc.verifySubstring(me.message,'line_fault_clear');
    tc.verifySubstring(me.message,'fault_on');
    tc.verifySubstring(me.message,'fixture_arm');
end
end

function test_no_declared_defining_event_is_not_a_miss(tc)
r = run_fixture({'sg_trip'},{'sg_trip',true});
[~,~,def,ok] = ieee14_event_execution(r,arm(''));
tc.verifyEmpty(def);
tc.verifyTrue(ok, ...
    'nothing declared means nothing to fall short of; false would be a phantom miss');
end

function test_an_arm_without_the_field_at_all_is_accepted(tc)
% run_ieee14_gfm_lock_comparison's rows have no defining_event field. The helper
% must not require callers to add one.
r = run_fixture({'sg_trip'},{'sg_trip',true});
a = arm(''); a = rmfield(a,'defining_event');
[~,~,def,ok] = ieee14_event_execution(r,a);
tc.verifyEmpty(def);
tc.verifyTrue(ok);
end

% ==========================================================================
% 5. Degenerate inputs.
% ==========================================================================

function test_an_empty_schedule_yields_empty_lists(tc)
r = run_fixture({},{});
[ex,nx,~,ok] = ieee14_event_execution(r,arm(''));
tc.verifyEmpty(ex);
tc.verifyEmpty(nx);
tc.verifyTrue(ok);
end

function test_a_schedule_with_an_empty_log_reports_everything_unreached(tc)
% A run that failed before its first event: nothing applied, so nothing executed.
r = run_fixture({'sg_trip','fault_on'},{});
[ex,nx,~,ok] = ieee14_event_execution(r,arm('fault_on'));
tc.verifyEmpty(ex);
tc.verifyEqual(nx,{'sg_trip','fault_on'});
tc.verifyFalse(ok);
end

function test_string_typed_event_types_are_handled(tc)
% run_hybrid_case writes r.events(k).type as char, but the log types arrive as
% string in some paths. Both must compare equal or every event reads unreached.
r = struct();
r.events = struct('type',{"sg_trip","load_step"},'t',{20,50});
r.event_log = struct('type',{'sg_trip','load_step'},'t',{20,50}, ...
    'applied',{true,true});
[ex,nx] = ieee14_event_execution(r,arm('load_step'));
tc.verifyEqual(ex,{'sg_trip','load_step'});
tc.verifyEmpty(nx);
end

% ==========================================================================
% 6. The delivered artifacts, if they are present.
% ==========================================================================

function test_the_delivered_caches_reproduce_the_reported_split(tc)
% Reads the shipped summary rather than re-running: the point is that the
% reported split is what the helper produces from those very results, so a later
% edit to either side is caught.
f = fullfile(fileparts(mfilename('fullpath')),'..','output','diagnostics', ...
    'ieee14_scenario_suite','summary.mat');
tc.assumeTrue(isfile(f), ...
    'suite summary absent; run run_ieee14_scenario_suite to generate it');
S = load(f);
sc = S.summary.scenarios;
got = containers.Map({sc.id},{sc.defining_event_executed});
expect = {'sg_load_step30',true; 'sg_fault_bus9',false; ...
          'line_fault_9_14',false; 'former_outage',true};
for k = 1:size(expect,1)
    id = expect{k,1};
    tc.assumeTrue(got.isKey(id));
    tc.verifyEqual(logical(got(id)),expect{k,2}, ...
        sprintf('%s defining_event_executed changed',id));
end
end

% ==========================================================================
% Fixtures
% ==========================================================================

function r = run_fixture(scheduled,log_rows)
%RUN_FIXTURE  Minimal result struct carrying only what the helper reads.
r = struct();
if isempty(scheduled)
    r.events = struct('type',{},'t',{});
else
    ts = num2cell(10*(1:numel(scheduled)));
    r.events = struct('type',scheduled(:).','t',ts);
end
if isempty(log_rows)
    r.event_log = struct('type',{},'t',{},'applied',{});
else
    n = size(log_rows,1);
    r.event_log = struct('type',log_rows(:,1).', ...
        't',num2cell(10*(1:n)),'applied',log_rows(:,2).');
end
end

function a = arm(defining)
a = struct('id','fixture_arm','defining_event',defining);
end
