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
%   Validation (fail-closed, no silent fallback):
%     - times finite, nonnegative, ordered: fault_on < fault_clear <= sg_trip < sg_on <= t_end
%     - duplicate/coincident ambiguous events fail closed (tol 1e-12), except
%       fault_clear == sg_trip is explicitly allowed by the ordering contract.
%     - fault_bus valid external bus ID present in case_data.mpc.bus
%     - Zf valid finite non-zero complex
%     - selected_gfm_indices exact, unique, in-range, reference in selected
%     - devices must be indexed struct array with device_id
%
%   Classification:
%     topology Yfault = Ypre; Yfault(fb,fb)+=1/Zf  SOURCE_DEFINED
%     ordering/duplication gates CASE_DEFINED / NUMERICAL_METHOD (tol)
%     index validation PROJECT_DERIVED
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

event_profile = 'combined';
if isfield(ibr_events,'event_profile') && ~isempty(ibr_events.event_profile)
    if ~(ischar(ibr_events.event_profile) || isstring(ibr_events.event_profile))
        error('stability:ibr_event_schedule:badEventProfile', ...
            'event_profile must be combined, fault_only, or sg_cycle.');
    end
    event_profile = validatestring(char(ibr_events.event_profile), ...
        {'combined','fault_only','sg_cycle'});
end
has_fault = any(strcmp(event_profile,{'combined','fault_only'}));
has_sg_cycle = any(strcmp(event_profile,{'combined','sg_cycle'}));

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
    required = [required, {'fault_bus','Zf','fault_on','fault_clear'}];
end
if has_sg_cycle
    required = [required, {'sg_trip','sg_on'}];
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
if has_fault
    fault_bus = ibr_events.fault_bus; Zf = ibr_events.Zf;
    fault_on = ibr_events.fault_on; fault_clear = ibr_events.fault_clear;
end
if has_sg_cycle
    sg_trip = ibr_events.sg_trip; sg_on = ibr_events.sg_on;
end
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
    times.fields = [times.fields, {'fault_on','fault_clear'}];
    times.values = [times.values, fault_on, fault_clear];
end
if has_sg_cycle
    times.fields = [times.fields, {'sg_trip','sg_on'}];
    times.values = [times.values, sg_trip, sg_on];
end
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
% fault clearing no later than SG trip.
if has_fault && ~(fault_on + tol < fault_clear && fault_clear <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_on < fault_clear <= t_end.');
end
if has_sg_cycle && ~(sg_trip + tol < sg_on && sg_on <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require sg_trip < sg_on <= t_end.');
end
if strcmp(event_profile,'combined') && ~(fault_clear <= sg_trip + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_clear <= sg_trip for the combined profile.');
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
    ev(end+1) = struct('type','fault_clear','t',fault_clear,'index',numel(ev)+1); %#ok<AGROW>
end
if has_sg_cycle
    ev(end+1) = struct('type','sg_trip','t',sg_trip,'index',numel(ev)+1); %#ok<AGROW>
    ev(end+1) = struct('type','sg_on','t',sg_on,'index',numel(ev)+1); %#ok<AGROW>
end
% Already ordered per validation, but sort to be safe (stable for allowed equality)
[~,order] = sort([ev.t]);
% Preserve logical order for allowed equality: fault_clear before sg_trip when equal
% (stable sort already)
ev = ev(order);

sched = struct();
sched.enabled = true;
sched.event_profile = event_profile;
sched.has_fault = has_fault;
sched.has_sg_cycle = has_sg_cycle;
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
    'selection_mode', selection_request.mode);
end
