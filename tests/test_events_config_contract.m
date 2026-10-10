function tests = test_events_config_contract()
%TEST_EVENTS_CONFIG_CONTRACT  The events/ configuration system (Phase B).
%   Contract for the hand-editable event files in <root>/events/ and the
%   machinery in <root>/+events/:
%
%     * every events/evt_*.m round-trips through +events/load + validate
%     * ds=0, trip < t_fault+ds, Zf=0 and an unknown fault_bus each raise
%       their NAMED id
%     * opt.t_clear == opt.t_fault + ev.ds EXACTLY, for every file
%     * resolve DEFERS value and ordering checks to the runtime: a negative
%       control shows fault_bus=999 rejected by stability.ibr_event_schedule
%       itself, and an out-of-order sequence rejected by its badOrdering gate
%     * +events/list fails closed on a shadowed definition, and is lazy
%
%   See also: events.SCHEMA, events.LIST, events.LOAD, events.VALIDATE,
%   events.RESOLVE, stability.IBR_EVENT_SCHEDULE, stability.TS_SIMULATE.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root, 'tests'));
pf_init_paths();
tc.TestData.root = root;
% A real case, for the fault_bus-against-the-network checks. Loading it reads
% no solved state and runs no solver.
tc.TestData.ieee14 = cases.case_ieee14bus();
end

% =========================================================================
% 1. The hand-editable files themselves
% =========================================================================

function test_every_event_file_round_trips(tc)
entries = events.list();
tc.verifyGreaterThanOrEqual(numel(entries), 4, ...
    'The four production event files must be discovered.');

for k = 1:numel(entries)
    e = entries(k);
    tc.verifyEqual(e.name, ['evt_' e.id], ...
        'The evt_ prefix and the ID must agree.');
    tc.verifyNotEmpty(e.file);
    tc.verifyTrue(isa(e.loader, 'function_handle'), ...
        'list() must attach a loader handle without executing it.');
    ev = events.load(e.id);
    events.validate(ev);   % must not throw
    tc.verifyEqual(ev.schema_version, 'events_config/1.0');
    % ds is the sole authority: the clearing instant is NEVER stored.
    tc.verifyFalse(isfield(ev, 'fault_clear'), ...
        ['An event file must not store fault_clear: it is always derived ' ...
         'as t_fault + ds, so storing it would let the two disagree.']);
end
end

function test_every_event_file_agrees_with_its_case_network(tc)
% fault_bus is only meaningful against the case the file NAMES, so each file
% is resolved through its own declared case_id and validated against that
% case's bus list. A file whose fault bus belongs to a different network is
% caught here.
entries = events.list();
for k = 1:numel(entries)
    ev = events.load(entries(k).id);
    case_data = case_for(tc, entries(k).id);
    tc.verifyNotEmpty(case_data, ...
        sprintf('%s declares case_id "%s", which must be a case the engine can load.', ...
            entries(k).id, ev.case_id));
    events.validate(ev, case_data);   % throws if fault_bus is not a bus
    bus_ids = bus_ids_of(case_data);
    tc.verifyTrue(any(bus_ids == ev.fault_bus), ...
        sprintf('%s: fault_bus %g must exist in case %s.', ...
            entries(k).id, ev.fault_bus, ev.case_id));
end
end

function test_event_folder_reaches_the_path_by_name(tc)
% The plain folder is only reachable by explicit name -- which is the whole
% reason every file is prefixed evt_. Verify the name resolves INSIDE it.
root = tc.TestData.root;
config_dir = fullfile(root, 'events');
resolved = which('evt_ne39_bus_fault');
tc.verifyNotEmpty(resolved, 'pf_init_paths must put events/ on the path.');
tc.verifyEqual(lower(fileparts(resolved)), lower(config_dir), ...
    'evt_ne39_bus_fault must resolve inside <root>/events/, not elsewhere.');
end

function test_events_package_wins_over_the_config_folder(tc)
% events.schema() must resolve to the PACKAGE, never to a plain-folder file.
% This is why no file in events/ is named schema.m.
resolved = which('events.schema');
tc.verifyNotEmpty(resolved);
tc.verifySubstring(lower(resolved), [filesep '+events' filesep]);
end

function test_load_accepts_id_and_explicit_path(tc)
root = tc.TestData.root;
by_id = events.load('ne39_bus_fault');
by_name = events.load('evt_ne39_bus_fault');
by_path = events.load(fullfile(root, 'events', 'evt_ne39_bus_fault.m'));
tc.verifyTrue(isequal(by_id, by_name));
tc.verifyTrue(isequal(by_id, by_path));
tc.verifyError(@() events.load('no_such_event_anywhere'), 'events:load:unknownEvent');
end

function test_load_refuses_a_path_outside_the_config_folder(tc)
stray = fullfile(tc.TestData.root, 'tmp', 'evt_stray_probe.m');
make_file(stray, 'evt_stray_probe', 'ev = struct();');
cleanup = onCleanup(@() remove_file(stray)); %#ok<NASGU>
tc.verifyError(@() events.load(stray), 'events:load:badPath');
end

% =========================================================================
% 2. Named failure IDs
% =========================================================================

function test_nonpositive_duration_raises_named_id(tc)
ev = valid_event();
for bad = {0, -0.01, NaN, Inf, 1i, 'x'}
    broken = ev; broken.ds = bad{1};
    tc.verifyError(@() events.validate(broken), 'events:validate:nonPositiveDuration', ...
        sprintf('ds = %s must raise nonPositiveDuration.', mat2str(bad{1})));
end
end

function test_trip_before_clear_raises_named_id(tc)
ev = valid_event();
ev.trip = ev.t_fault + ev.ds - 0.01;
tc.verifyError(@() events.validate(ev), 'events:validate:tripBeforeClear');
% Equality is legal: the combined profile requires fault_clear <= sg_trip,
% and clearing exactly when the machine trips is a meaningful choice.
at_clear = valid_event(); at_clear.trip = at_clear.t_fault + at_clear.ds;
tc.verifyWarningFree(@() events.validate(at_clear));
end

function test_bad_impedance_raises_named_id(tc)
ev = valid_event();
for bad = {0, 0+0i, NaN, Inf, 1i*NaN}
    broken = ev; broken.Zf = bad{1};
    tc.verifyError(@() events.validate(broken), 'events:validate:badZf');
end
end

function test_unknown_fault_bus_raises_named_id(tc)
ev = valid_event();
case_data = tc.TestData.ieee14;
ev.fault_bus = 999;
tc.verifyError(@() events.validate(ev, case_data), 'events:validate:unknownFaultBus');
% Malformed shapes are the same gate, with or without the case in hand.
for bad = {0, -3, 4.5, NaN, 1i}
    broken = valid_event(); broken.fault_bus = bad{1};
    tc.verifyError(@() events.validate(broken), 'events:validate:unknownFaultBus');
end
% A bus list is required to make the membership claim at all: fail closed.
tc.verifyError(@() events.validate(ev, struct('base_values', struct())), ...
    'events:validate:badSchema');
end

function test_missing_values_raise_missing_field(tc)
for field = {'fault_bus', 'ds', 'Zf'}
    broken = valid_event();
    broken.(field{1}) = [];
    tc.verifyError(@() events.validate(broken), 'events:validate:missingField', ...
        sprintf('%s = [] must raise missingField.', field{1}));
end
broken = valid_event(); broken.profile = '';
tc.verifyError(@() events.validate(broken), 'events:validate:missingField');
end

function test_unknown_field_fails_closed(tc)
ev = valid_event();
ev.faultbus = 16;   % the typo this rule exists for
tc.verifyError(@() events.validate(ev), 'events:validate:badSchema');
end

function test_bad_case_id_raises_named_id(tc)
for bad = {'', 'Not A Case', 'Ieee14', '9bus'}
    broken = valid_event(); broken.case_id = bad{1};
    tc.verifyError(@() events.validate(broken), 'events:validate:badCaseId', ...
        sprintf('case_id "%s" must raise badCaseId.', bad{1}));
end
broken = valid_event(); broken.case_id = 14;
tc.verifyError(@() events.validate(broken), 'events:validate:badCaseId');
end

function test_bad_event_instant_raises_named_id(tc)
for field = {'t_fault', 'trip', 'sg_on'}
    for bad = {-1, Inf, NaN, 1i, 'x'}
        broken = valid_event();
        broken.(field{1}) = bad{1};
        tc.verifyError(@() events.validate(broken), 'events:validate:badFaultTime', ...
            sprintf('%s = %s must raise badFaultTime.', field{1}, mat2str(bad{1})));
    end
end
% [] is not a bad instant for trip/sg_on: it means "not armed".
for field = {'trip', 'sg_on'}
    unarmed = valid_event(); unarmed.(field{1}) = [];
    tc.verifyWarningFree(@() events.validate(unarmed));
end
end

function test_bad_analysis_raises_named_id(tc)
ev = valid_event();
for bad = {'pf', 'sssa', '', 'TS '}
    tc.verifyError(@() events.validate(ev, [], bad{1}), 'events:validate:badAnalysis');
end
tc.verifyWarningFree(@() events.validate(ev, [], 'ts'));
tc.verifyWarningFree(@() events.validate(ev, [], 'ibr'));
end

function test_bad_schema_raises_named_id(tc)
tc.verifyError(@() events.validate(42), 'events:validate:badSchema');
tc.verifyError(@() events.validate(struct()), 'events:validate:badSchema');
broken = valid_event(); broken.schema_version = 'events_config/2.0';
tc.verifyError(@() events.validate(broken), 'events:validate:badSchema');
% A record missing a whole field is a missing value, not a broken schema.
broken = valid_event(); broken = rmfield(broken, 'notes');
tc.verifyError(@() events.validate(broken), 'events:validate:missingField');
end

% =========================================================================
% 3. The derived clearing instant, EXACTLY
% =========================================================================

function test_t_clear_is_exactly_t_fault_plus_ds(tc)
% Every file, against its OWN case (an event's fault bus is only meaningful
% against the network it names).
entries = events.list();
for k = 1:numel(entries)
    ev = events.load(entries(k).id);
    case_data = case_for(tc, entries(k).id);
    if isempty(case_data)
        continue;   % the copy-me template names a case, not a disturbance
    end
    opt = events.resolve(ev, case_data, struct('analysis', 'ts'));
    tc.verifyEqual(opt.t_clear, opt.t_fault + ev.ds, 'AbsTol', 0, ...
        sprintf('%s: t_clear must equal t_fault + ds to the last bit.', entries(k).id));
    tc.verifyTrue(opt.t_clear == opt.t_fault + ev.ds, ...
        'The equality must hold exactly, not within a tolerance.');
    tc.verifyTrue(opt.fault_enabled);
    tc.verifyEqual(opt.fault_bus, ev.fault_bus);
    tc.verifyEqual(opt.Zf, ev.Zf);
    if isempty(ev.t_fault)
        tc.verifyEqual(opt.t_fault, events.schema().t_fault, 'AbsTol', 0);
    else
        tc.verifyEqual(opt.t_fault, ev.t_fault, 'AbsTol', 0);
    end
end
end

function test_one_edit_to_ds_moves_the_clearing_instant(tc)
% The whole point of ds being the single authority: changing it moves the
% clearing instant, and moves nothing else. The two durations are powers of
% two and t_fault is 1.0, so the arithmetic here is exact and the assertion
% can be bit-exact WITHOUT a tolerance hiding anything.
case_data = tc.TestData.ieee14;
ev = events.load('ieee14_bus_fault');
ev.ds = 0.25;
a = events.resolve(ev, case_data, struct('analysis', 'ts'));
ev.ds = 0.50;
b = events.resolve(ev, case_data, struct('analysis', 'ts'));
tc.verifyEqual(b.t_clear - a.t_clear, 0.25, 'AbsTol', 0);
tc.verifyEqual(a.t_fault, b.t_fault, 'AbsTol', 0);
end

function test_empty_t_fault_takes_the_schema_default(tc)
% [] in an event file means "take the derived default", and that default
% lives in events.schema -- one authority, not one copy per file.
case_data = tc.TestData.ieee14;
ev = events.load('ieee14_bus_fault');
ev.t_fault = [];
opt = events.resolve(ev, case_data, struct('analysis', 'ts'));
tc.verifyEqual(opt.t_fault, events.schema().t_fault, 'AbsTol', 0);
tc.verifyEqual(opt.t_clear, events.schema().t_fault + ev.ds, 'AbsTol', 0);
end

% =========================================================================
% 4. The IBR launcher ABI, and what resolve DEFERS
% =========================================================================

function test_ibr_arm_uses_the_schedule_field_names(tc)
% ibr_event_schedule says fault_on/fault_clear/event_profile -- NOT the
% ts_simulate names t_fault/t_clear/profile. If that ever changes, this test
% is the tripwire.
case_data = tc.TestData.ieee14;
ev = events.load('ieee14_bus_fault');
ev.trip = ev.t_fault + ev.ds + 0.05;
ev.sg_on = ev.trip + 0.5;
opt = events.resolve(ev, case_data, struct('analysis', 'ibr'));

tc.verifyTrue(opt.ibr_events.enabled);
tc.verifyEqual(opt.ibr_events.fault_bus, ev.fault_bus);
tc.verifyEqual(opt.ibr_events.Zf, ev.Zf);
tc.verifyEqual(opt.ibr_events.fault_on, ev.t_fault, 'AbsTol', 0);
tc.verifyEqual(opt.ibr_events.fault_clear, ev.t_fault + ev.ds, 'AbsTol', 0);
tc.verifyEqual(opt.ibr_events.event_profile, ev.profile);
tc.verifyEqual(opt.ibr_events.sg_trip, ev.trip);
tc.verifyEqual(opt.ibr_events.sg_on, ev.sg_on);
% The ts_simulate names must NOT leak into the ibr arm.
tc.verifyFalse(isfield(opt.ibr_events, 't_fault'));
tc.verifyFalse(isfield(opt.ibr_events, 't_clear'));

% An unarmed event is an ABSENT field, not an empty one.
unarmed = events.load('rts24_bus_fault');
opt = events.resolve(unarmed, [], struct('analysis', 'ibr'));
tc.verifyFalse(isfield(opt.ibr_events, 'sg_trip'));
tc.verifyFalse(isfield(opt.ibr_events, 'sg_on'));
end

function test_resolve_defers_fault_bus_to_the_runtime_gate(tc)
% The negative control. resolve must NOT repair a bad value: it hands it to
% the runtime unmodified, and the runtime's own gate is what rejects it.
case_data = tc.TestData.ieee14;
ev = events.load('ieee14_bus_fault');
ev.fault_bus = 999;

% With the case in hand, the cheap UI gate refuses it by name...
tc.verifyError(@() events.validate(ev, case_data), 'events:validate:unknownFaultBus');
tc.verifyError(@() events.resolve(ev, case_data, struct('analysis', 'ibr')), ...
    'events:validate:unknownFaultBus');

% ...and with no case, resolve passes 999 through UNTOUCHED (no clipping,
% no substitution), so the schedule is the thing that rejects it.
opt = events.resolve(ev, [], struct('analysis', 'ibr'));
tc.verifyEqual(opt.ibr_events.fault_bus, 999);
devices = struct('device_id', {'SG1', 'IBR2'});
tc.verifyError(@() stability.ibr_event_schedule(case_data, devices, ...
    opt.ibr_events, 15, 0.01), 'stability:ibr_event_schedule:badFaultBus');
end

function test_resolve_defers_ordering_to_the_runtime_gate(tc)
% Same division for ORDER: validate catches the one inequality an operator
% can see without a capability row (trip before clear) and nothing else. A
% reclose that precedes the trip is the schedule's badOrdering gate.
case_data = tc.TestData.ieee14;
ev = events.load('ieee14_bus_fault');
ev.profile = 'combined';
ev.trip = ev.t_fault + ev.ds;      % exactly at clearing: legal
ev.sg_on = ev.t_fault;             % a reclose that precedes the trip

tc.verifyWarningFree(@() events.validate(ev, case_data), ...
    'validate must not duplicate the schedule''s ordering contract.');

opt = events.resolve(ev, [], struct('analysis', 'ibr'));
devices = struct('device_id', {'SG1', 'IBR2'});
tc.verifyError(@() stability.ibr_event_schedule(case_data, devices, ...
    opt.ibr_events, 15, 0.01), 'stability:ibr_event_schedule:badOrdering');
end

% =========================================================================
% 4b. Integration: the file really reaches the production TS engine
% =========================================================================

function test_event_file_reaches_ts_simulate_end_to_end(tc)
% The whole chain in one run: hand-editable FILE -> load -> resolve ->
% stability.ts_simulate, with the engine echoing the derived clearing instant
% back. A file that merely validates but never reaches the engine would pass
% every other test here.
ev = events.load('ieee14_bus_fault');
ev.ds = 0.15;
case_data = tc.TestData.ieee14;
opt = events.resolve(ev, case_data, struct('analysis', 'ts'));
opt.t_end = 5;
opt.dt = 0.01;
opt.verbose = false;
opt.plot_results = false;
r = stability.ts_simulate(case_data, opt);

tc.verifyEqual(r.fault_bus, ev.fault_bus);
tc.verifyEqual(r.t_fault, opt.t_fault, 'AbsTol', 0);
tc.verifyEqual(r.t_clear, opt.t_fault + ev.ds, 'AbsTol', 0, ...
    'The engine must see the DERIVED instant, not a stored one.');
tc.verifyEqual(r.Zf, ev.Zf);
tc.verifyGreaterThan(numel(r.t), 100);

% The fault window is real, not just an echo: some bus voltage inside
% fault_on..fault_clear is worse than any voltage outside it. Asserting the
% comparison rather than a magic minimum keeps this a contract test.
% r.Vbus is samples x buses.
in_window = r.t >= opt.t_fault & r.t <= opt.t_clear;
tc.verifyGreaterThan(nnz(in_window), 0);
tc.verifyLessThan(min(r.Vbus(in_window, :), [], 'all'), ...
    min(r.Vbus(~in_window, :), [], 'all'));
end

% =========================================================================
% 5. list(): fail closed, and lazy
% =========================================================================

function test_list_fails_closed_on_shadowed_definition(tc)
root = tc.TestData.root;
probe = 'evt_zzz_shadowprobe';
in_config = fullfile(root, 'events', [probe '.m']);
shadow_dir = fullfile(root, 'tmp', 'events_shadow_probe');
if ~exist(shadow_dir, 'dir'), mkdir(shadow_dir); end
shadow_file = fullfile(shadow_dir, [probe '.m']);
make_file(in_config, probe, 'ev = struct();');
cleanup = onCleanup(@() cleanup_shadow(probe, in_config, shadow_dir)); %#ok<NASGU>
make_file(shadow_file, probe, 'ev = struct();');

addpath(shadow_dir, '-begin');
tc.verifyEqual(lower(fileparts(which(probe))), lower(shadow_dir), ...
    'the probe must really be shadowed for this test to mean anything.');
tc.verifyError(@() events.list(), 'events:list:shadowedDefinition');

% And load() must refuse it for the same reason -- it resolves through list.
tc.verifyError(@() events.load(probe), 'events:list:shadowedDefinition');
end

function test_list_is_lazy_it_never_executes_a_file(tc)
% A file whose BODY throws must still be listed: opening a dropdown must
% never run configuration code, so list() cannot be allowed to call a loader.
root = tc.TestData.root;
probe = 'evt_zzz_brokenprobe';
file = fullfile(root, 'events', [probe '.m']);
make_file(file, probe, ...
    'error(''test_events_config:probeBodyRan'', ''list() must not execute this'');');
cleanup = onCleanup(@() remove_file(file)); %#ok<NASGU>

entries = events.list();
idx = find(strcmp('zzz_brokenprobe', {entries.id}), 1);
tc.verifyNotEmpty(idx, 'the broken probe must still be listed');
tc.verifyTrue(isa(entries(idx).loader, 'function_handle'));

% Calling it is a different matter -- load() runs the file and the error is
% the file's own, not something swallowed or replaced.
tc.verifyError(@() events.load('zzz_brokenprobe'), 'test_events_config:probeBodyRan');
end

% =========================================================================
% 6. describe(): the display rendering
% =========================================================================

function test_describe_reports_the_derived_clear_time(tc)
ev = events.load('ne39_bus_fault');
ev.ds = 0.07;
lines = events.describe(ev);
text = strjoin(lines, newline);
tc.verifySubstring(text, 'ne39');
tc.verifySubstring(text, 'fault_only');
tc.verifySubstring(text, 'DERIVED');
tc.verifySubstring(text, num2str(ev.t_fault + ev.ds, '%.15g'));
% It must not throw on a half-edited file -- that is what it is for.
half = events.schema();
tc.verifyWarningFree(@() events.describe(half));
empty_lines = events.describe(events.schema());
tc.verifyTrue(any(contains(empty_lines, '<unset>')));
end

% =========================================================================
% Helpers
% =========================================================================

function case_data = case_for(tc, event_id)
% The loaded case an event file names in its own case_id. Loading a case
% reads no solved state and runs no solver.
ev = events.load(event_id);
switch ev.case_id
    case 'ieee14', case_data = tc.TestData.ieee14;
    case 'ne39',   case_data = cases.case_ne39();
    case 'rts24',  case_data = cases.case_ieee_rts24_pgaz();
    case 'kundur', case_data = cases.kundur_ex126_book_case();
    otherwise,     case_data = [];
end
end

function ids = bus_ids_of(case_data)
if isfield(case_data, 'mpc') && isfield(case_data.mpc, 'bus')
    ids = case_data.mpc.bus(:, 1);
else
    ids = case_data.bus_data(:, 1);
end
end

function ev = valid_event()
% A fully set, valid record: the baseline every bad-value test perturbs.
ev = events.schema();
ev.case_id = 'ieee14';
ev.fault_bus = 4;
ev.ds = 0.10;
ev.Zf = 1i * 0.1;
ev.t_fault = 1.0;
end

function make_file(path, name, body)
folder = fileparts(path);
if ~exist(folder, 'dir'), mkdir(folder); end
fid = fopen(path, 'w');
if fid < 0
    error('test_events_config_contract:probeWrite', 'Cannot write probe %s.', path);
end
fprintf(fid, 'function ev = %s()\n%s\nend\n', name, body);
fclose(fid);
rehash path;
end

function remove_file(path)
if exist(path, 'file'), delete(path); end
rehash path;
end

function cleanup_shadow(probe, in_config, shadow_dir)
remove_file(in_config);
if exist(shadow_dir, 'dir')
    rmpath(shadow_dir);
    rmdir(shadow_dir, 's');
end
rehash path;
clear(probe);
end
