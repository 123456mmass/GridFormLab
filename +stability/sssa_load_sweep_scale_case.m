function [scaled_case, audit] = sssa_load_sweep_scale_case(base_case, alpha, opt)
%SSSA_LOAD_SWEEP_SCALE_CASE  Central immutable case-scaling helper.
%   [SCALED_CASE, AUDIT] = sssa_load_sweep_scale_case(BASE_CASE, ALPHA, OPT)
%   returns an isolated deep copy of BASE_CASE with only load-demand fields
%   scaled by ALPHA. The caller's struct is never mutated.
%
%   Load equation (constant power factor):
%       P_L,k(alpha) = alpha * P_L,k,base
%       Q_L,k(alpha) = alpha * Q_L,k,base
%
%   Dual load-representation audit (conditional, compare values):
%       a. If both bus_data and mpc.bus exist: audit bus IDs, signs, units,
%          nonzero-load support, and converted values (bus_data P/Q on
%          system pu base <-> mpc.bus Pd/Qd in MW/MVAr through Sbase);
%          update both consistently.
%       b. If only bus_data exists: scale it without fabricating mpc.bus.
%       c. If the runtime consumer requires mpc.bus but it is absent: fail
%          closed as unsupported.
%       d. If both exist and disagree: fail closed.
%
%   point.case_data stores the scaled snapshot BEFORE solver execution. A
%   separate working copy must be passed into PF/equilibrium/SSSA so the
%   stored snapshot is never mutated by runtime-added solved fields.

arguments
    base_case struct
    alpha (1,1) double {mustBeFinite,mustBeReal}
    opt struct = struct()
end

% --- smib_loaded_ibr/1.0 branch (single IBR to infinite bus, shunt load) ---
% Scale ONLY the shunt load fields P_load_base_pu / Q_load_base_pu. The IBR
% base references, infinite bus, line impedance, device params, and
% classification are left unchanged. No bus_data / mpc.bus representation.
if isfield(base_case,'smib_loaded_ibr') && isstruct(base_case.smib_loaded_ibr)
    [scaled_case, audit] = scale_smib_loaded(base_case, alpha);
    return;
end

if ~isfield(base_case,'bus_data') || ~ismatrix(base_case.bus_data) || ...
        size(base_case.bus_data,2) < 8
    error('sssa_load_sweep_scale_case:notNetworkCase', ...
        'base_case must contain bus_data with at least 8 columns.');
end

% --- Deep copy: struct assignment + separate numeric matrix copies -------
% MATLAB struct assignment is copy-on-write, but nested numeric matrices are
% shared until written. Force separate copies of bus_data and mpc.bus so the
% caller's struct is never mutated by index assignment below.
scaled_case = base_case;
scaled_case.bus_data = base_case.bus_data;
if isfield(scaled_case,'mpc') && isstruct(scaled_case.mpc) && ...
        isfield(scaled_case.mpc,'bus') && ismatrix(scaled_case.mpc.bus)
    scaled_case.mpc.bus = base_case.mpc.bus;
end

Sbase = 100.0;
if isfield(scaled_case,'base_values') && isfield(scaled_case.base_values,'S_base_MVA') ...
        && ~isempty(scaled_case.base_values.S_base_MVA)
    Sbase = scaled_case.base_values.S_base_MVA;
end

bus_data = scaled_case.bus_data;
bus_ids = bus_data(:,1);
Pload_pu = bus_data(:,7);
Qload_pu = bus_data(:,8);

has_mpc = isfield(scaled_case,'mpc') && isstruct(scaled_case.mpc) && ...
    isfield(scaled_case.mpc,'bus') && ismatrix(scaled_case.mpc.bus);
if has_mpc
    mpc_bus = scaled_case.mpc.bus;
    mpc_ids = mpc_bus(:,1);
    mpc_Pd_MW = mpc_bus(:,3);
    mpc_Qd_MVAr = mpc_bus(:,4);
end

% --- Dual load-representation audit (compare values) ----------------------
dual_audit = struct('both_present', has_mpc, 'consistent', true, 'disagreement', '');
if has_mpc
    % Bus-ID correspondence: every bus_data row must map to exactly one mpc row.
    [~, bd_idx, mpc_idx] = intersect(bus_ids, mpc_ids, 'stable');
    if numel(bd_idx) ~= numel(bus_ids) || numel(mpc_idx) ~= numel(mpc_ids)
        dual_audit.consistent = false;
        dual_audit.disagreement = 'bus ID sets differ between bus_data and mpc.bus';
    else
        % Compare converted values: mpc Pd_MW / Sbase should equal bus_data Pload_pu.
        P_conv = mpc_Pd_MW(mpc_idx) / Sbase;
        Q_conv = mpc_Qd_MVAr(mpc_idx) / Sbase;
        P_diff = abs(P_conv - Pload_pu(bd_idx));
        Q_diff = abs(Q_conv - Qload_pu(bd_idx));
        tol = 1e-9 * max(1, max(abs(Pload_pu(bd_idx))) + max(abs(Qload_pu(bd_idx))));
        if any(P_diff > tol) || any(Q_diff > tol)
            dual_audit.consistent = false;
            dual_audit.disagreement = sprintf( ...
                'bus_data P/Q (pu) and mpc.bus Pd/Qd (MW/MVAr via Sbase) disagree: max P diff=%.3e, max Q diff=%.3e', ...
                max(P_diff), max(Q_diff));
        end
        % Sign and nonzero-load support must match.
        Pload_mapped = Pload_pu(bd_idx);
        Qload_mapped = Qload_pu(bd_idx);
        if any(sign(P_conv) ~= sign(Pload_mapped)) || ...
                any(sign(Q_conv) ~= sign(Qload_mapped))
            dual_audit.consistent = false;
            dual_audit.disagreement = 'sign mismatch between bus_data and mpc.bus load';
        end
        if any((P_conv ~= 0) ~= (Pload_mapped ~= 0)) || ...
                any((Q_conv ~= 0) ~= (Qload_mapped ~= 0))
            dual_audit.consistent = false;
            dual_audit.disagreement = 'nonzero-load support mismatch between bus_data and mpc.bus';
        end
    end
    if ~dual_audit.consistent
        error('sssa_load_sweep:loadRepresentationMismatch', '%s', dual_audit.disagreement);
    end
end

% Whether the runtime consumer requires mpc.bus (IEEE14 IBR composite_dae).
requires_mpc = option_value_local(opt, 'requires_mpc', false);
if requires_mpc && ~has_mpc
    error('sssa_load_sweep:missingMpcLoadRepresentation', ...
        'The selected runtime consumer requires mpc.bus but it is absent; fail-closed as unsupported.');
end

% --- Scale only load-demand fields -----------------------------------------
bus_data(:,7) = alpha * Pload_pu;
bus_data(:,8) = alpha * Qload_pu;
scaled_case.bus_data = bus_data;
if has_mpc
    mpc_bus(:,3) = alpha * mpc_Pd_MW;
    mpc_bus(:,4) = alpha * mpc_Qd_MVAr;
    scaled_case.mpc.bus = mpc_bus;
end

% --- Immutability audit: every non-load field unchanged -------------------
violations = {};
if isfield(base_case,'bus_data')
    bd0 = base_case.bus_data; bd1 = scaled_case.bus_data;
    cols_nonload = setdiff(1:size(bd0,2), [7 8]);
    for k = cols_nonload
        if any(bd0(:,k) ~= bd1(:,k), 'all')
            violations{end+1} = sprintf('bus_data column %d changed', k); %#ok<AGROW>
        end
    end
end
if has_mpc
    mb0 = base_case.mpc.bus; mb1 = scaled_case.mpc.bus;
    cols_nonload_mpc = setdiff(1:size(mb0,2), [3 4]);
    for k = cols_nonload_mpc
        if any(mb0(:,k) ~= mb1(:,k), 'all')
            violations{end+1} = sprintf('mpc.bus column %d changed', k); %#ok<AGROW>
        end
    end
end
% Non-load case fields unchanged.
non_load_fields = setdiff(fieldnames(base_case), {'bus_data','mpc'});
for k = 1:numel(non_load_fields)
    f = non_load_fields{k};
    v0 = base_case.(f); v1 = scaled_case.(f);
    try
        changed = ~isequaln(v0, v1);
    catch
        changed = ~isequal(v0, v1);
    end
    if changed
        violations{end+1} = sprintf('case field %s changed', f); %#ok<AGROW>
    end
end
% mpc non-load subfields.
if has_mpc
    mpc_fields = setdiff(fieldnames(base_case.mpc), {'bus'});
    for k = 1:numel(mpc_fields)
        f = mpc_fields{k};
        try
            changed = ~isequaln(base_case.mpc.(f), scaled_case.mpc.(f));
        catch
            changed = ~isequal(base_case.mpc.(f), scaled_case.mpc.(f));
        end
        if changed
            violations{end+1} = sprintf('mpc.%s changed', f); %#ok<AGROW>
        end
    end
end
immutability = struct();
immutability.passed = isempty(violations);
immutability.violations = violations;
if ~immutability.passed
    error('sssa_load_sweep_scale_case:immutabilityViolation', ...
        'Non-load case field changed: %s', strjoin(immutability.violations, '; '));
end

% --- Audit struct ----------------------------------------------------------
audit = struct();
audit.alpha = alpha;
audit.base_fingerprint = stability.load_sweep.fingerprint(base_case);
audit.scaled_fingerprint = stability.load_sweep.fingerprint(scaled_case);
audit.changed_bus_ids = bus_ids(~(Pload_pu == 0 & Qload_pu == 0)).';
audit.before_total_Pload_pu = sum(Pload_pu);
audit.before_total_Qload_pu = sum(Qload_pu);
audit.after_total_Pload_pu = sum(bus_data(:,7));
audit.after_total_Qload_pu = sum(bus_data(:,8));
if has_mpc
    audit.before_total_Pd_MW = sum(mpc_Pd_MW);
    audit.before_total_Qd_MVAr = sum(mpc_Qd_MVAr);
    audit.after_total_Pd_MW = sum(mpc_bus(:,3));
    audit.after_total_Qd_MVAr = sum(mpc_bus(:,4));
end
audit.Sbase_MVA = Sbase;
audit.dual_representation = dual_audit;
audit.immutability = immutability;
end

function value = option_value_local(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end

% =========================================================================
function [scaled_case, audit] = scale_smib_loaded(base_case, alpha)
%SCALE_SMIB_LOADED  Scale the shunt load of a smib_loaded_ibr/1.0 case.
%   Constant-power-factor: P_load(alpha)=alpha*P_load_base, Q analogously.
%   Every non-load field is left unchanged (IBR base refs, infinite bus, Z_line,
%   device params, classification). No bus_data / mpc.bus representation.
scaled_case = base_case;
scaled_case.smib_loaded_ibr = base_case.smib_loaded_ibr;
m0 = base_case.smib_loaded_ibr;
m1 = m0;
m1.P_load_base_pu = alpha * m0.P_load_base_pu;
m1.Q_load_base_pu = alpha * m0.Q_load_base_pu;
scaled_case.smib_loaded_ibr = m1;

% Immutability audit: every non-load smib_loaded_ibr field unchanged.
violations = {};
load_fields = {'P_load_base_pu','Q_load_base_pu'};
non_load_fields = setdiff(fieldnames(m0), load_fields);
for k = 1:numel(non_load_fields)
    f = non_load_fields{k};
    v0 = m0.(f); v1 = m1.(f);
    try
        changed = ~isequaln(v0, v1);
    catch
        changed = ~isequal(v0, v1);
    end
    if changed
        violations{end+1} = sprintf('smib_loaded_ibr.%s changed', f); %#ok<AGROW>
    end
end
% Non-smib_loaded_ibr case fields unchanged.
case_nonload = setdiff(fieldnames(base_case), {'smib_loaded_ibr'});
for k = 1:numel(case_nonload)
    f = case_nonload{k};
    v0 = base_case.(f); v1 = scaled_case.(f);
    try
        changed = ~isequaln(v0, v1);
    catch
        changed = ~isequal(v0, v1);
    end
    if changed
        violations{end+1} = sprintf('case field %s changed', f); %#ok<AGROW>
    end
end
immutability = struct();
immutability.passed = isempty(violations);
immutability.violations = violations;
if ~immutability.passed
    error('sssa_load_sweep_scale_case:immutabilityViolation', ...
        'Non-load case field changed: %s', strjoin(immutability.violations, '; '));
end

audit = struct();
audit.alpha = alpha;
audit.base_fingerprint = stability.load_sweep.fingerprint(base_case);
audit.scaled_fingerprint = stability.load_sweep.fingerprint(scaled_case);
audit.changed_bus_ids = m0.load_bus_id;
audit.before_total_Pload_pu = m0.P_load_base_pu;
audit.before_total_Qload_pu = m0.Q_load_base_pu;
audit.after_total_Pload_pu = m1.P_load_base_pu;
audit.after_total_Qload_pu = m1.Q_load_base_pu;
Sbase = 100.0;
if isfield(base_case,'base_values') && isfield(base_case.base_values,'S_base_MVA')
    Sbase = base_case.base_values.S_base_MVA;
end
audit.before_total_Pd_MW = m0.P_load_base_pu * Sbase;
audit.before_total_Qd_MVAr = m0.Q_load_base_pu * Sbase;
audit.after_total_Pd_MW = m1.P_load_base_pu * Sbase;
audit.after_total_Qd_MVAr = m1.Q_load_base_pu * Sbase;
audit.Sbase_MVA = Sbase;
audit.dual_representation = struct('both_present', false, 'consistent', true, ...
    'disagreement', 'smib_loaded_ibr uses single load representation (no mpc.bus)');
audit.immutability = immutability;
end
