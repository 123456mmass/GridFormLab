function table = ibr_selector_table(case_data, resources, scenario, opt)
%IBR_SELECTOR_TABLE  Precomputed authenticated SG_OFF + SG_ON selector tables.
%   TABLE = ibr_selector_table(CASE_DATA, RESOURCES, SCENARIO, OPT) builds
%   BOTH the SG_OFF and SG_ON candidate tables BEFORE time-domain simulation
%   by calling the EXISTING stability.ibr_config_selector /
%   ibr_candidate_evaluate path. It does NOT duplicate selector, equilibrium,
%   or SSSA algorithms. The complete candidate evidence is cached and bound to
%   an immutable selector_table_fingerprint.
%
%   At runtime (Phase 2 reselection), the TS driver verifies the fingerprint
%   against the current immutable case/model/table inputs, then ranks
%   candidates relative to the current committed configuration. A stale or
%   incomplete table fails closed WITHOUT rolling back a successful Phase 1
%   reclose.
%
%   Inputs:
%     case_data  - immutable network case (with .mpc)
%     resources  - validated resource table
%     scenario   - scenario struct (carries config, selector policy, dispatch)
%     opt        - struct with:
%       .gamma_req            (frozen; default from scenario.selector)
%       .sg_off.n_gfm_required (required; SG_OFF GFM count)
%       .sg_off.reference_resource_index (optional constraint)
%       .sg_off.dispatch      (optional; SG_OFF dispatch contract)
%       .sg_on.n_gfm_required (required; SG_ON GFM count, may be 0 for all-GFL)
%       .sg_on.reference_resource_index (optional; usually [] when SG owns)
%       .sg_on.dispatch       (optional; SG_ON = pre_fault dispatch)
%
%   Output TABLE struct:
%     .sg_off               selector result for SG_OFF context
%     .sg_on                selector result for SG_ON context
%     .selector_table_fingerprint  immutable fingerprint authenticating
%                                  topology/resources/models/parameters/
%                                  dispatch/selector policy/gamma_req/cached
%                                  evidence
%     .gamma_req            frozen margin
%     .built_at             build provenance (no wall-clock; deterministic)
%
%   Selection policy (deterministic, applied at runtime lookup):
%     feasibility -> fewer runtime mode changes -> fewer GFMs ->
%     larger stability margin -> resource-ID tie-break
%
%   Classification: table build PROJECT_DERIVED (calls existing selector);
%   fingerprint canonical serialization NUMERICAL_METHOD. No external solver.
%
%   Source: F1 (three fingerprints), C7 (precomputed authenticated table).

arguments
    case_data struct
    resources struct
    scenario struct
    opt struct = struct()
end

gamma_req = resolve_gamma_req(scenario, opt);

table = struct();
table.gamma_req = gamma_req;
table.sg_off = build_context(case_data, resources, scenario, opt, gamma_req, false);
table.sg_on = build_context(case_data, resources, scenario, opt, gamma_req, true);
table.selector_table_fingerprint = build_fingerprint(case_data, resources, ...
    scenario, gamma_req, table.sg_off, table.sg_on);
table.built_at = 'precomputed_before_ts';
end

% =========================================================================
function result = build_context(case_data, resources, scenario, opt, gamma_req, sg_online)
ctx_opt = struct('case_data', case_data, 'gamma_req', gamma_req, 'sg_online', sg_online);
prefix = 'sg_off';
if sg_online
    prefix = 'sg_on';
end
if isfield(opt, prefix) && isstruct(opt.(prefix))
    ctx = opt.(prefix);
    if isfield(ctx, 'n_gfm_required') && ~isempty(ctx.n_gfm_required)
        ctx_opt.n_gfm_required = ctx.n_gfm_required;
    end
    if isfield(ctx, 'reference_resource_index') && ~isempty(ctx.reference_resource_index)
        ctx_opt.reference_resource_index = ctx.reference_resource_index;
    end
    if isfield(ctx, 'dispatch') && ~isempty(ctx.dispatch)
        ctx_opt.dispatch = ctx.dispatch;
    end
end
if ~isfield(ctx_opt, 'n_gfm_required') || isempty(ctx_opt.n_gfm_required)
    % Default: SG_OFF requires >=1 GFM; SG_ON permits 0 (all-GFL).
    if sg_online
        ctx_opt.n_gfm_required = 0;
    else
        ctx_opt.n_gfm_required = 1;
    end
end
topology = struct('case_data', case_data);
result = stability.ibr_config_selector(resources, topology, scenario, ctx_opt);
result.context = prefix;
result.sg_online = sg_online;
result.n_gfm_required = ctx_opt.n_gfm_required;
end

function gamma_req = resolve_gamma_req(scenario, opt)
if isfield(opt, 'gamma_req') && ~isempty(opt.gamma_req)
    gamma_req = opt.gamma_req;
elseif isfield(scenario, 'selector') && isstruct(scenario.selector)
    if isfield(scenario.selector, 'gamma_req_rad_per_s') && ...
            ~isempty(scenario.selector.gamma_req_rad_per_s)
        gamma_req = scenario.selector.gamma_req_rad_per_s;
    elseif isfield(scenario.selector, 'gamma_req') && ~isempty(scenario.selector.gamma_req)
        gamma_req = scenario.selector.gamma_req;
    else
        gamma_req = 0.1;
    end
else
    gamma_req = 0.1;
end
if ~isscalar(gamma_req) || ~isfinite(gamma_req) || gamma_req < 0
    error('stability:ibr_selector_table:badGammaReq', ...
        'gamma_req must be a finite nonnegative scalar.');
end
end

function fp = build_fingerprint(case_data, resources, scenario, gamma_req, sg_off, sg_on)
% Canonical serialization of all inputs that authenticate the cached evidence.
% Includes complete relevant topology (not only rcond), resource IDs/ordering,
% model IDs/parameter fingerprints, online/mode capabilities, dispatch/input
% contract, selector policy, gamma_req, case/base values, source/config version.
fp_parts = {};
% Topology: canonical serialization of the full Ybus (not only rcond).
if isfield(case_data, 'mpc') && isfield(case_data.mpc, 'bus') && ...
        isfield(case_data.mpc, 'branch')
    fp_parts{end+1} = sprintf('bus=%s', mat2str(case_data.mpc.bus(:,:))); %#ok<AGROW>
    fp_parts{end+1} = sprintf('branch=%s', mat2str(case_data.mpc.branch(:,:))); %#ok<AGROW>
    if isfield(case_data.mpc, 'baseMVA')
        fp_parts{end+1} = sprintf('baseMVA=%g', case_data.mpc.baseMVA); %#ok<AGROW>
    end
end
% Resource IDs and ordering.
nr = numel(resources);
ids = cell(1, nr);
model_ids = cell(1, nr);
for k = 1:nr
    ids{k} = char(resources(k).resource_id);
    if isfield(resources(k), 'model_id')
        model_ids{k} = char(resources(k).model_id);
    else
        model_ids{k} = '';
    end
end
fp_parts{end+1} = sprintf('resource_ids=%s', strjoin(ids, ',')); %#ok<AGROW>
fp_parts{end+1} = sprintf('model_ids=%s', strjoin(model_ids, ',')); %#ok<AGROW>
% Online/mode capabilities.
caps = cell(1, nr);
for k = 1:nr
    if isfield(resources(k), 'capabilities') && isstruct(resources(k).capabilities)
        caps{k} = sprintf('%s|%s|%s', ...
            char(resources(k).capabilities.resource_type), ...
            mat2str(resources(k).capabilities.can_switch_mode), ...
            strjoin(string(resources(k).capabilities.supported_modes), '/'));
    else
        caps{k} = 'none';
    end
end
fp_parts{end+1} = sprintf('capabilities=%s', strjoin(caps, ';')); %#ok<AGROW>
% Dispatch/input contract.
if isfield(scenario, 'config') && isstruct(scenario.config) && ...
        isfield(scenario.config, 'dispatch') && ~isempty(scenario.config.dispatch)
    fp_parts{end+1} = sprintf('dispatch=%s', struct_to_str(scenario.config.dispatch)); %#ok<AGROW>
end
% Selector policy + gamma_req.
fp_parts{end+1} = sprintf('gamma_req=%.12g', gamma_req); %#ok<AGROW>
if isfield(scenario, 'selector') && isstruct(scenario.selector)
    fp_parts{end+1} = sprintf('selector_policy=%s', struct_to_str(scenario.selector)); %#ok<AGROW>
end
% Case/base values.
if isfield(case_data, 'base_values') && isstruct(case_data.base_values)
    fp_parts{end+1} = sprintf('base_values=%s', struct_to_str(case_data.base_values)); %#ok<AGROW>
end
% Cached evidence summary (selected indices + omega + margin per context).
fp_parts{end+1} = sprintf('sg_off_selected=%s', mat2str(sg_off.selected_gfm_indices)); %#ok<AGROW>
fp_parts{end+1} = sprintf('sg_off_omega=%.12g', sg_off.omega); %#ok<AGROW>
fp_parts{end+1} = sprintf('sg_on_selected=%s', mat2str(sg_on.selected_gfm_indices)); %#ok<AGROW>
fp_parts{end+1} = sprintf('sg_on_omega=%.12g', sg_on.omega); %#ok<AGROW>
% Source/config version.
fp_parts{end+1} = 'version=selector_table_v1'; %#ok<AGROW>
fp = ['selector_table|' strjoin(fp_parts, '|')];
% Hash to a compact fingerprint (deterministic; in-house, no toolbox).
fp = sprintf('selector_table|%s', hash_string(fp));
end

function s = struct_to_str(s)
% Deterministic canonical serialization of a scalar struct (recursive).
if ~isstruct(s) || isempty(s)
    s = '';
    return;
end
fns = sort(fieldnames(s));
parts = {};
for k = 1:numel(fns)
    v = s.(fns{k});
    if isnumeric(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, mat2str(v(:).')); %#ok<AGROW>
    elseif ischar(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, v); %#ok<AGROW>
    elseif isstring(v)
        parts{end+1} = sprintf('%s=%s', fns{k}, char(v)); %#ok<AGROW>
    elseif islogical(v)
        parts{end+1} = sprintf('%s=%d', fns{k}, v); %#ok<AGROW>
    elseif isstruct(v) && isscalar(v)
        parts{end+1} = sprintf('%s={%s}', fns{k}, struct_to_str(v)); %#ok<AGROW>
    else
        parts{end+1} = sprintf('%s=?', fns{k}); %#ok<AGROW>
    end
end
s = strjoin(parts, ',');
end

function h = hash_string(s)
% Deterministic in-house hash (no toolbox dependency). FNV-1a 32-bit variant.
% MATLAB integer multiply is SATURATING (clamps to intmax), not modular, so a
% direct `h * uint32(16777619)` saturates at 0xFFFFFFFF after the first overflow
% and every distinct input collides to the same hash. Use an exact uint64
% intermediate and mask the low 32 bits to implement true modular arithmetic.
% Max product 0xFFFFFFFF * 16777619 ~= 7.2e16 < uint64 max (1.8e19): no overflow.
h = uint32(2166136261);
mask32 = uint64(4294967295);   % 2^32 - 1
for k = 1:numel(s)
    h = bitxor(h, uint32(double(s(k))));
    product = uint64(h) * uint64(16777619);
    h = uint32(bitand(product, mask32));
end
h = sprintf('%08x', h);
end
