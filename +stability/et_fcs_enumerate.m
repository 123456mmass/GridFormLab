function candidates = et_fcs_enumerate(snapshot)
%ET_FCS_ENUMERATE  Canonical finite GFL/GFM mode and reference-owner universe.
%   For one energized island, an online reference-capable SG remains owner and
%   all 2^N eligible-IBR mode vectors are enumerated. If no SG can own the
%   island, all nonempty GFM subsets are enumerated once per eligible GFM owner.
%   No physical feasibility claim is made here.
%
%   Classification: finite action-set construction PROJECT_DERIVED; canonical
%   binary/owner ordering NUMERICAL_METHOD.

arguments
    snapshot struct
end
if ~isfield(snapshot, 'schema') || ~strcmp(snapshot.schema, 'et_fcs_snapshot/1.0')
    error('stability:et_fcs_enumerate:badSnapshot', ...
        'Input must be produced by stability.et_fcs_snapshot.');
end

eligible = find(snapshot.eligible_mask);
if numel(eligible) > 4
    error('stability:et_fcs_enumerate:excessiveUniverse', ...
        'The validated exhaustive ET-FCSPS universe is limited to four eligible IBRs.');
end
if any(~strcmp(snapshot.resource_types(eligible), 'ibr'))
    error('stability:et_fcs_enumerate:eligibleNotIbr', ...
        'Every eligible switching resource must have resource_type="ibr".');
end

island_id = snapshot.energized_island_ids(1);
sg_owner = find(snapshot.device_online & snapshot.reference_capable & ...
    strcmp(snapshot.resource_types, 'sg') & snapshot.resource_island_ids == island_id);
if numel(sg_owner) > 1
    current = intersect(sg_owner, snapshot.reference_owner_indices, 'stable');
    if isscalar(current)
        sg_owner = current;
    else
        error('stability:et_fcs_enumerate:ambiguousSgOwner', ...
            'Multiple online SG owners exist without one authenticated current owner.');
    end
end

template = struct('candidate_id','','ordinal',0,'modes',{{}}, ...
    'selected_gfm_indices',[],'owner_index',[],'owner_resource_id','', ...
    'n_gfm',0,'n_switch',0,'structural_pass',true,'structural_reason','', ...
    'snapshot_fingerprint',snapshot.fingerprint);
candidates = repmat(template, 0, 1);
n = numel(eligible);
for mask = 0:(2^n - 1)
    bits = bitget(mask, 1:n);
    selected = eligible(logical(bits));
    modes = snapshot.device_modes;
    for j = 1:n
        if bits(j)
            modes{eligible(j)} = 'gfm';
        else
            modes{eligible(j)} = 'gfl';
        end
    end
    if ~isempty(sg_owner)
        owners = sg_owner;
    else
        owners = selected(snapshot.reference_capable(selected) & ...
            snapshot.device_online(selected) & ...
            snapshot.resource_island_ids(selected) == island_id);
    end
    for oi = 1:numel(owners)
        owner = owners(oi);
        c = template;
        c.ordinal = numel(candidates) + 1;
        c.modes = modes;
        c.selected_gfm_indices = selected;
        c.owner_index = owner;
        c.owner_resource_id = snapshot.resource_ids{owner};
        c.n_gfm = numel(selected);
        c.n_switch = count_switches(snapshot.device_modes, modes, eligible);
        bit_text = sprintf('%d', bits);
        c.candidate_id = sprintf('m%s|owner=%s', bit_text, c.owner_resource_id);
        candidates(end+1,1) = c; %#ok<AGROW>
    end
end

if isempty(candidates)
    error('stability:et_fcs_enumerate:noReferenceCandidate', ...
        'No mode-owner pair can provide a reference for the energized island.');
end
end

function n = count_switches(current, target, eligible)
n = 0;
for k = eligible
    n = n + ~strcmpi(current{k}, target{k});
end
end
