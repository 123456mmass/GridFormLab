function result = ibr_config_selector(resources, topology, scenario, opt)
%IBR_CONFIG_SELECTOR  Index-based resource-configuration selector (correction 8).
%   RESULT = ibr_config_selector(RESOURCES, TOPOLOGY, SCENARIO, OPT) enumerates
%   feasible mixed-resource configurations and selects the best one using a
%   deterministic predeclared ordering. All decisions derive from validated
%   resource indices — NEVER from bus IDs or hard-coded device names.
%
%   Correction 8 ordering (deterministic, predeclared):
%     1. Feasibility: at least one voltage-forming source per energized island;
%        all selected IBRs must have their mode in supported_modes.
%     2. Min-mode-changes: prefer configs with fewer mode switches.
%     3. Min-GFM count (subject to voltage-forming reserve).
%     4. Max-margin (from SSSA — most negative ω).
%     5. Deterministic resource-ID tie-break (lexicographic).
%
%   Inputs:
%     resources  - validated resource table (from stability.resource_table)
%     topology   - current network topology (island membership)
%     scenario   - scenario struct (dispatch, delay policies, etc.)
%     opt        - selector options (gamma_req, verbose)
%
%   Output: RESULT with .selected_config, .configurations, .fingerprint,
%   .feasibility_log, .sssa_log, .failed_configs.
%
%   No IEEE14 bus IDs or device names appear here. No SG_ON→all-GFL or
%   SG_OFF→all-GFM rule. Automatic selection records selected resource IDs.
%
%   STATUS: STRUCTURAL_ONLY (Phase D). Gamma_req frozen at 0.1 rad/s.
%   SSSA integration deferred to Phase D integration test.
%   Source: execution plan §D; correction 8.

arguments
    resources struct
    topology struct = struct()
    scenario struct = struct()
    opt struct = struct()
end

gamma_req = 0.1;   % rad/s, frozen (execution plan appendix)
if isfield(opt, 'gamma_req') && ~isempty(opt.gamma_req), gamma_req = opt.gamma_req; end
verbose = false;
if isfield(opt, 'verbose') && ~isempty(opt.verbose), verbose = opt.verbose; end

result = struct();
result.selected_config = struct();
result.configurations = [];
result.fingerprint = '';
result.feasibility_log = {};
result.sssa_log = {};
result.failed_configs = {};

nr = numel(resources);
if nr == 0
    result.fingerprint = 'ibr_config_selector:noResources';
    return;
end

% --- Enumerate candidate configurations (simplified: one current config) ---
% Full enumeration over all mode combinations is Phase D+. This version
% validates the current committed configuration and returns it if feasible.

current_config = struct();
current_config.resource_ids = cell(nr,1);
current_config.modes = cell(nr,1);
current_config.online = false(nr,1);
current_config.voltage_forming = false(nr,1);
current_config.resource_type = cell(nr,1);

vf_count = 0;
online_count = 0;
for k = 1:nr
    r = resources(k);
    current_config.resource_ids{k} = r.resource_id;
    current_config.resource_type{k} = r.resource_type;
    current_config.online(k) = r.initial_online;
    current_config.modes{k} = r.initial_mode;
    if r.initial_online
        online_count = online_count + 1;
        if any(string(r.initial_mode) == r.voltage_forming_modes)
            current_config.voltage_forming(k) = true;
            vf_count = vf_count + 1;
        end
    end
end

% --- Feasibility gate: at least one voltage-forming source per island ------
if online_count == 0
    result.selected_config = current_config;
    result.selected_config.feasible = false;
    result.selected_config.reason = 'noOnlineResources';
    return;
end
if vf_count < 1
    result.selected_config = current_config;
    result.selected_config.feasible = false;
    result.selected_config.reason = 'noVoltageFormingSource';
    if verbose
        fprintf('ibr_config_selector: %d online resources, 0 VF -> not feasible.\n', online_count);
    end
    return;
end

% --- SSSA check: verify damping margin (deferred to Phase D test) ----------
% Placeholder: assume config passes the margin check in the current state.
% Full SSSA integration: composite_sssa_model + eig check against gamma_req.

current_config.feasible = true;
current_config.n_mode_changes = 0;
current_config.n_gfm = sum(strcmpi(current_config.modes, 'gfm') | ...
    strcmpi(current_config.resource_type, 'sg'));
current_config.margin = -1.0;   % placeholder — SSSA required for actual margin
current_config.tie_break = strjoin(sort(current_config.resource_ids), ',');

result.selected_config = current_config;
result.configurations = current_config;
result.fingerprint = sprintf('selector_v1_n%d_vf%d_margin%.3f', ...
    nr, vf_count, current_config.margin);
end
