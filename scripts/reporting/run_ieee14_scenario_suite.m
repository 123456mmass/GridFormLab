function out = run_ieee14_scenario_suite(opts)
%RUN_IEEE14_SCENARIO_SUITE  Four added disturbance scenarios on the IEEE 14-bus case.
%
%   out = run_ieee14_scenario_suite()
%   out = run_ieee14_scenario_suite(scenarios=["former_outage"])
%   out = run_ieee14_scenario_suite(reuse_completed=false)
%
% The delivered study runs ONE chronology. Every published result therefore
% describes the framework's behaviour on a single sequence of disturbances.
% This runner adds four scenarios, each asking a question that sequence cannot
% express, on the SAME case, dispatch, solver and step control, so a difference
% between a scenario and the chronology is attributable to the disturbance
% sequence and to nothing else.
%
%   sg_load_step30   Island first, then the load grows 30 % on the island, then
%                    the machine is offered back. Can the converters absorb a
%                    step larger than the chronology's 20 %, and can the machine
%                    be resynchronised under that heavier load?
%
%   sg_fault_bus9    Island, then a bolted fault at bus 9 ridden through on the
%                    island, then reclose. The chronology faults the system
%                    while four converters are already forming; here the fault
%                    arrives earlier in the island's life.
%
%   line_fault_9_14  A fault ON a line, cleared the way protection clears one:
%                    both breakers of the faulted line open, so the line AND the
%                    fault leave the network together, and the line does NOT
%                    come back. Does the island adapt to a permanently reduced
%                    network, and do the promoted converters still hand back
%                    after the machine returns?
%
%   former_outage    The converter that OWNS the island angle reference is lost.
%                    No reclose is scheduled. Either the framework promotes a
%                    surviving converter to carry the reference, or it refuses
%                    fail-closed because no authenticated configuration survives.
%                    BOTH are results; neither is tuned for.
%
% Each scenario row owns its event schedule and its declared expectation, and the
% merge onto the shared base is asserted field by field, so "the scenarios differ
% only in their disturbance sequence" is a property of the code rather than a
% claim in a comment.
%
% Classification: reporting/diagnostic study over production runs. No value
% computed here feeds PF, SSSA, TS, a selector, a controller, or an acceptance
% decision in any production path.

arguments
    opts.scenarios (1,:) string = ["sg_load_step30","sg_fault_bus9", ...
        "line_fault_9_14","former_outage"]
    opts.reuse_completed (1,1) logical = true
    opts.t_end (1,1) double = 120
    opts.dt (1,1) double = 0.05
    opts.outdir (1,1) string = ""
    opts.return_results (1,1) logical = false
end

pf_init_paths();
outdir = char(opts.outdir);
if isempty(outdir)
    % Its own directory. The delivered six-arm caches live in
    % output/diagnostics/ieee14_gfm_lock_compare_zeta and are read by the report
    % and deck generators; writing anywhere near them would put a delivered
    % artifact at risk.
    outdir = fullfile('output','diagnostics','ieee14_scenario_suite');
end
if ~isfolder(outdir), mkdir(outdir); end

rows = scenario_table();
keep = false(1,numel(rows));
for k = 1:numel(opts.scenarios)
    j = find(strcmp({rows.id},char(opts.scenarios(k))),1);
    if isempty(j)
        error('run_ieee14_scenario_suite:unknownScenario', ...
            'Unknown scenario "%s". Known scenarios: %s.', ...
            char(opts.scenarios(k)), strjoin({rows.id},', '));
    end
    keep(j) = true;
end
rows = rows(keep);

[base_events, base_opt, shared] = base_request(opts.t_end, opts.dt);

out = struct();
out.schema = 'ieee14_scenario_suite/1.0';
out.classification = 'REPORTING_DIAGNOSTIC_OVER_PRODUCTION_RUNS';
out.outdir = outdir;
out.t_end_requested = opts.t_end;
out.dt = opts.dt;
out.generated_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
out.shared = shared;
out.scenarios = struct([]);

for k = 1:numel(rows)
    a = rows(k);
    [ev,op] = realize_scenario(a,base_events,base_opt);
    assert_only_declared_differences(a,base_events,base_opt,ev,op);
    op.ibr_events = ev;

    cache = fullfile(outdir,a.artifact);
    [r,elapsed,reused] = load_or_run(a,cache,op,opts.reuse_completed);

    m = ieee14_arm_metrics(r,a,opts.t_end);
    m.wall_time_s = elapsed;
    m.reused_cache = reused;
    m.artifact = cache;
    % expectation_met answers "was a usable trajectory produced". It does NOT
    % answer "did the run reach the disturbance this scenario was built around",
    % and for TRAJECTORY_THEN_ANY the two come apart: three of these scenarios
    % stop early, two of them BEFORE their own defining event. Recording the
    % split here puts that fact in the artifact and the manifest instead of
    % leaving it to prose written beside them.
    [m.events_executed,m.events_not_executed,m.defining_event, ...
        m.defining_event_executed] = ieee14_event_execution(r,a);
    if isempty(out.scenarios), out.scenarios = m; else, out.scenarios(end+1) = m; end %#ok<AGROW>
    print_scenario(m,r);
    if opts.return_results, out.results.(a.id) = r; end
end

out.comparison = struct( ...
    'note',['Per-scenario figures live in ' ...
            'generate_ieee14_scenario_suite_figures, which loads these caches ' ...
            'one at a time. Nothing is compared here so this runner never ' ...
            'holds two full trajectories in memory at once.'], ...
    'scenario_ids',{{out.scenarios.id}}, ...
    'expectation_all_met',all([out.scenarios.expectation_met]), ...
    'defining_event_all_executed',all([out.scenarios.defining_event_executed]));

summary_file = fullfile(outdir,'summary.mat');
summary = out; %#ok<NASGU>
save(summary_file,'summary','-v7');
fprintf('\nwrote %s\n',summary_file);
write_provenance(outdir,out,rows);
if ~all([out.scenarios.expectation_met])
    bad = {out.scenarios(~[out.scenarios.expectation_met]).id};
    fprintf('EXPECTATION NOT MET: %s\n',strjoin(bad,', '));
end
% Printed unconditionally and separately from the expectation line, because a
% scenario can satisfy TRAJECTORY_THEN_ANY and still never reach the disturbance
% it exists to exercise. Reading only the expectation line would miss that.
short = out.scenarios(~[out.scenarios.defining_event_executed]);
if isempty(short)
    fprintf('DEFINING EVENT REACHED: all %d scenario(s)\n',numel(out.scenarios));
else
    for k = 1:numel(short)
        fprintf(['STOPPED BEFORE ITS DEFINING EVENT: %s (%s never executed; ' ...
            'stopped at %.6f s)\n'],short(k).id,short(k).defining_event, ...
            short(k).t_end_s);
    end
end
end

% ==========================================================================
function rows = scenario_table()
%SCENARIO_TABLE  The four added scenarios. Each row owns its event schedule.
%   event_overrides go into opt.ibr_events; opt_overrides go top level. Both
%   are merged onto ONE shared base and the merge is asserted field by field.
%
%   Expectation tokens are the existing ones (ieee14_arm_metrics.check_expectation):
%     REACHES_T_END       must reach the requested horizon, converged, no failure
%     TRAJECTORY_THEN_ANY must integrate past the SG trip; where it ends is the
%                         measurement, so no horizon is demanded
%     FAILS_CLOSED        must refuse with a NAMED identifier at the SG trip
%   No new token is introduced, so ieee14_arm_metrics is untouched.
%
%   Every scenario here uses TRAJECTORY_THEN_ANY. That is not laziness: these are
%   new disturbance sequences whose outcome is the thing being measured. Demanding
%   REACHES_T_END would turn a legitimate fail-closed refusal -- the honest answer
%   for a configuration the framework cannot certify -- into a test failure, and
%   the temptation would then be to relax a gate to make it pass. FAILS_CLOSED is
%   equally wrong: it is strict about stopping AT THE SG TRIP, which none of these
%   is expected to do. The horizon each scenario actually reaches is reported and
%   is the result.
%
%   defining_event names the ONE event each scenario exists to exercise. It is
%   deliberately NOT part of the expectation: a run that stops before its own
%   event has still measured something real, and folding this into the pass/fail
%   token would recreate the pressure to tune. It is reported separately, on its
%   own line, so "the expectation was met" can never be read as "the scenario
%   answered its question" when it did not.
rows = struct('id',{},'label',{},'short_label',{},'scenario_fn',{}, ...
    'event_overrides',{},'opt_overrides',{},'expectation',{}, ...
    'expected_failure_id',{},'artifact',{},'color',{},'line_style',{}, ...
    'classification',{},'question',{},'defining_event',{});

% --- 1. SG trip, then a 30 % load step, then reclose ----------------------
% The chronology steps the load 20 % (base_request in
% run_ieee14_gfm_lock_comparison.m). 30 % is a strictly harder step on the same
% constant-impedance load model, so the comparison is one number apart.
rows(1) = struct( ...
    'id','sg_load_step30', ...
    'label','SG trip, +30 % load step on the island, then SG reclose', ...
    'short_label','load +30 %', ...
    'scenario_fn',@eecon49_scenario, ...
    'event_overrides',struct( ...
        'event_profile','sg_load_cycle', ...
        'sg_trip',20,'load_step',50,'load_step_factor',0.30,'sg_on',80, ...
        'fault_bus',[],'Zf',[],'fault_on',[],'fault_clear',[], ...
        'line_trip',[],'line_from_bus',[],'line_to_bus',[],'restore_time',[]), ...
    'opt_overrides',struct(), ...
    'expectation','TRAJECTORY_THEN_ANY', ...
    'expected_failure_id','', ...
    'artifact','sg_load_step30.mat', ...
    'color',[0.00 0.45 0.74], ...
    'line_style','-', ...
    'classification','PROJECT_RESULT', ...
    'question',['Can the island absorb a load step half again larger than the ' ...
        'chronology''s, and can the machine be resynchronised under it?'], ...
    'defining_event','load_step');

% --- 2. SG trip, then a bolted fault at bus 9, then reclose ---------------
% Same fault bus and same Zf as the chronology, so the fault itself is not a new
% quantity; what is new is that it arrives while the island is younger and fewer
% converters have been promoted.
rows(2) = struct( ...
    'id','sg_fault_bus9', ...
    'label','SG trip, bolted fault at bus 9 ridden through on the island, then SG reclose', ...
    'short_label','bus-9 fault', ...
    'scenario_fn',@eecon49_scenario, ...
    'event_overrides',struct( ...
        'event_profile','sg_fault_cycle', ...
        'sg_trip',20,'fault_on',50,'fault_clear',50.15, ...
        'fault_bus',9,'Zf',0.01+0.01i,'sg_on',80, ...
        'load_step',[],'load_step_factor',[], ...
        'line_trip',[],'line_from_bus',[],'line_to_bus',[],'restore_time',[]), ...
    'opt_overrides',struct(), ...
    'expectation','TRAJECTORY_THEN_ANY', ...
    'expected_failure_id','', ...
    'artifact','sg_fault_bus9.mat', ...
    'color',[0.85 0.33 0.10], ...
    'line_style','-', ...
    'classification','PROJECT_RESULT', ...
    'question',['Does the island ride a bolted fault through and still pass ' ...
        'every synchronism gate afterwards?'], ...
    'defining_event','fault_clear');

% --- 3. A line fault cleared by opening the line, permanently -------------
% Branch 9-14 is the choice, and the reason is topological. Bus 9's four
% incident branches are 4-9 and 7-9 (both TRANSFORMERS: taps 0.969 and an
% X-only unit, case_matpower6_case14.m rows 9 and 15) and the lines 9-10 and
% 9-14 (rows 16 and 17). Opening a transformer is not a line trip. Of the two
% lines, 9-14 is chosen because bus 14 keeps its 13-14 path and bus 9 keeps
% three, so no bus is stranded and per_island_vf_check still sees one energized
% island -- the scenario tests adaptation to a weaker network, not survival of
% an accidental islanding.
%
% NOTE the fault model, stated not hidden: this repository has no mid-line fault
% (that needs an auxiliary node splitting the branch impedance, which changes
% mpc and therefore the selector fingerprint, making the run incomparable with
% the chronology). The fault is CLOSE-IN: on the line at the line side of the
% bus-9 breaker, represented by the bus-9 shunt while it is on, leaving the
% network with the line when the breakers open. Standard zero-distance
% approximation; not a claim of a mid-line location.
rows(3) = struct( ...
    'id','line_fault_9_14', ...
    'label','SG trip, fault on line 9-14 cleared by opening that line permanently, then SG reclose', ...
    'short_label','line 9-14 fault', ...
    'scenario_fn',@eecon49_scenario, ...
    'event_overrides',struct( ...
        'event_profile','line_fault_relay_clear', ...
        'sg_trip',20,'fault_on',50,'fault_bus',9,'Zf',0.01+0.01i, ...
        'line_fault_clear',50.15,'line_from_bus',9,'line_to_bus',14,'sg_on',90, ...
        'fault_clear',[],'load_step',[],'load_step_factor',[], ...
        'line_trip',[],'restore_time',[]), ...
    'opt_overrides',struct(), ...
    'expectation','TRAJECTORY_THEN_ANY', ...
    'expected_failure_id','', ...
    'artifact','line_fault_9_14.mat', ...
    'color',[0.47 0.67 0.19], ...
    'line_style','-', ...
    'classification','PROJECT_RESULT', ...
    'question',['With the faulted line gone for good, does the island adapt, and ' ...
        'do the promoted converters still hand back after the machine returns?'], ...
    'defining_event','line_fault_clear');

% --- 4. The reference-owning converter is lost ----------------------------
% ibr_trip_target='reference_owner' is resolved AT THE EVENT INSTANT from the
% published ownership, not pinned to a device index here. Which converter owns
% the reference at t = 60 s is an outcome of the severity supervisor, so pinning
% an index would silently test a different scenario if the supervisor's choice
% moved.
%
% No reclose is scheduled: sg_on is absent, and the sg_trip_then_former_outage
% profile does not require it. The question is whether the converters recover the
% reference on their own, and offering the machine back would answer a different
% question.
rows(4) = struct( ...
    'id','former_outage', ...
    'label','SG trip, then outage of the converter that owns the island angle reference', ...
    'short_label','former outage', ...
    'scenario_fn',@eecon49_scenario, ...
    'event_overrides',struct( ...
        'event_profile','sg_trip_then_former_outage', ...
        'sg_trip',20,'ibr_trip',60,'ibr_trip_target','reference_owner', ...
        'sg_on',[],'fault_bus',[],'Zf',[],'fault_on',[],'fault_clear',[], ...
        'load_step',[],'load_step_factor',[], ...
        'line_trip',[],'line_from_bus',[],'line_to_bus',[],'restore_time',[]), ...
    'opt_overrides',struct(), ...
    'expectation','TRAJECTORY_THEN_ANY', ...
    'expected_failure_id','', ...
    'artifact','former_outage.mat', ...
    'color',[0.49 0.18 0.56], ...
    'line_style','-', ...
    'classification','PROJECT_RESULT', ...
    'question',['When the converter holding the angle reference is lost, does the ' ...
        'framework promote a survivor, or refuse fail-closed because no ' ...
        'authenticated configuration survives?'], ...
    'defining_event','ibr_trip');
end

% ==========================================================================
function scenario = eecon49_scenario()
%EECON49_SCENARIO  The one case every scenario shares.
scenario = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));
end

% ==========================================================================
function [events,opt,shared] = base_request(t_end,dt)
%BASE_REQUEST  The shared option set, copied from the delivered six-arm runner
%   scripts/reporting/run_ieee14_gfm_lock_comparison.m:253-305, which in turn
%   copies the flagship driver plus agsi_reference=true. Keeping the option set
%   identical is what makes a difference between a scenario here and the
%   delivered chronology attributable to the disturbance sequence alone.
%
%   agsi_reference=true is required, not optional: the severity trace the figures
%   draw comes from that overlay, it defaults false, and
%   ieee14_switch_decision_signals cannot recover it afterwards because the
%   admittance log it needs exists only under the same flag.
%
%   The base EVENTS struct is the chronology's, so every field a scenario does
%   NOT use must be explicitly cleared in its event_overrides. That is deliberate:
%   the assertion below then proves each scenario declared every field it changed,
%   including the ones it removed.

sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);

scenario = eecon49_scenario();

% Pass the FULL scenario struct: the selector resolves its dispatch from
% scenario.config.dispatch or scenario.scenario_opt.dispatch, so handing it
% scenario.scenario_opt directly would silently certify every SG-online row at
% zero IBR active power.
selector_table = stability.ibr_selector_table(scenario.case_data, ...
    scenario.resources,scenario,struct());

events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',20,'load_step',50,'load_step_factor',0.20, ...
    'fault_on',85,'fault_clear',85.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',145,'sg_on',145,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));

opt = struct( ...
    't_end',t_end,'dt',dt,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',12,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).', ...
    'stepper','adaptive','reject_limit',20, ...
    'support_transition_certificate',true, ...
    'handback_efd_timescale','control', ...
    'agsi_reference',true, ...
    'selector_table',selector_table);

shared = struct( ...
    'scenario_id',scenario.scenario_id, ...
    'case_profile','eecon49_figure4', ...
    'selector_table_fingerprint',table_fingerprint(selector_table), ...
    'n_sg_off_configurations',numel(selector_table.sg_off.configurations), ...
    'agsi_reference_enabled',true, ...
    'base_runner','scripts/reporting/run_ieee14_gfm_lock_comparison.m', ...
    'base_events_profile','chronology (cleared per scenario)', ...
    'line_fault_model',['close-in (zero-distance): bus shunt while on, removed ' ...
        'with the line when both breakers open; NOT a mid-line fault']);
end

% ==========================================================================
function fp = table_fingerprint(T)
fp = '';
if isstruct(T) && isfield(T,'selector_table_fingerprint')
    fp = char(string(T.selector_table_fingerprint));
elseif isstruct(T) && isfield(T,'fingerprint')
    fp = char(string(T.fingerprint));
end
end

% ==========================================================================
function [ev,op] = realize_scenario(a,base_events,base_opt)
%REALIZE_SCENARIO  Merge this scenario's declared overrides onto the shared base.
%   An override set to [] REMOVES the field, which is how a scenario declares
%   that it does not schedule an event the chronology does. ibr_event_schedule
%   treats an empty field as absent anyway (isempty test at its required-field
%   check), but removing it keeps the realized struct honest about what the run
%   was asked to do.
ev = base_events;
f = fieldnames(a.event_overrides);
for k = 1:numel(f)
    v = a.event_overrides.(f{k});
    if isempty(v) && ~ischar(v)
        if isfield(ev,f{k}), ev = rmfield(ev,f{k}); end
    else
        ev.(f{k}) = v;
    end
end
op = base_opt;
f = fieldnames(a.opt_overrides);
for k = 1:numel(f), op.(f{k}) = a.opt_overrides.(f{k}); end
end

% ==========================================================================
function assert_only_declared_differences(a,base_events,base_opt,ev,op)
%ASSERT_ONLY_DECLARED_DIFFERENCES  The scenarios must differ ONLY where declared.
%   This is what makes "identical case, dispatch, solver and step control; only
%   the disturbance sequence differs" a property of the code. Without it a stray
%   edit to one scenario's option set would silently invalidate the comparison
%   against the delivered chronology.
check_struct(base_events,ev,fieldnames(a.event_overrides),'ibr_events',a.id);
check_struct(base_opt,op,fieldnames(a.opt_overrides),'opt',a.id);
end

function check_struct(base,realized,declared,label,scenario_id)
names = union(fieldnames(base),fieldnames(realized));
differing = {};
for k = 1:numel(names)
    n = names{k};
    hb = isfield(base,n); hr = isfield(realized,n);
    if ~hb || ~hr
        differing{end+1} = n; continue; %#ok<AGROW>
    end
    if ~isequaln(base.(n),realized.(n))
        differing{end+1} = n; %#ok<AGROW>
    end
end
extra = setdiff(differing,declared);
if ~isempty(extra)
    error('run_ieee14_scenario_suite:undeclaredOptionDifference', ...
        ['Scenario "%s" %s differs from the shared base in undeclared ' ...
         'field(s): %s. Every scenario must differ only in its declared ' ...
         'overrides.'], scenario_id,label,strjoin(extra,', '));
end
end

% ==========================================================================
function [r,elapsed,reused] = load_or_run(a,cache,op,reuse_completed)
%LOAD_OR_RUN  Reuse a cache only when it was produced by THIS request.
%   A cache whose recorded option signature differs from the signature the runner
%   would build now is rejected. The pattern is copied from
%   run_ieee14_gfm_lock_comparison.m:392-429, where its header records the trap it
%   closes: an option was added, the stale cache still looked complete, and the
%   missing field was only discovered by probing the file.
sig = opt_signature(op);
reused = false;
if reuse_completed && isfile(cache)
    S = load(cache);
    if isfield(S,'result') && isfield(S,'opt_signature') && ...
            isequaln(S.opt_signature,sig)
        r = S.result;
        elapsed = NaN;
        if isfield(S,'elapsed'), elapsed = S.elapsed; end
        reused = true;
        fprintf('[%s] reusing %s\n',a.id,cache);
        refresh_cached_arm(cache,a,S,a.id);
        return;
    end
    if isfield(S,'opt_signature')
        fprintf('[%s] cache rejected: option signature changed since it was written\n',a.id);
    else
        fprintf('[%s] cache rejected: no recorded option signature\n',a.id);
    end
end

scenario = a.scenario_fn();
fprintf('[%s] running %s ...\n',a.id,a.label);
t0 = tic;
r = stability.run_hybrid_case(scenario,op);
elapsed = toc(t0);
S = struct('result',r,'elapsed',elapsed,'arm',stored_arm(a),'opt_signature',sig);
save(cache,'-struct','S','-v7.3');
fprintf('[%s] wrote %s (%.1f s)\n',a.id,cache,elapsed);
end

% ==========================================================================
function row = stored_arm(a)
%STORED_ARM  The scenario declaration as it goes into the cache.
%   The function handle is flattened because a handle saved in a .mat reloads
%   bound to whatever that name means later, which is a silent provenance lie.
row = a;
row.scenario_fn = func2str(a.scenario_fn);
end

% ==========================================================================
function refresh_cached_arm(cache,a,S,id)
%REFRESH_CACHED_ARM  Keep a reused cache's DECLARATION current, not its result.
%   generate_ieee14_scenario_suite_figures reads its page metadata from the arm
%   stored in the cache, so a declaration that gained a field after the run was
%   made leaves the figure manifest reporting less than the runner does -- and
%   silently, because an absent field and an empty one look the same downstream.
%
%   Only the arm variable is rewritten, with -append: the trajectory, the timing
%   and the option signature are untouched, so this cannot turn a stale RESULT
%   into a fresh-looking one. That is the whole point of the split -- the option
%   signature above still governs whether the result may be reused at all, and a
%   declaration change that alters the RUN changes the signature and lands in the
%   rejection path instead of here.
want = stored_arm(a);
if isfield(S,'arm') && isequaln(S.arm,want), return; end
added = {};
if isfield(S,'arm')
    added = setdiff(fieldnames(want),fieldnames(S.arm));
end
arm = want; %#ok<NASGU> saved by name below
try
    save(cache,'arm','-append');
catch me
    warning('run_ieee14_scenario_suite:armRefreshFailed', ...
        ['Could not refresh the stored declaration in %s (%s). The result is ' ...
         'still valid; figure pages may report an older declaration.'], ...
        cache,me.identifier);
    return;
end
if isempty(added)
    fprintf('[%s] refreshed the stored scenario declaration\n',id);
else
    fprintf('[%s] refreshed the stored scenario declaration (added %s)\n', ...
        id,strjoin(added,', '));
end
end

% ==========================================================================
function sig = opt_signature(op)
%OPT_SIGNATURE  Comparable fingerprint of the realized request.
%   The selector table is replaced by its own fingerprint so the signature stays
%   small; everything else that changes the run is kept verbatim.
sig = op;
if isfield(sig,'selector_table')
    T = sig.selector_table;
    sig.selector_table = struct( ...
        'fingerprint',table_fingerprint(T), ...
        'n_sg_off',numel(T.sg_off.configurations));
end
end

% ==========================================================================
function print_scenario(m,r)
fprintf('\n--- %s ---\n',m.label);
fprintf('  expectation      %s  -> %s\n',m.expectation, ...
    ternary(m.expectation_met,'MET','NOT MET'));
fprintf('  converged        %d\n',m.converged);
fprintf('  horizon          %.6f s of %.6f s requested\n', ...
    m.t_end_s,m.requested_t_end_s);
if ~isempty(m.failure_id)
    fprintf('  failure_id       %s\n',m.failure_id);
    fprintf('  failure_reason   %s\n',m.failure_reason);
end
fprintf('  reclose          %s at %s s\n',m.reclose_status, ...
    num2str(m.actual_reclose_time));
% The defining event, printed right under the horizon so the two are read
% together. "expectation MET" plus "its own event never executed" is the exact
% pair a reader must not be allowed to miss.
if ~isempty(m.defining_event)
    fprintf('  defining event   %s -> %s\n',m.defining_event, ...
        ternary(m.defining_event_executed,'EXECUTED', ...
            'NOT EXECUTED (the run stopped first)'));
end
if ~isempty(m.events_not_executed)
    fprintf('  scheduled but not executed: %s\n', ...
        strjoin(m.events_not_executed,', '));
end
fprintf('  GFM units        %d at end, %d max\n',m.n_gfm_at_end,m.n_gfm_max);
fprintf('  support commits  %d applied, %d rejected\n', ...
    m.n_support_augment_applied,m.n_support_augment_rejected);
fprintf('  samples          %d\n',m.n_accepted_samples);
% The converter-outage transaction is the added capability, so its own outcome
% is printed rather than left to be read out of the event log by hand.
if isfield(r,'event_log') && ~isempty(r.event_log)
    ty = string({r.event_log.type});
    j = find(ty=="ibr_trip",1);
    if ~isempty(j)
        e = r.event_log(j);
        fprintf('  converter outage applied=%d at t=%.3f\n',e.applied,e.t);
        fprintf('    %s\n',char(string(e.details)));
    end
end
if isfield(r,'reference_owner_indices') && ~isempty(r.reference_owner_indices)
    fprintf('  final ref owner  %s\n',mat2str(r.reference_owner_indices));
end
end

function s = ternary(c,a,b)
if c, s = a; else, s = b; end
end

% ==========================================================================
function write_provenance(outdir,out,rows)
%WRITE_PROVENANCE  Plain-text manifest beside the caches.
%   Format follows generate_final_report_figures_th_v2.m:503-666: a key/value
%   header, then one block per artifact carrying its SHA-256, its mtime and the
%   gate it was accepted under. The point is that a later reader can tell WHICH
%   file produced a figure and whether it has changed since.
p = fullfile(outdir,'provenance.txt');
fid = fopen(p,'w');
if fid < 0
    warning('run_ieee14_scenario_suite:provenanceUnwritable', ...
        'Could not write %s; the caches are still valid.',p);
    return;
end
fprintf(fid,'generator: scripts/reporting/run_ieee14_scenario_suite.m\n');
fprintf(fid,'schema:    %s\n',out.schema);
fprintf(fid,'generated: %s\n',out.generated_utc);
fprintf(fid,'t_end:     %g s\n',out.t_end_requested);
fprintf(fid,'dt:        %g s\n',out.dt);
fprintf(fid,'case:      %s\n',out.shared.case_profile);
fprintf(fid,'selector_table_fingerprint: %s\n',out.shared.selector_table_fingerprint);
fprintf(fid,'sg_off_configurations:      %d\n',out.shared.n_sg_off_configurations);
fprintf(fid,'base_runner: %s\n',out.shared.base_runner);
fprintf(fid,'line_fault_model: %s\n',out.shared.line_fault_model);
fprintf(fid,'\n');
fprintf(fid,['Every scenario shares one case, one dispatch, one solver and one ' ...
    'step controller.\n  Only the disturbance sequence differs, and the merge ' ...
    'onto the shared base is\n  asserted field by field ' ...
    '(assert_only_declared_differences), so an undeclared\n  difference aborts ' ...
    'the run instead of producing an incomparable result.\n\n']);
fprintf(fid,['Expectation tokens are the existing ones. Every scenario here is ' ...
    'TRAJECTORY_THEN_ANY:\n  the horizon each one reaches IS the measurement, ' ...
    'so a fail-closed refusal is\n  reported as the result rather than treated ' ...
    'as a test failure. No gate is relaxed\n  to make a scenario reach its ' ...
    'horizon.\n\n']);
fprintf(fid,['READ THE TWO GATES SEPARATELY. "expectation MET" means a usable ' ...
    'trajectory was\n  produced past the SG trip. It does NOT mean the run ' ...
    'reached the disturbance the\n  scenario exists to exercise -- so each block ' ...
    'below also states its defining event\n  and whether that event actually ' ...
    'executed. A scenario can be MET and still have\n  been stopped before its ' ...
    'own event; two of these were.\n\n']);
fprintf(fid,['No simulation value is smoothed, filtered, clipped, offset, ' ...
    'padded or resampled.\n\n']);
for k = 1:numel(out.scenarios)
    m = out.scenarios(k);
    j = find(strcmp({rows.id},m.id),1);
    q = '';
    if ~isempty(j), q = rows(j).question; end
    fprintf(fid,'%-16s %s\n',m.id,m.label);
    fprintf(fid,'  question   %s\n',q);
    if isfile(m.artifact)
        d = dir(m.artifact);
        fprintf(fid,'  file       %s\n',m.artifact);
        fprintf(fid,'  sha256     %s\n',sha256_of(m.artifact));
        fprintf(fid,'  mtime      %s\n',char(datetime(d.datenum,'ConvertFrom','datenum', ...
            'Format','yyyy-MM-dd HH:mm:ss')));
        fprintf(fid,'  bytes      %d\n',d.bytes);
    else
        fprintf(fid,'  file       %s (MISSING)\n',m.artifact);
    end
    fprintf(fid,'  gate       expectation %s -> %s\n',m.expectation, ...
        ternary(m.expectation_met,'MET','NOT MET'));
    fprintf(fid,'  outcome    converged=%d horizon=%.6f s samples=%d\n', ...
        m.converged,m.t_end_s,m.n_accepted_samples);
    if ~isempty(m.defining_event)
        fprintf(fid,'  defining   %s -> %s\n',m.defining_event, ...
            ternary(m.defining_event_executed,'EXECUTED', ...
                'NOT EXECUTED, the run stopped first'));
    end
    if ~isempty(m.events_not_executed)
        fprintf(fid,'  unreached  %s\n',strjoin(m.events_not_executed,', '));
    end
    if ~isempty(m.failure_id)
        fprintf(fid,'  failure    %s\n',m.failure_id);
    end
    fprintf(fid,'\n');
end
fclose(fid);
fprintf('wrote %s\n',p);
end

% ==========================================================================
function sha = sha256_of(f)
%SHA256_OF  Hex SHA-256 of a file via Java, on an absolute path.
%   Same implementation as generate_final_report_figures_th_v2.m:1555, which is
%   a local function there and therefore not callable across files.
fj = char(java.io.File(f).getCanonicalPath());
h = java.security.MessageDigest.getInstance('SHA-256');
fis = java.io.FileInputStream(fj);
try
    buf = typecast(zeros(1,65536,'int8'),'uint8');
    while true
        n = fis.read(buf);
        if n < 0, break; end
        h.update(buf(1:n));
    end
catch err
    fis.close();
    rethrow(err);
end
fis.close();
sha = sprintf('%02x', reshape(typecast(h.digest(),'uint8'),1,[]));
end
