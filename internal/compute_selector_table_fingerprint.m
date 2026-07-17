function fp = compute_selector_table_fingerprint(inputs, evidence)
%COMPUTE_SELECTOR_TABLE_FINGERPRINT  Canonical fingerprint for the authenticated selector table.
%
%   FP = compute_selector_table_fingerprint(INPUTS, EVIDENCE) computes a
%   deterministic, canonical fingerprint that BOTH the table builder
%   (ibr_selector_table.m) and the runtime validator
%   (validate_runtime_candidate_compatibility.m) call. This is the single
%   fingerprint source of truth -- builder and validator MUST agree.
%
%   Architecture (3-layer, see plan):
%     selector_input_fingerprint      = hash(immutable inputs + context topology)
%     candidate_evidence_fingerprint  = hash(canonical candidate evidence)
%     selector_table_fingerprint      = hash(schema_version + input_fp + evidence_fp)
%
%   INPUTS struct:
%     .bus              bus matrix (full, not just rcond)
%     .branch           branch matrix
%     .baseMVA          scalar
%     .resource_ids     cell of char
%     .model_ids        cell of char
%     .capabilities     cell of canonical capability strings
%     .dispatch         dispatch struct (or [])
%     .gamma_req        scalar
%     .selector         selector policy struct (or [])
%     .base_values      struct (or [])
%     .topology_payload canonical complex Ybus + bus ordering (actual Y at event)
%
%   EVIDENCE struct:
%     .sg_off_universe  serialized candidate array for SG_OFF context
%     .sg_on_universe   serialized candidate array for SG_ON context
%
%   Classification: canonical serialization NUMERICAL_METHOD. No external solver.

% Canonical serialization of all immutable inputs that authenticate the evidence.
parts = {};
if isfield(inputs,'bus') && ~isempty(inputs.bus)
    parts{end+1} = ['bus=', mat2str(inputs.bus(:)')]; %#ok<AGROW>
end
if isfield(inputs,'branch') && ~isempty(inputs.branch)
    parts{end+1} = ['branch=', mat2str(inputs.branch(:)')]; %#ok<AGROW>
end
if isfield(inputs,'baseMVA') && ~isempty(inputs.baseMVA)
    parts{end+1} = sprintf('baseMVA=%g', inputs.baseMVA); %#ok<AGROW>
end
if isfield(inputs,'resource_ids') && ~isempty(inputs.resource_ids)
    parts{end+1} = sprintf('resource_ids=%s', strjoin(cellfun(@char, inputs.resource_ids, 'UniformOutput', false), ',')); %#ok<AGROW>
end
if isfield(inputs,'model_ids') && ~isempty(inputs.model_ids)
    parts{end+1} = sprintf('model_ids=%s', strjoin(cellfun(@char, inputs.model_ids, 'UniformOutput', false), ',')); %#ok<AGROW>
end
if isfield(inputs,'capabilities') && ~isempty(inputs.capabilities)
    parts{end+1} = sprintf('capabilities=%s', strjoin(inputs.capabilities, ';')); %#ok<AGROW>
end
if isfield(inputs,'dispatch') && ~isempty(inputs.dispatch)
    parts{end+1} = sprintf('dispatch=%s', struct_to_str(inputs.dispatch)); %#ok<AGROW>
end
if isfield(inputs,'gamma_req') && ~isempty(inputs.gamma_req)
    parts{end+1} = sprintf('gamma_req=%.12g', inputs.gamma_req); %#ok<AGROW>
end
if isfield(inputs,'selector') && ~isempty(inputs.selector)
    parts{end+1} = sprintf('selector=%s', struct_to_str(inputs.selector)); %#ok<AGROW>
end
if isfield(inputs,'base_values') && ~isempty(inputs.base_values)
    parts{end+1} = sprintf('base_values=%s', struct_to_str(inputs.base_values)); %#ok<AGROW>
end
% Context topology from ACTUAL Y at event (not immutable case_data alone).
if isfield(inputs,'topology_payload') && ~isempty(inputs.topology_payload)
    parts{end+1} = sprintf('topology=%s', topology_to_str(inputs.topology_payload)); %#ok<AGROW>
end

selector_input_fingerprint = hash_string(strjoin(parts, '|'));

% Evidence fingerprint from serialized candidate universes.
evidence_parts = {};
if isfield(evidence,'sg_off_universe')
    evidence_parts{end+1} = sprintf('sg_off=%s', evidence.sg_off_universe); %#ok<AGROW>
end
if isfield(evidence,'sg_on_universe')
    evidence_parts{end+1} = sprintf('sg_on=%s', evidence.sg_on_universe); %#ok<AGROW>
end
candidate_evidence_fingerprint = hash_string(strjoin(evidence_parts, '|'));

% Combined table fingerprint.
fp = hash_string(sprintf('version=selector_table_v2|input=%s|evidence=%s', ...
    selector_input_fingerprint, candidate_evidence_fingerprint));
end

% ---------------------------------------------------------------------
function h = hash_string(s)
% Deterministic in-house hash (FNV-1a 32-bit variant with uint64 intermediate).
h = uint32(2166136261);
mask32 = uint64(4294967295);
for k = 1:numel(s)
    h = bitxor(h, uint32(double(s(k))));
    product = uint64(h) * uint64(16777619);
    h = uint32(bitand(product, mask32));
end
h = sprintf('%08x', h);
end

% ---------------------------------------------------------------------
function s = struct_to_str(st)
% Deterministic canonical serialization of a scalar struct (recursive).
% Handles: numeric, char, string, logical, cell, struct (scalar + array), complex.
if ~isstruct(st) || isempty(st)
    s = '';
    return;
end
fns = sort(fieldnames(st));
parts = {};
for k = 1:numel(fns)
    v = st.(fns{k});
    if isnumeric(v)
        if ~isreal(v)
            parts{end+1} = sprintf('%s=(re=%s,im=%s)', fns{k}, mat2str(real(v(:)')), mat2str(imag(v(:)'))); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%s=%s', fns{k}, mat2str(v(:)')); %#ok<AGROW>
        end
    elseif ischar(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, v); %#ok<AGROW>
    elseif isstring(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, char(v)); %#ok<AGROW>
    elseif islogical(v)
        parts{end+1} = sprintf('%s=%d', fns{k}, v); %#ok<AGROW>
    elseif iscell(v)
        parts{end+1} = sprintf('%s=[%s]', fns{k}, cell_to_str(v)); %#ok<AGROW>
    elseif isstruct(v) && isscalar(v)
        parts{end+1} = sprintf('%s={%s}', fns{k}, struct_to_str(v)); %#ok<AGROW>
    elseif isstruct(v) && ~isscalar(v)
        elems = cell(1, numel(v));
        for i = 1:numel(v)
            elems{i} = struct_to_str(v(i));
        end
        parts{end+1} = sprintf('%s=[%s]', fns{k}, strjoin(elems, ';')); %#ok<AGROW>
    else
        parts{end+1} = sprintf('%s=?', fns{k}); %#ok<AGROW>
    end
end
s = strjoin(parts, ',');
end

function s = cell_to_str(c)
% Deterministic serialization of a cell array (ordered).
if isempty(c)
    s = '';
    return;
end
elems = cell(1, numel(c));
for i = 1:numel(c)
    v = c{i};
    if isnumeric(v)
        elems{i} = mat2str(v(:)');
    elseif ischar(v)
        elems{i} = v;
    elseif isstring(v)
        elems{i} = char(v);
    elseif islogical(v)
        elems{i} = sprintf('%d', v);
    else
        elems{i} = '?';
    end
end
s = strjoin(elems, '/');
end

function s = topology_to_str(Y)
% Canonical serialization of complex Ybus with bus ordering.
% NaN/Inf replaced with canonical tokens for stability.
if isempty(Y)
    s = '';
    return;
end
nr = numel(Y(:));
re = real(Y(:)');
im = imag(Y(:)');
% Replace NaN/Inf with canonical tokens. Use logical masks on BOTH sides so
% empty masks (no NaN/Inf present) are a safe no-op assignment rather than a
% double-indexed subscript that triggers badsubscript on degenerate inputs.
re_nan = isnan(re); re_inf = isinf(re);
re(re_nan) = -99999; re(re_inf) = 99999 .* sign(re(re_inf));
im_nan = isnan(im); im_inf = isinf(im);
im(im_nan) = -99999; im(im_inf) = 99999 .* sign(im(im_inf));
s = sprintf('n=%d|re=%s|im=%s', nr, mat2str(re), mat2str(im));
end
