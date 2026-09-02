function sched = ibr_event_schedule(case_data, devices, ibr_events, t_end, dt)
%IBR_EVENT_SCHEDULE  Validate and build IBR event schedule (fail-closed).
%   SCHED = ibr_event_schedule(CASE_DATA, DEVICES, IBR_EVENTS, T_END, DT)
%   validates the opt-in IBR event struct and returns a normalized schedule.
%
%   API (example):
%     opt.ibr_events = struct('enabled',true,'fault_bus',4,'Zf',1i*0.1,...
%        'fault_on',1.0,'fault_clear',1.10,'sg_trip',1.20,'sg_on',3.0,...
%        'selected_gfm_indices',[2 3],'reference_resource_index',2);
%
%   Event profiles. Each profile declares WHICH events it arms (a capability
%   row) and its OWN admissible ordering. The first four are the original
%   profiles and their contracts are unchanged:
%
%     combined     fault_on < fault_clear <= sg_trip < sg_on
%     fault_only   fault_on < fault_clear
%     sg_cycle     sg_trip < sg_on
%     chronology   sg_trip < load_step < fault_on < fault_clear < line_trip
%                  < restore_time = sg_on
%
%   The four added profiles each answer one question that the chronology
%   cannot express, because the chronology ordering is a single fixed chain:
%
%     sg_load_cycle               sg_trip < load_step < sg_on
%                                 Can the island absorb a load step and then
%                                 take the machine back under that load?
%     sg_fault_cycle              sg_trip < fault_on < fault_clear < sg_on
%                                 Can the island ride a bus fault through and
%                                 still reclose?
%     line_fault_relay_clear      sg_trip < fault_on < line_fault_clear < sg_on
%                                 A fault ON A LINE, cleared the way protection
%                                 clears it: both breakers of the faulted line
%                                 open, so the line AND the fault leave the
%                                 network in ONE atomic transaction, and the
%                                 line does NOT come back (no restore_time).
%                                 Does the island adapt to the reduced network,
%                                 and do the promoted converters hand back?
%     sg_trip_then_former_outage  sg_trip < ibr_trip
%                                 The converter that owns the island angle
%                                 reference is lost. No reclose is scheduled:
%                                 the question is whether the framework
%                                 recovers the reference by itself.
%
%   Validation (fail-closed, no silent fallback):
%     - times finite, nonnegative, and ordered per the selected profile
%     - duplicate/coincident ambiguous events fail closed (tol 1e-12), except
%       fault_clear == sg_trip is explicitly allowed by the ordering contract.
%       restore_time is excluded from that check because the chronology
%       contract REQUIRES restore_time == sg_on.
%     - fault_bus valid external bus ID present in case_data.mpc.bus
%     - Zf valid finite non-zero complex
%     - selected_gfm_indices exact, unique, in-range, reference in selected
%     - ibr_trip_target is 'reference_owner' or one in-range IBR device index
%     - devices must be indexed struct array with device_id
%
%   Classification:
%     topology Yfault = Ypre; Yfault(fb,fb)+=1/Zf  SOURCE_DEFINED
%     ordering/duplication gates CASE_DEFINED / NUMERICAL_METHOD (tol)
%     index validation PROJECT_DERIVED
%     added profiles and their capability rows PROJECT_DERIVED
%
%   LIMITATION of line_fault_relay_clear (PROJECT_DERIVED, stated not hidden):
%   this repository has no mid-line fault model -- representing one requires
%   splitting the branch impedance at an auxiliary node, which changes
%   mpc.bus/mpc.branch and therefore the selector-table fingerprint, so a run
%   using it could not be compared against the delivered chronology. The
%   profile therefore models a CLOSE-IN (zero-distance) fault: the fault is on
%   the line at the line side of the bus-9 breaker, represented by the shunt at
%   bus 9 while it is on, and it leaves the network together with the line when
%   the breakers open. This is the standard zero-distance approximation in
%   protection studies; it is NOT a claim of a mid-line fault location.
%
%   Returns SCHED struct with normalized events sorted by time.

arguments
    case_data struct
    devices struct
    ibr_events struct
    t_end (1,1) double
    dt (1,1) double = 0.01
end

tol = 1e-12;

% --- Basic case_data validation -------------------------------------------
if ~isstruct(case_data) || ~isscalar(case_data) || ~isfield(case_data,'mpc')
    error('stability:ibr_event_schedule:badCaseData', ...
        'case_data must be scalar struct with .mpc MATPOWER field.');
end
mpc = case_data.mpc;
if ~isfield(mpc,'bus') || ~ismatrix(mpc.bus) || size(mpc.bus,1)<1
    error('stability:ibr_event_schedule:badCaseData', ...
        'case_data.mpc.bus invalid.');
end
bus_ids = mpc.bus(:,1);

if ~isfinite(t_end) || ~isreal(t_end) || t_end <= 0
    error('stability:ibr_event_schedule:badTEnd', ...
        't_end must be finite positive.');
end
if ~isfinite(dt) || ~isreal(dt) || dt <= 0
    error('stability:ibr_event_schedule:badDt', ...
        'dt must be finite positive.');
end

% --- enabled flag ----------------------------------------------------------
if ~isfield(ibr_events,'enabled')
    error('stability:ibr_event_schedule:missingEnabled', ...
        'ibr_events.enabled missing.');
end
enabled = ibr_events.enabled;
if ~isscalar(enabled) || ~(islogical(enabled) || isnumeric(enabled))
    error('stability:ibr_event_schedule:badEnabled', ...
        'enabled must be logical scalar.');
end
enabled = logical(enabled);

% If disabled, return minimal sched (caller treats as no-event)
if ~enabled
    sched = struct('enabled',false,'t_end',t_end,'dt',dt,'events',[]);
    return;
end

PROFILES = {'combined','fault_only','sg_cycle','chronology', ...
    'sg_load_cycle','sg_fault_cycle','line_fault_relay_clear', ...
    'sg_trip_then_former_outage'};
event_profile = 'combined';
if isfield(ibr_events,'event_profile') && ~isempty(ibr_events.event_profile)
    if ~(ischar(ibr_events.event_profile) || isstring(ibr_events.event_profile))
        error('stability:ibr_event_schedule:badEventProfile', ...
            'event_profile must be one of: %s.', strjoin(PROFILES,', '));
    end
    event_profile = validatestring(char(ibr_events.event_profile), PROFILES);
end

% --- Per-event capability flags (PROJECT_DERIVED) ------------------------
% Each profile declares WHICH events it arms, one flag per event type. The four
% original profiles keep exactly the capability set they always had, so their
% behaviour is unchanged; the four added profiles are new rows in the same
% table. The flags exist because the consumer (ts_simulate_ibr_hybrid.m:52)
% previously keyed the load-step and line-trip admittance stamps off
% has_chronology alone: a profile arming load_step without being 'chronology'
% would receive a ZERO stamp, and the event would report applied=true while
% changing nothing. Capability flags make that coupling explicit and per-event.
%
% sg_trip and sg_reclose are SEPARATE columns because one added profile trips
% the machine and deliberately schedules no reclose: the question it asks is
% whether the converters recover the angle reference on their own.
%
% sync_controller is its own column and is NOT implied by sg_reclose. The
% offline-SG synchronizer (initialize_sync_controller) has only ever been armed
% for 'chronology'; 'combined' and 'sg_cycle' have always reclosed without it.
% Deriving the flag from sg_reclose would arm it for those two and change
% results that are already published, so they keep false.
%
% Column order: profile, fault, sg_trip, sg_reclose, load_step, line_trip,
%               restore, line_fault_clear, ibr_trip, sync_controller
caps = { ...
    'combined',                    true,  true,  true,  false, false, false, false, false, false; ...
    'fault_only',                  true,  false, false, false, false, false, false, false, false; ...
    'sg_cycle',                    false, true,  true,  false, false, false, false, false, false; ...
    'chronology',                  true,  true,  true,  true,  true,  true,  false, false, true ; ...
    'sg_load_cycle',               false, true,  true,  true,  false, false, false, false, true ; ...
    'sg_fault_cycle',              true,  true,  true,  false, false, false, false, false, true ; ...
    'line_fault_relay_clear',      true,  true,  true,  false, false, false, true,  false, true ; ...
    'sg_trip_then_former_outage',  false, true,  false, false, false, false, false, true,  false};
crow = find(strcmp(caps(:,1),event_profile),1);
if isempty(crow)
    error('stability:ibr_event_schedule:badEventProfile', ...
        'Profile "%s" has no capability row.', event_profile);
end
has_fault            = caps{crow,2};
has_sg_trip          = caps{crow,3};
has_sg_reclose       = caps{crow,4};
has_load_step        = caps{crow,5};
has_line_trip        = caps{crow,6};
has_restore          = caps{crow,7};
has_line_fault_clear = caps{crow,8};
has_ibr_trip         = caps{crow,9};
has_sync_controller  = caps{crow,10};
% has_sg_cycle keeps its original meaning for the consumers that read it as
% "this profile involves the SG breaker at all" (sg_id resolution below,
% tests/test_ieee14_ibr_ts_event_runner.m:251,260).
has_sg_cycle         = has_sg_trip || has_sg_reclose;
% has_chronology remains the identity of the ORIGINAL profile, NOT a capability
% union. Two consumers read it as an identity: ts_simulate_ibr_hybrid.m:3922
% gates the chronology SG synchronizer on it, and ieee14_switch_event_marks.m
% derives its own copy from the presence of load_step. Widening it to a
% capability union would silently arm that synchronizer for the new profiles.
has_chronology = strcmp(event_profile,'chronology');

% 'line_fault_relay_clear' clears a line fault the way a protection scheme
% does: both breakers of the faulted line open, so the line AND the fault leave
% the network in ONE atomic transaction. It therefore arms has_line_fault_clear
% instead of has_line_trip plus a separate fault_clear. It needs the branch
% stamp all the same, so the stamp condition is the union of the two flags.
needs_line_stamp = has_line_trip || has_line_fault_clear;

% Normalize ibr_events FIRST to determine selection_request.mode, THEN decide
% which fields are required based on that mode. This closes the defect where
% automatic mode could not enter the schedule without a manual tuple.
% (Single normalization point: normalize_gfm_selection_request.)
norm_opt = struct('automatic_gfm_switching', true);
if isfield(ibr_events,'automatic_gfm_switching') && ...
        ~isempty(ibr_events.automatic_gfm_switching)
    norm_opt.automatic_gfm_switching = logical(ibr_events.automatic_gfm_switching);
end
% Pass raw manual fields if present (normalizer handles legacy mapping).
if isfield(ibr_events,'selected_gfm_indices') && ~isempty(ibr_events.selected_gfm_indices)
    norm_opt.selected_gfm_indices = ibr_events.selected_gfm_indices;
end
if isfield(ibr_events,'n_gfm_required') && ~isempty(ibr_events.n_gfm_required)
    norm_opt.n_gfm_required = ibr_events.n_gfm_required;
end
if isfield(ibr_events,'reference_resource_index') && ~isempty(ibr_events.reference_resource_index)
    norm_opt.reference_resource_index = ibr_events.reference_resource_index;
end
selection_request = stability.normalize_gfm_selection_request(norm_opt, devices, true);

% Required fields depend on selection_request.mode, NOT on automatic_gfm_switching flag.
% NOTE: for manual_override the input needs only selected_gfm_indices +
% reference_resource_index; n_gfm_required is DERIVED by the normalizer from
% numel(selected_gfm_indices) (2-field legacy mapping in
% normalize_gfm_selection_request). Requiring n_gfm_required as an input
% field here would reject the legitimate 2-field manual tuple (regression
% caught 2026-07-17: test_solve_case_ibr_logs_trip_counts_and_work). The
% post-normalization integrity check below verifies the derived request is
% complete.
required = {};
if has_fault
    % 'line_fault_relay_clear' raises the fault but clears it together with the
    % faulted line, so it requires fault_on WITHOUT fault_clear.
    if has_line_fault_clear
        required = [required, {'fault_bus','Zf','fault_on'}];
    else
        required = [required, {'fault_bus','Zf','fault_on','fault_clear'}];
    end
end
if has_sg_trip
    required = [required, {'sg_trip'}];
end
if has_sg_reclose
    required = [required, {'sg_on'}];
end
if has_load_step
    required = [required, {'load_step','load_step_factor'}];
end
if has_line_trip
    required = [required, {'line_trip','line_from_bus','line_to_bus'}];
end
if has_restore
    required = [required, {'restore_time'}];
end
if has_line_fault_clear
    required = [required, {'line_fault_clear','line_from_bus','line_to_bus'}];
end
if has_ibr_trip
    required = [required, {'ibr_trip','ibr_trip_target'}];
end
switch selection_request.mode
    case 'manual_override'
        if has_sg_cycle
            required = [required, {'selected_gfm_indices','reference_resource_index'}];
        end
    case 'automatic'
        % NO manual tuple required for automatic mode.
    case 'off'
        % No selection fields for firmware-off mode.
    otherwise
        error('stability:ibr_event_schedule:badMode', ...
            'selection_request.mode must be automatic/manual_override/off (got %s).', ...
            selection_request.mode);
end
for k=1:numel(required)
    if ~isfield(ibr_events,required{k}) || isempty(ibr_events.(required{k}))
        error('stability:ibr_event_schedule:missingField', ...
            'ibr_events.%s missing (required for mode=%s).', required{k}, selection_request.mode);
    end
end

% Post-normalization integrity check: the NORMALIZED selection_request must
% be complete for its mode (distinct from the raw-input check above, since
% the normalizer derives fields like n_gfm_required). This is the binding
% contract: input tuple must be derivable; normalized request must be whole.
switch selection_request.mode
    case 'manual_override'
        if ~isfield(selection_request,'manual_candidate') || ...
                ~isstruct(selection_request.manual_candidate) || ...
                isempty(selection_request.manual_candidate)
            error('stability:ibr_event_schedule:incompleteManualRequest', ...
                'manual_override selection_request lacks a complete manual_candidate after normalization.');
        end
        mc = selection_request.manual_candidate;
        if isempty(mc.selected_gfm_indices) || isempty(mc.n_gfm_required) || ...
                isempty(mc.reference_resource_index)
            error('stability:ibr_event_schedule:incompleteManualRequest', ...
                'manual_candidate tuple incomplete after normalization (selected/n_gfm_required/ref).');
        end
    case 'automatic'
        % automatic: no manual tuple; selector table owns the choice.
    case 'off'
        % off: firmware disabled; no selection fields.
end

fault_bus = NaN; Zf = NaN; fault_on = NaN; fault_clear = NaN;
sg_trip = NaN; sg_on = NaN;
load_step = NaN; line_trip = NaN; restore_time = NaN;
line_fault_clear = NaN; ibr_trip = NaN;
if has_fault
    fault_bus = ibr_events.fault_bus; Zf = ibr_events.Zf;
    fault_on = ibr_events.fault_on;
    if ~has_line_fault_clear
        fault_clear = ibr_events.fault_clear;
    end
end
if has_sg_trip,    sg_trip = ibr_events.sg_trip; end
if has_sg_reclose, sg_on   = ibr_events.sg_on;   end
if has_load_step,        load_step        = ibr_events.load_step;        end
if has_line_trip,        line_trip        = ibr_events.line_trip;        end
if has_restore,          restore_time     = ibr_events.restore_time;     end
if has_line_fault_clear, line_fault_clear = ibr_events.line_fault_clear; end
if has_ibr_trip,         ibr_trip         = ibr_events.ibr_trip;         end
selected = [];
ref_idx = [];
n_req = [];
if strcmp(selection_request.mode,'manual_override')
    % Read the DERIVED manual tuple from the normalized selection_request,
    % NOT from raw ibr_events (which may be a 2-field legacy tuple without
    % n_gfm_required -- the normalizer derives n_gfm_required from
    % numel(selected_gfm_indices)). Reading ibr_events.n_gfm_required here
    % would throw nonExistentField on the legitimate 2-field tuple.
    mc = selection_request.manual_candidate;
    selected = mc.selected_gfm_indices;
    ref_idx = mc.reference_resource_index;
    n_req = mc.n_gfm_required;
end

% --- fault_bus -------------------------------------------------------------
if has_fault && (~isnumeric(fault_bus) || ~isscalar(fault_bus) || ~isfinite(fault_bus) || ...
        fault_bus ~= fix(fault_bus))
    error('stability:ibr_event_schedule:badFaultBus', ...
        'fault_bus must be finite integer external bus ID.');
end
if has_fault && ~any(bus_ids == fault_bus)
    error('stability:ibr_event_schedule:badFaultBus', ...
        'fault_bus %d not found in case bus list.', fault_bus);
end
fb_pos = find(bus_ids == fault_bus,1);
if isempty(fb_pos), fb_pos = NaN; end

% --- Zf --------------------------------------------------------------------
if has_fault && (~isnumeric(Zf) || ~isscalar(Zf) || ~isfinite(Zf) || abs(Zf) < eps)
    error('stability:ibr_event_schedule:badZf', ...
        'Zf must be finite non-zero complex (got %.3g%+.3gj).', real(Zf), imag(Zf));
end

% --- times -----------------------------------------------------------------
times.fields = {};
times.values = [];
if has_fault
    if has_line_fault_clear
        times.fields = [times.fields, {'fault_on'}];
        times.values = [times.values, fault_on];
    else
        times.fields = [times.fields, {'fault_on','fault_clear'}];
        times.values = [times.values, fault_on, fault_clear];
    end
end
if has_sg_trip
    times.fields = [times.fields, {'sg_trip'}];
    times.values = [times.values, sg_trip];
end
if has_sg_reclose
    times.fields = [times.fields, {'sg_on'}];
    times.values = [times.values, sg_on];
end
% Every remaining scheduled instant joins the SAME list, so the finiteness,
% nonnegativity and coincidence gates below cover all of them. Before the
% capability flags, load_step / line_trip / restore_time were validated only by
% the chronology ordering inequality and never entered the coincidence check,
% so two chronology events set to one instant passed silently.
if has_load_step
    times.fields = [times.fields, {'load_step'}];
    times.values = [times.values, load_step];
end
if has_line_trip
    times.fields = [times.fields, {'line_trip'}];
    times.values = [times.values, line_trip];
end
if has_line_fault_clear
    times.fields = [times.fields, {'line_fault_clear'}];
    times.values = [times.values, line_fault_clear];
end
if has_ibr_trip
    times.fields = [times.fields, {'ibr_trip'}];
    times.values = [times.values, ibr_trip];
end
% restore_time is deliberately EXCLUDED: the chronology contract requires
% restore_time == sg_on exactly, so including it would make the coincidence
% check reject every valid chronology. Its value is checked by that equality.
for k=1:numel(times.values)
    v = times.values(k);
    if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || ~isreal(v)
        error('stability:ibr_event_schedule:badTime', ...
            '%s must be finite real scalar (got %s).', times.fields{k}, mat2str(v));
    end
    if v < -tol
        error('stability:ibr_event_schedule:badTime', ...
            '%s must be nonnegative.', times.fields{k});
    end
end

% Ordering within each selected event family; combined additionally requires
% fault clearing no later than SG trip. A profile whose fault is cleared by
% opening the faulted line has no fault_clear instant, so the fault-family
% inequality applies to line_fault_clear instead.
if has_fault && ~has_line_fault_clear && ...
        ~(fault_on + tol < fault_clear && fault_clear <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_on < fault_clear <= t_end.');
end
if has_fault && has_line_fault_clear && ...
        ~(fault_on + tol < line_fault_clear && line_fault_clear <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_on < line_fault_clear <= t_end.');
end
if has_sg_trip && has_sg_reclose && ...
        ~(sg_trip + tol < sg_on && sg_on <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require sg_trip < sg_on <= t_end.');
end
if has_sg_trip && ~has_sg_reclose && ~(sg_trip <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require sg_trip <= t_end.');
end
if strcmp(event_profile,'combined') && ~(fault_clear <= sg_trip + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_clear <= sg_trip for the combined profile.');
end
if has_chronology && ~(sg_trip < ibr_events.load_step && ...
        ibr_events.load_step < fault_on && fault_clear < ibr_events.line_trip && ...
        ibr_events.line_trip < ibr_events.restore_time && ...
        ibr_events.restore_time == sg_on && sg_on <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        ['Chronology requires sg_trip < load_step < fault_on < fault_clear ' ...
         '< line_trip < restore_time = sg_on <= t_end.']);
end

% --- Ordering for the added profiles (one rule per profile) ----------------
% Each rule is written out in full rather than composed from the chronology
% rule, so the chronology contract above is untouched and each new profile
% states its own admissible order.
switch event_profile
case 'sg_load_cycle'
    % Island first, then the load grows on the island, then the machine is
    % offered back. The severity supervisor only runs while no SG is online
    % (ts_simulate_ibr_hybrid.m:738), so sg_trip must precede load_step for
    % the step to be answered by a converter mode decision at all.
    if ~(sg_trip + tol < load_step && load_step + tol < sg_on)
        error('stability:ibr_event_schedule:badOrdering', ...
            'sg_load_cycle requires sg_trip < load_step < sg_on <= t_end.');
    end
case 'sg_fault_cycle'
    % Island, then a bus fault ridden through on the island, then reclose.
    if ~(sg_trip + tol < fault_on && fault_clear + tol < sg_on)
        error('stability:ibr_event_schedule:badOrdering', ...
            ['sg_fault_cycle requires sg_trip < fault_on < fault_clear ' ...
             '< sg_on <= t_end.']);
    end
case 'line_fault_relay_clear'
    % Island, then a fault on the line, then the protection opens that line
    % and the fault leaves with it, then reclose onto the REDUCED network.
    % There is no restore_time in this profile by design: the faulted line
    % stays out, which is the whole question the profile asks.
    if ~(sg_trip + tol < fault_on && line_fault_clear + tol < sg_on)
        error('stability:ibr_event_schedule:badOrdering', ...
            ['line_fault_relay_clear requires sg_trip < fault_on < ' ...
             'line_fault_clear < sg_on <= t_end.']);
    end
case 'sg_trip_then_former_outage'
    % Island, then the converter that owns the island angle reference is
    % lost. No reclose is scheduled after it: the point is whether the
    % framework recovers the reference on its own.
    if ~(sg_trip + tol < ibr_trip && ibr_trip <= t_end + tol)
        error('stability:ibr_event_schedule:badOrdering', ...
            ['sg_trip_then_former_outage requires sg_trip < ibr_trip ' ...
             '<= t_end.']);
    end
end

% --- load_step_factor and branch identity, bound to their own capability ---
if has_load_step && (~isscalar(ibr_events.load_step_factor) || ...
        ~isfinite(ibr_events.load_step_factor) || ibr_events.load_step_factor<=0)
    error('stability:ibr_event_schedule:badLoadStep', ...
        'load_step_factor must be one finite positive fraction.');
end
if needs_line_stamp && (~ismember(ibr_events.line_from_bus,bus_ids) || ...
        ~ismember(ibr_events.line_to_bus,bus_ids) || ...
        ibr_events.line_from_bus==ibr_events.line_to_bus)
    error('stability:ibr_event_schedule:badLineTrip', ...
        'line_from_bus/line_to_bus must be distinct case bus IDs.');
end
if has_restore && ~(isscalar(restore_time) && isfinite(restore_time))
    error('stability:ibr_event_schedule:badRestoreTime', ...
        'restore_time must be one finite scalar.');
end

% Duplicate / coincident ambiguous (except fault_clear==sg_trip allowed)
% Check all pairs except (fault_clear, sg_trip) with distance < tol
vals = times.values;
names = times.fields;
for i=1:numel(vals)
    for j=i+1:numel(vals)
        if strcmp(names{i},'fault_clear') && strcmp(names{j},'sg_trip')
            continue;
        end
        if abs(vals(i)-vals(j)) < tol
            error('stability:ibr_event_schedule:coincidentEvents', ...
                'Duplicate/coincident events %s (%.15g) and %s (%.15g) within tol %.1e.', ...
                names{i}, vals(i), names{j}, vals(j), tol);
        end
    end
end
% Also fault_clear==sg_trip is allowed but if they are within tol but not exactly equal
% we treat as allowed equality; still ensure the difference is either <tol (equality) or clearly distinct.
% Already excluded from duplicate check, so equality passes.

% --- devices validation for index checks -----------------------------------
if isempty(devices) || ~isfield(devices,'device_id')
    error('stability:ibr_event_schedule:badDevices', ...
        'devices must be nonempty struct array with device_id.');
end
nd = numel(devices);
if nd < 2
    error('stability:ibr_event_schedule:badDevices', ...
        'Need at least SG + IBR devices.');
end

% --- selected_gfm_indices content validation (manual_override only) -----
% These content checks (finite/duplicate/range/eligibility) apply to the
% manual tuple. Guard by selection_request.mode (the normalized authority),
% NOT the legacy automatic_gfm_switching variable (removed in Step 1).
if strcmp(selection_request.mode,'manual_override')
if ~isnumeric(selected) || isempty(selected) || any(~isfinite(selected)) || ...
        any(selected ~= fix(selected))
    error('stability:ibr_event_schedule:badSelectedIndices', ...
        'selected_gfm_indices must contain finite integer indices.');
end
selected = reshape(selected,1,[]);
if numel(unique(selected)) ~= numel(selected)
    error('stability:ibr_event_schedule:duplicateSelectedIndices', ...
        'selected_gfm_indices contains duplicates.');
end
if any(selected < 1 | selected > nd)
    error('stability:ibr_event_schedule:badSelectedIndices', ...
        'selected_gfm_indices out of range [1,%d].', nd);
end
% Eligibility: selected must be dual-mode GFM-capable IBR (not SG)
for k = selected
    % Check capability if available, otherwise assume IBR by type
    if isfield(devices(k),'capabilities')
        c = devices(k).capabilities;
        if isfield(c,'resource_type') && strcmpi(char(c.resource_type),'sg')
            error('stability:ibr_event_schedule:selectedResourceIneligible', ...
                'Selected index %d is SG, must be IBR.', k);
        end
        if isfield(c,'supported_modes')
            sup = string(c.supported_modes);
            if ~any(strcmpi(sup,'gfl')) || ~any(strcmpi(sup,'gfm'))
                error('stability:ibr_event_schedule:selectedResourceIneligible', ...
                    'Selected index %d not dual-mode GFM-capable.', k);
            end
        end
    end
end
end  % close manual_override content-validation block

% n_req is derived by the normalizer (selection_request.manual_candidate.n_gfm_required)
% and read above; do NOT recompute numel(selected) here (would overwrite the
% authenticated derived value and could disagree if the normalizer applied a
% legacy mapping).

% --- reference_resource_index content validation (manual_override only) -
if strcmp(selection_request.mode,'manual_override')
if ~isnumeric(ref_idx) || ~isscalar(ref_idx) || ~isfinite(ref_idx) || ref_idx ~= fix(ref_idx)
    error('stability:ibr_event_schedule:badReferenceIndex', ...
        'reference_resource_index must be finite integer scalar.');
end
if ~ismember(ref_idx, selected)
    error('stability:ibr_event_schedule:referenceNotSelected', ...
        'reference_resource_index %d must be member of selected_gfm_indices %s.', ...
        ref_idx, mat2str(selected));
end
end

% --- ibr_trip_target (converter outage) ------------------------------------
% Two admissible forms, both resolved to a device index by the TS driver:
%   'reference_owner'  the converter that owns the island angle reference AT
%                      THE EVENT INSTANT. Resolved at run time from
%                      ec.hybrid_state.reference_owner_indices, because which
%                      converter owns the reference is a run-time outcome of
%                      the severity supervisor and is not knowable here.
%   numeric index      one explicit device index into the resource table.
% A resource ID string is deliberately NOT accepted: device identity in this
% schedule is positional everywhere else (selected_gfm_indices,
% reference_resource_index), and admitting a second identity channel here
% would create the ownership confusion the selection_request contract closed.
ibr_trip_target = [];
if has_ibr_trip
    tgt = ibr_events.ibr_trip_target;
    if ischar(tgt) || isstring(tgt)
        tgt = char(tgt);
        if ~strcmp(tgt,'reference_owner')
            error('stability:ibr_event_schedule:badIbrTripTarget', ...
                ['ibr_trip_target must be ''reference_owner'' or one device ' ...
                 'index (got "%s").'], tgt);
        end
        ibr_trip_target = 'reference_owner';
    elseif isnumeric(tgt)
        if ~isscalar(tgt) || ~isfinite(tgt) || tgt ~= fix(tgt) || ...
                tgt < 1 || tgt > nd
            error('stability:ibr_event_schedule:badIbrTripTarget', ...
                'ibr_trip_target index must be one finite integer in [1,%d].', nd);
        end
        % A non-IBR target is refused HERE rather than at run time: the
        % transaction has no transfer path for a synchronous machine, and the
        % SG breaker already has its own event.
        if isfield(devices(tgt),'capabilities') && ...
                isfield(devices(tgt).capabilities,'resource_type') && ...
                ~strcmpi(char(devices(tgt).capabilities.resource_type),'ibr')
            error('stability:ibr_event_schedule:badIbrTripTarget', ...
                ['ibr_trip_target index %d is not an IBR; use the SG breaker ' ...
                 'events for a synchronous machine.'], tgt);
        end
        ibr_trip_target = double(tgt);
    else
        error('stability:ibr_event_schedule:badIbrTripTarget', ...
            'ibr_trip_target must be char/string ''reference_owner'' or numeric.');
    end
end

% --- Optional sg_id ---------------------------------------------------------
sg_id = '';
if has_sg_cycle && isfield(ibr_events,'sg_id') && ~isempty(ibr_events.sg_id)
    if ~(ischar(ibr_events.sg_id) || isstring(ibr_events.sg_id))
        error('stability:ibr_event_schedule:badSgId', 'sg_id must be string.');
    end
    sg_id = char(ibr_events.sg_id);
    dev_ids = arrayfun(@(d) char(d.device_id), devices, 'UniformOutput', false);
    if ~any(strcmp(dev_ids, sg_id))
        error('stability:ibr_event_schedule:badSgId', 'sg_id %s not found.', sg_id);
    end
elseif has_sg_cycle
    % A unique SG capability may supply the default. Device order and a
    % familiar name are never accepted as identity fallbacks.
    sg_candidates = [];
    for k=1:nd
        if isfield(devices(k),'capabilities') && isfield(devices(k).capabilities,'resource_type')
            if strcmpi(char(devices(k).capabilities.resource_type),'sg')
                sg_candidates(end+1) = k; %#ok<AGROW>
            end
        end
    end
    if numel(sg_candidates) ~= 1
        error('stability:ibr_event_schedule:ambiguousSg', ...
            ['ibr_events.sg_id is required unless exactly one device declares ' ...
             'capabilities.resource_type="sg" (found %d).'],numel(sg_candidates));
    end
    sg_id = char(devices(sg_candidates).device_id);
end

% --- Build schedule struct -------------------------------------------------
ev = repmat(struct('type','','t',0,'index',0),0,1);
if has_fault
    ev(end+1) = struct('type','fault_on','t',fault_on,'index',numel(ev)+1); %#ok<AGROW>
    if ~has_line_fault_clear
        ev(end+1) = struct('type','fault_clear','t',fault_clear,'index',numel(ev)+1); %#ok<AGROW>
    end
end
if has_sg_trip
    ev(end+1) = struct('type','sg_trip','t',sg_trip,'index',numel(ev)+1); %#ok<AGROW>
end
if has_sg_reclose
    ev(end+1) = struct('type','sg_on','t',sg_on,'index',numel(ev)+1); %#ok<AGROW>
end
if has_load_step
    ev(end+1) = struct('type','load_step','t',load_step,'index',numel(ev)+1); %#ok<AGROW>
end
if has_line_trip
    ev(end+1) = struct('type','line_trip','t',line_trip,'index',numel(ev)+1); %#ok<AGROW>
end
if has_restore
    % Insert restoration before the same-time sg_on request.  Stable sorting
    % preserves this explicit transaction order.
    ev(end+1) = struct('type','topology_restore','t',restore_time,'index',numel(ev)+1); %#ok<AGROW>
end
if has_line_fault_clear
    ev(end+1) = struct('type','line_fault_clear','t',line_fault_clear,'index',numel(ev)+1); %#ok<AGROW>
end
if has_ibr_trip
    ev(end+1) = struct('type','ibr_trip','t',ibr_trip,'index',numel(ev)+1); %#ok<AGROW>
end
% Already ordered per validation, but sort to be safe (stable for allowed equality)
[~,order] = sortrows([[ev.t].',event_priority({ev.type}).'],[1 2]);
ev = ev(order);

sched = struct();
sched.enabled = true;
sched.event_profile = event_profile;
sched.has_fault = has_fault;
sched.has_sg_cycle = has_sg_cycle;
sched.has_chronology = has_chronology;
% Per-event capabilities. ts_simulate_ibr_hybrid reads these to decide which
% admittance stamps to build, so a profile that arms an event always gets the
% matrix that event needs instead of a silent zero.
sched.has_sg_trip = has_sg_trip;
sched.has_sg_reclose = has_sg_reclose;
sched.has_load_step = has_load_step;
sched.has_line_trip = has_line_trip;
sched.has_restore = has_restore;
sched.has_line_fault_clear = has_line_fault_clear;
sched.has_ibr_trip = has_ibr_trip;
sched.has_sync_controller = has_sync_controller;
sched.needs_line_stamp = needs_line_stamp;
sched.t_end = t_end;
sched.dt = dt;
sched.fault_bus = fault_bus;
sched.fault_bus_position = fb_pos;
sched.Zf = Zf;
sched.fault_on = fault_on;
sched.fault_clear = fault_clear;
sched.sg_trip = sg_trip;
sched.sg_on = sg_on;
sched.sg_id = sg_id;
% Event fields are published per capability, NOT under a single profile test.
% Previously every one of these lived inside `if has_chronology`, so a profile
% arming load_step or line_trip without being 'chronology' reached the kernel
% with the field absent and the corresponding admittance stamp identically
% zero -- the event then reported applied=true while changing nothing.
if has_load_step
    sched.load_step = load_step;
    sched.load_step_factor = ibr_events.load_step_factor;
end
if has_line_trip
    sched.line_trip = line_trip;
end
if has_line_fault_clear
    sched.line_fault_clear = line_fault_clear;
end
if needs_line_stamp
    sched.line_from_bus = ibr_events.line_from_bus;
    sched.line_to_bus = ibr_events.line_to_bus;
end
if has_restore
    sched.restore_time = restore_time;
end
if has_ibr_trip
    sched.ibr_trip = ibr_trip;
    sched.ibr_trip_target = ibr_trip_target;
end
if has_sg_reclose
    sched.coordinated_handback=false;
    if isfield(ibr_events,'coordinated_handback')
        sched.coordinated_handback=logical(ibr_events.coordinated_handback);
    end
end
sched.automatic_gfm_switching = norm_opt.automatic_gfm_switching;
sched.events = ev;
sched.tol = tol;
% --- selection_request (single normalization point) ---
% The schedule owns timing/routing + the canonical selection_request ONLY.
% It does NOT publish physical-selection fields at top level (closes the
% ownership-confusion defect: consumers must read the authenticated selector
% table, not sched.*). selection_request was normalized BEFORE the required-
% field check above, so automatic mode does not need a manual tuple.
sched.selection_request = selection_request;
% Audit-only legacy input (NOT a compatibility field; do not read for commit).
sched.audit = struct('legacy_selected_gfm_indices', selected, ...
    'legacy_reference_resource_index', ref_idx, ...
    'legacy_n_gfm_required', n_req);
sched.provenance = struct('source','ibr_event_schedule validation',...
    'fault','Yfault(fb,fb)+=1/Zf SOURCE_DEFINED','ordering','CASE_DEFINED',...
    'selection_mode', selection_request.mode, ...
    'profile_capabilities','PROJECT_DERIVED per-event capability row', ...
    'line_fault_model',ternary_char(has_line_fault_clear, ...
        ['close-in (zero-distance) line fault: bus shunt while on, removed ' ...
         'with the line when both breakers open; NOT a mid-line fault'], ...
        'n/a'));
end

function s=ternary_char(condition,a,b)
if condition, s=a; else, s=b; end
end

function p=event_priority(types)
% Tie-break order for events landing on the SAME instant. Only the relative
% order matters. line_fault_clear shares fault_clear's rank because it IS a
% fault clearing (it additionally removes the line). ibr_trip sits after both
% clearings and before sg_on: a converter outage must be applied to a network
% whose fault has already been removed, and a reclose request must observe the
% post-outage configuration rather than the pre-outage one.
p=zeros(1,numel(types));
for k=1:numel(types)
    switch types{k}
        case 'topology_restore', p(k)=1;
        case 'fault_clear', p(k)=2;
        case 'line_fault_clear', p(k)=2;
        case 'sg_trip', p(k)=3;
        case 'ibr_trip', p(k)=4;
        case 'sg_on', p(k)=5;
        otherwise, p(k)=2;
    end
end
end
