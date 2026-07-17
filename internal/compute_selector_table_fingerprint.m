function [fp, input_fp, evidence_fp] = compute_selector_table_fingerprint(inputs, evidence)
%COMPUTE_SELECTOR_TABLE_FINGERPRINT  Canonical fingerprint for the authenticated selector table.
%
%   FP = compute_selector_table_fingerprint(INPUTS, EVIDENCE) computes the
%   deterministic, canonical AGGREGATE fingerprint (backward-compatible:
%   one-output callers are unchanged).
%
%   [FP, INPUT_FP, EVIDENCE_FP] = compute_selector_table_fingerprint( ... )
%   additionally returns the two component layer hashes for 3-layer
%   authentication. The validator recomputes all three from runtime inputs
%   + live Y and compares each against the stored values. The aggregate
%   FP remains the AUTHORITATIVE digest; the component hashes are
%   diagnostic (advisor Q1, Revision 4).
%
%   This is the single fingerprint source of truth -- builder and validator
%   MUST call this same function.
%
%   Architecture (3-layer, see plan):
%     selector_input_fingerprint      = hash(immutable inputs + context topology)
%     candidate_evidence_fingerprint  = hash(canonical full candidate evidence)
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
%   EVIDENCE struct (REVISION 4): the evidence struct may carry either
%   PRE-SERIALIZED universe strings (sg_off_universe / sg_on_universe) OR
%   RAW candidate struct arrays (sg_off_configurations / sg_on_configurations).
%   Raw arrays are canonicalized through THIS shared serializer so builder
%   and validator use ONE serialization path (advisor: no duplicated
%   serializer that collapses cell/struct to '?'). This closes the lossy
%   '?' path in the prior local struct_to_str.
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

input_fp = hash_string(strjoin(parts, '|'));

% Evidence fingerprint. Accept either pre-serialized universe strings
% (legacy callers) or raw candidate struct arrays (Revision 4: builder +
% validator pass raw arrays through this ONE shared serializer).
evidence_parts = {};
if isfield(evidence,'sg_off_universe') && ~isempty(evidence.sg_off_universe)
    ev_off = evidence.sg_off_universe;
    if ischar(ev_off) || isstring(ev_off)
        off_str = char(ev_off);
    else
        off_str = config_array_to_str(ev_off);
    end
    evidence_parts{end+1} = sprintf('sg_off=%s', off_str); %#ok<AGROW>
elseif isfield(evidence,'sg_off_configurations')
    evidence_parts{end+1} = sprintf('sg_off=%s', ...
        config_array_to_str(evidence.sg_off_configurations)); %#ok<AGROW>
end
if isfield(evidence,'sg_on_universe') && ~isempty(evidence.sg_on_universe)
    ev_on = evidence.sg_on_universe;
    if ischar(ev_on) || isstring(ev_on)
        on_str = char(ev_on);
    else
        on_str = config_array_to_str(ev_on);
    end
    evidence_parts{end+1} = sprintf('sg_on=%s', on_str); %#ok<AGROW>
elseif isfield(evidence,'sg_on_configurations')
    evidence_parts{end+1} = sprintf('sg_on=%s', ...
        config_array_to_str(evidence.sg_on_configurations)); %#ok<AGROW>
end
evidence_fp = hash_string(strjoin(evidence_parts, '|'));

% Combined table fingerprint (aggregate, AUTHORITATIVE).
fp = hash_string(sprintf('version=selector_table_v2|input=%s|evidence=%s', ...
    input_fp, evidence_fp));
end

% ---------------------------------------------------------------------
function s = config_array_to_str(cfgs)
% Deterministic serialization of the full candidate universe (struct array).
% Element order IS the enumeration order (already deterministic), so no
% re-sort is needed. The fingerprint authenticates this whole array, not
% only the single selected result. Shared by builder + validator.
if isempty(cfgs)
    s = 'none';
    return;
end
parts = cell(1, numel(cfgs));
for i = 1:numel(cfgs)
    parts{i} = struct_to_str(cfgs(i));
end
s = strjoin(parts, ';');
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
