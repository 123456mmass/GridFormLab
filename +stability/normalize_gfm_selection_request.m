function [req, err_id, err_msg] = normalize_gfm_selection_request(opt, devices, strict)
%NORMALIZE_GFM_SELECTION_REQUEST  Resolve mode + manual fields into one canonical request.
%
%   [REQ, ERR_ID, ERR_MSG] = normalize_gfm_selection_request(OPT, DEVICES, STRICT)
%   is the SINGLE validation point for the GFM-selection schema. Schedule, the
%   selector table, and the runtime transaction all consume its output — there
%   is no duplicated per-file validation (the defect this closes).
%
%   Mode contract:
%     automatic_gfm_switching=false : no selector call, no IBR transition, the
%       only legal fields are the time/routing ones; manual selection fields
%       are ignored (caller must set them only with manual_override).
%     gfm_selection_mode='automatic' : manualCandidate MUST stay empty. Any
%       nonempty manual fields are a structured conflict (fail closed).
%     gfm_selection_mode='manual_override' : all three fields (selected,
%       n_gfm_required, reference_resource_index) must resolve atomically.
%
%   Legacy backward compatibility: a caller that supplies the three manual
%   fields WITHOUT gfm_selection_mode is mapped unambiguously to
%   manual_override with req.legacy_mapped=true (audit metadata). An ambiguous
%   mixed schema fails closed.
%
%   Devices DEVICES are needed only to validate eligibility in manual mode
%   (same rules currently in ibr_event_schedule); in automatic mode they are
%   not inspected.
%
%   STRICT (default true): when true, any conflict fails closed; the schedule
%   path always runs strict. Tests may pass strict=false to observe conflict
%   detection without an error.

arguments
    opt struct
    devices struct = struct([],[],[])
    strict logical = true
end

req = struct('mode','automatic','manual_candidate',struct(), ...
    'legacy_mapped',false,'provenance','automatic');
err_id = '';
err_msg = '';

% --- firmware enable ---
fw = true;
if isfield(opt,'automatic_gfm_switching') && ~isempty(opt.automatic_gfm_switching)
    fw = logical(opt.automatic_gfm_switching);
end
if ~fw
    req.mode = 'off';
    req.provenance = 'firmware_off';
    return;
end

% --- read raw fields ---
has_mode = isfield(opt,'gfm_selection_mode') && ~isempty(opt.gfm_selection_mode);
mode = '';
if has_mode
    mode = lower(char(opt.gfm_selection_mode));
end

manual_fields = {'selected_gfm_indices','n_gfm_required','reference_resource_index'};
has_manual = false(1,3);
vals = cell(1,3);
for i=1:3
    if isfield(opt,manual_fields{i}) && ~isempty(opt.(manual_fields{i}))
        has_manual(i) = true;
        vals{i} = opt.(manual_fields{i});
    end
end
any_manual = any(has_manual);
all_manual = all(has_manual);

% --- resolve mode ---
if has_mode
    if ~any(strcmp(mode,{'automatic','manual_override'}))
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:gfmSelectionModeInvalid', ...
            sprintf('gfm_selection_mode must be ''automatic'' or ''manual_override'' (got ''%s'').', mode));
        return;
    end
    req.mode = mode;
    req.provenance = mode;
    if strcmp(mode,'automatic') && any_manual
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:gfmSelectionModeConflict', ...
            'automatic mode must not supply selected_gfm_indices/n_gfm_required/reference_resource_index.');
        return;
    end
else
    % No explicit mode: legacy mapping.
    if any_manual
        % Legacy two-field form (selected_gfm_indices + reference_resource_index,
        % WITHOUT n_gfm_required) is the canonical legacy caller shape (e.g.
        % ibr_event_schedule / event_spec in tests). Derive n_gfm_required =
        % numel(selected) HERE — in the single normalization point — so the
        % schema conversion is visible and identical regardless of caller.
        % Any OTHER partial combination (e.g. selected without ref, or
        % n_gfm_required without selected) remains ambiguous and fails closed.
        two_field_legacy = has_manual(1) && has_manual(3) && ~has_manual(2);
        if two_field_legacy
            vals{2} = numel(vals{1});   % derive count from the selected set
            has_manual(2) = true;
            all_manual = true;
            req.mode = 'manual_override';
            req.legacy_mapped = true;
            req.provenance = 'legacy_mapped_two_field';
        elseif ~all_manual
            [req, err_id, err_msg] = conflict(req, ...
                'ibr_event_schedule:gfmSelectionAmbiguousLegacy', ...
                'Legacy selection fields supplied partially without gfm_selection_mode — ambiguous.');
            return;
        else
            req.mode = 'manual_override';
            req.legacy_mapped = true;
            req.provenance = 'legacy_mapped';
        end
    else
        req.mode = 'automatic';
        req.provenance = 'automatic_default';
    end
end

% --- manual_override validation (atomic three-field + eligibility) ---
if strcmp(req.mode,'manual_override')
    sel = vals{1}; nreq = vals{2}; ref = vals{3};
    nd = numel(devices);
    if ~isnumeric(sel) || any(~isfinite(sel)) || any(sel ~= fix(sel))
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:badSelectedIndices', ...
            'selected_gfm_indices must contain finite integer indices.');
        return;
    end
    sel = reshape(sel,1,[]);
    if numel(unique(sel)) ~= numel(sel)
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:duplicateSelectedIndices', ...
            'selected_gfm_indices contains duplicates.');
        return;
    end
    if any(sel < 1 | sel > nd)
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:badSelectedIndices', ...
            'selected_gfm_indices out of range [1,%d].', nd);
        return;
    end
    % Eligibility (mirrors ibr_event_schedule:208-225)
    for k = sel
        if isfield(devices(k),'capabilities')
            c = devices(k).capabilities;
            if isfield(c,'resource_type') && strcmpi(char(c.resource_type),'sg')
                [req, err_id, err_msg] = conflict(req, ...
                    'ibr_event_schedule:selectedResourceIneligible', ...
                    'Selected index %d is SG, must be IBR.', k);
                return;
            end
            if isfield(c,'supported_modes')
                sup = string(c.supported_modes);
                if ~any(strcmpi(sup,'gfl')) || ~any(strcmpi(sup,'gfm'))
                    [req, err_id, err_msg] = conflict(req, ...
                        'ibr_event_schedule:selectedResourceIneligible', ...
                        'Selected index %d not dual-mode GFM-capable.', k);
                    return;
                end
            end
        end
    end
    if ~isequal(nreq, numel(sel))
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:badNRequired', ...
            'n_gfm_required must equal numel(selected_gfm_indices).');
        return;
    end
    if ~isnumeric(ref) || ~isscalar(ref) || ~isfinite(ref) || ref ~= fix(ref) || ~ismember(ref, sel)
        [req, err_id, err_msg] = conflict(req, ...
            'ibr_event_schedule:referenceNotSelected', ...
            'reference_resource_index must be a finite integer scalar member of selected_gfm_indices.');
        return;
    end
    req.manual_candidate = struct('selected_gfm_indices',sel, ...
        'n_gfm_required',nreq,'reference_resource_index',ref);
end

    % nested helper keeps the return shape uniform
    function [r, eid, ems] = conflict(r, eid, ems, varargin)
        if ~isempty(ems) && nargin>3
            ems = sprintf(ems, varargin{:});
        end
        if strict
            error(eid, '%s', ems);
        end
        err_id = eid;
        err_msg = ems;
    end
end
