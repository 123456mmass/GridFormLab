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

% automatic_gfm_switching (C3/F2): when false, the SG breaker trip still
% occurs but no GFM is committed and IBR modes remain unchanged. In that
% mode selected_gfm_indices/reference_resource_index are not required.
automatic_gfm_switching = true;
if isfield(ibr_events,'automatic_gfm_switching') && ...
        ~isempty(ibr_events.automatic_gfm_switching)
    automatic_gfm_switching = logical(ibr_events.automatic_gfm_switching);
end
if automatic_gfm_switching
    required = {'fault_bus','Zf','fault_on','fault_clear','sg_trip','sg_on',...
        'selected_gfm_indices','reference_resource_index'};
else
    required = {'fault_bus','Zf','fault_on','fault_clear','sg_trip','sg_on'};
end
for k=1:numel(required)
    if ~isfield(ibr_events,required{k}) || isempty(ibr_events.(required{k}))
        error('stability:ibr_event_schedule:missingField', ...
            'ibr_events.%s missing (required when enabled).', required{k});
    end
end

fault_bus = ibr_events.fault_bus;
Zf = ibr_events.Zf;
fault_on = ibr_events.fault_on;
fault_clear = ibr_events.fault_clear;
sg_trip = ibr_events.sg_trip;
sg_on = ibr_events.sg_on;
selected = [];
ref_idx = [];
if automatic_gfm_switching
    selected = ibr_events.selected_gfm_indices;
    ref_idx = ibr_events.reference_resource_index;
end

% --- fault_bus -------------------------------------------------------------
if ~isnumeric(fault_bus) || ~isscalar(fault_bus) || ~isfinite(fault_bus) || ...
        fault_bus ~= fix(fault_bus)
    error('stability:ibr_event_schedule:badFaultBus', ...
        'fault_bus must be finite integer external bus ID.');
end
if ~any(bus_ids == fault_bus)
    error('stability:ibr_event_schedule:badFaultBus', ...
        'fault_bus %d not found in case bus list.', fault_bus);
end
fb_pos = find(bus_ids == fault_bus,1);

% --- Zf --------------------------------------------------------------------
if ~isnumeric(Zf) || ~isscalar(Zf) || ~isfinite(Zf) || abs(Zf) < eps
    error('stability:ibr_event_schedule:badZf', ...
        'Zf must be finite non-zero complex (got %.3g%+.3gj).', real(Zf), imag(Zf));
end

% --- times -----------------------------------------------------------------
times.fields = {'fault_on','fault_clear','sg_trip','sg_on'};
times.values = [fault_on, fault_clear, sg_trip, sg_on];
for k=1:4
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

% Ordering: fault_on < fault_clear <= sg_trip < sg_on <= t_end
if ~(fault_on + tol < fault_clear)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_on < fault_clear (%.15g < %.15g).', fault_on, fault_clear);
end
if ~(fault_clear <= sg_trip + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require fault_clear <= sg_trip (%.15g <= %.15g).', fault_clear, sg_trip);
end
if ~(sg_trip + tol < sg_on)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require sg_trip < sg_on (%.15g < %.15g).', sg_trip, sg_on);
end
if ~(sg_on <= t_end + tol)
    error('stability:ibr_event_schedule:badOrdering', ...
        'Require sg_on <= t_end (%.15g <= %.15g).', sg_on, t_end);
end

% Duplicate / coincident ambiguous (except fault_clear==sg_trip allowed)
% Check all pairs except (fault_clear, sg_trip) with distance < tol
vals = [fault_on, fault_clear, sg_trip, sg_on];
names = {'fault_on','fault_clear','sg_trip','sg_on'};
for i=1:4
    for j=i+1:4
        if i==2 && j==3  % allowed equality fault_clear==sg_trip
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

% --- selected_gfm_indices (required only when automatic_gfm_switching) -----
if automatic_gfm_switching
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
end  % close automatic_gfm_switching validation block

n_req = numel(selected);

% --- reference_resource_index (required only when automatic_gfm_switching) -
if automatic_gfm_switching
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
if isfield(ibr_events,'sg_id') && ~isempty(ibr_events.sg_id)
    if ~(ischar(ibr_events.sg_id) || isstring(ibr_events.sg_id))
        error('stability:ibr_event_schedule:badSgId', 'sg_id must be string.');
    end
    sg_id = char(ibr_events.sg_id);
    dev_ids = arrayfun(@(d) char(d.device_id), devices, 'UniformOutput', false);
    if ~any(strcmp(dev_ids, sg_id))
        error('stability:ibr_event_schedule:badSgId', 'sg_id %s not found.', sg_id);
    end
else
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
ev(4) = struct('type','','t',0,'index',0);
ev(1) = struct('type','fault_on','t',fault_on,'index',1);
ev(2) = struct('type','fault_clear','t',fault_clear,'index',2);
ev(3) = struct('type','sg_trip','t',sg_trip,'index',3);
ev(4) = struct('type','sg_on','t',sg_on,'index',4);
% Already ordered per validation, but sort to be safe (stable for allowed equality)
[~,order] = sort([ev.t]);
% Preserve logical order for allowed equality: fault_clear before sg_trip when equal
% (stable sort already)
ev = ev(order);

sched = struct();
sched.enabled = true;
sched.t_end = t_end;
sched.dt = dt;
sched.fault_bus = fault_bus;
sched.fault_bus_position = fb_pos;
sched.Zf = Zf;
sched.fault_on = fault_on;
sched.fault_clear = fault_clear;
sched.sg_trip = sg_trip;
sched.sg_on = sg_on;
sched.selected_gfm_indices = selected;
sched.reference_resource_index = ref_idx;
sched.n_gfm_required = n_req;
sched.sg_id = sg_id;
sched.automatic_gfm_switching = automatic_gfm_switching;
sched.events = ev;
sched.tol = tol;
sched.provenance = struct('source','ibr_event_schedule validation','fault','Yfault(fb,fb)+=1/Zf SOURCE_DEFINED','ordering','CASE_DEFINED');
end
