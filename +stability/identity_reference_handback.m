function [state_out, audit] = identity_reference_handback(state_in, owner_index, physical_before, physical_after, opt)
%IDENTITY_REFERENCE_HANDBACK  Metadata-only reference-owner transaction.
%   [STATE_OUT,AUDIT] = stability.identity_reference_handback(STATE_IN,OWNER,
%   BEFORE,AFTER,OPT) changes only the canonical reference-owner metadata.
%   BEFORE/AFTER are a struct of physical observables (for example x, y, u,
%   V, I, P and Q); they must remain equal within a tolerance derived from
%   machine precision and supplied signal scale.  No angle rotation, state
%   reset, current injection, or KCL row is introduced.
%
%   This is the identity transaction used when an online SG becomes the
%   supervisory reference while the physical network is already unchanged.
%   A breaker close or a mode transfer is not an identity transaction and
%   must use its own right-limit/transfer gate.

arguments
    state_in struct
    owner_index (1,1) double
    physical_before struct
    physical_after struct
    opt struct = struct()
end

if ~isfinite(owner_index) || owner_index < 1 || owner_index ~= fix(owner_index)
    error('stability:identity_reference_handback:badOwner', ...
        'owner_index must be one finite positive integer.');
end
scale = option_value(opt,'signal_scale',1);
if ~isfinite(scale) || scale <= 0 || ~isscalar(scale)
    error('stability:identity_reference_handback:badScale', ...
        'signal_scale must be one finite positive scalar.');
end
rtol = max(100*eps, option_value(opt,'relative_tolerance',0));
atol = max(100*eps*scale, option_value(opt,'absolute_tolerance',0));
names = union(fieldnames(physical_before),fieldnames(physical_after));
max_abs = 0;
for k = 1:numel(names)
    name = names{k};
    if ~isfield(physical_before,name) || ~isfield(physical_after,name)
        error('stability:identity_reference_handback:missingObservable', ...
            'Observable %s must be present on both sides.',name);
    end
    a = physical_before.(name); b = physical_after.(name);
    if ~isnumeric(a) || ~isnumeric(b) || ~isequal(size(a),size(b)) || ...
            any(~isfinite(a(:))) || any(~isfinite(b(:)))
        error('stability:identity_reference_handback:badObservable', ...
            'Observable %s must be finite numeric arrays of equal size.',name);
    end
    d = max(abs(a(:)-b(:)));
    scale_local = max([1;abs(a(:));abs(b(:))]);
    limit = atol + rtol*scale*scale_local;
    if d > limit
        error('stability:identity_reference_handback:physicalChange', ...
            'Observable %s changed by %.3e above %.3e.',name,d,limit);
    end
    max_abs = max(max_abs,d);
end

state_out = state_in;
state_out.reference_owner_indices = owner_index;
state_out.reference_island_ids = option_value(opt,'reference_island_id',1);
state_out.gfm_reference_resource_indices = NaN;
% The legacy alias is deliberately not pointed at the SG. It remains an
% SG_OFF/GFM-only compatibility field and is cleared during SG_ON handback.
state_out.reference_resource_index = [];
if isfield(state_in,'selected_gfm_indices')
    state_out.selected_gfm_indices = state_in.selected_gfm_indices;
end
audit = struct('identity_only',true,'physical_unchanged',true, ...
    'max_absolute_difference',max_abs,'absolute_tolerance',atol, ...
    'relative_tolerance',rtol,'owner_index',owner_index, ...
    'reference_island_id',state_out.reference_island_ids, ...
    'state_reset',false,'angle_rotation',false,'kcl_mutation',false);
end

function v = option_value(s,name,default)
v = default;
if isfield(s,name) && ~isempty(s.(name)), v = s.(name); end
end
