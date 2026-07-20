function point = route_smib_ibr(scaled_case, scenario, opt)
%ROUTE_SMIB_IBR  SMIB loaded-IBR route adapter for the load sweep.
%   POINT = stability.load_sweep.route_smib_ibr(SCALED_CASE, SCENARIO, OPT)
%   evaluates ONE load-sweep point for a single GFL/GFM converter connected
%   to an ideal infinite bus through Z_line, with a shunt load at the IBR
%   terminal bus. Delegates to ibr.smib_loaded_equilibrium +
%   ibr.smib_loaded_sssa_oracle (dedicated, self-contained — does NOT call
%   composite_dae / composite_sssa_model / mixed_equilibrium_solve /
%   powerflow_newton_raphson).
%
%   Stages (each fail-closed with a typed failure_stage + failure_id):
%     INPUT_VALIDATION -> DEVICE_BUILD -> EQUILIBRIUM -> SSSA_LINEARIZATION
%     -> MODAL_REPORTING
%
%   Dispatch policy (ASSUMED_DIAGNOSTIC): the IBR receives the incremental
%   load. Its P/Q references track the swept load level; the infinite bus
%   absorbs the change in line flow. Tm/Efd are not applicable (IBR).

point = struct();
point.route = 'smib_ibr';
point.failure_stage = '';
point.failure_id = '';
point.failure_reason = '';

% --- INPUT_VALIDATION -----------------------------------------------------
if ~isfield(scaled_case,'smib_loaded_ibr') || ~isstruct(scaled_case.smib_loaded_ibr)
    point.failure_stage = 'INPUT_VALIDATION';
    point.failure_id = 'route_smib_ibr:missingSchema';
    point.failure_reason = 'scaled_case must contain smib_loaded_ibr metadata.';
    return;
end
m = scaled_case.smib_loaded_ibr;
required_fields = {'kind','device_type','device_id','V_infinite_pu', ...
    'Z_line_pu','P_load_base_pu','Q_load_base_pu','P_ibr_base_pu','Q_ibr_base_pu'};
for k = 1:numel(required_fields)
    if ~isfield(m,required_fields{k})
        point.failure_stage = 'INPUT_VALIDATION';
        point.failure_id = 'route_smib_ibr:missingField';
        point.failure_reason = sprintf('smib_loaded_ibr missing field %s.', ...
            required_fields{k});
        return;
    end
end

V_inf = m.V_infinite_pu;
Z_line = m.Z_line_pu;
P_load = m.P_load_base_pu;     % SCALED by scale_case (alpha * base)
Q_load = m.Q_load_base_pu;     % SCALED by scale_case (alpha * base)
P_ibr_ref = m.P_ibr_base_pu;   % FIXED at base (IBR setpoint, NOT load-tracked)
Q_ibr_ref = m.Q_ibr_base_pu;   % FIXED at base (IBR setpoint, NOT load-tracked)
kind = lower(char(m.kind));

% Dispatch policy (ASSUMED_DIAGNOSTIC): IBR references held FIXED at base
% values. The infinite bus is the slack that absorbs the incremental load
% through Z_line. When load increases, the terminal voltage V moves, the
% line current changes, and the IBR responds through its own dynamics (PLL /
% current loop for GFL, VSG swing for GFM) — this is the physically
% meaningful SMIB. (Setting IBR reference = load would make line flow = 0
% always and degenerate to an isolated IBR+load, NOT a SMIB.)

% --- DEVICE_BUILD ---------------------------------------------------------
dev_opt = struct();
Sbase = 100.0;
if isfield(scaled_case,'base_values') && isfield(scaled_case.base_values,'S_base_MVA')
    Sbase = scaled_case.base_values.S_base_MVA;
end
try
    bus_id = 1.0; bus_position = 1.0; bus_ids = 1.0;
    V0 = abs(V_inf);
    switch kind
        case 'gfl_rms10'
            dev = ibr.gfl_rms10_model(char(m.device_id), bus_id, bus_position, ...
                bus_ids, V0, dev_opt, P_ibr_ref, Q_ibr_ref);
        case 'gfm_no_pll'
            dev = ibr.gfm_vsg_no_pll_model(char(m.device_id), bus_id, ...
                bus_position, bus_ids, V0, dev_opt, P_ibr_ref, abs(V_inf));
        otherwise
            error('route_smib_ibr:unknownKind', ...
                'Unknown smib_loaded_ibr kind %s.', kind);
    end
catch err
    point.failure_stage = 'DEVICE_BUILD';
    point.failure_id = 'sssa_load_sweep:deviceBuild';
    point.failure_reason = err.message;
    point.devices = [];
    point.dev_meta = struct();
    return;
end
point.devices = dev;
point.dev_meta = struct('kind',kind,'device_type',char(m.device_type));

% --- EQUILIBRIUM ----------------------------------------------------------
eq_opt = struct('verbose', logical(option_value(opt,'verbose',false)), ...
    'tolerance', 1e-10, 'max_iter', 100, 'fd_eps', 1e-6);
try
    eq = ibr.smib_loaded_equilibrium(dev, V_inf, Z_line, P_load, Q_load, ...
        P_ibr_ref, Q_ibr_ref, eq_opt);
catch err
    point.failure_stage = 'EQUILIBRIUM';
    point.failure_id = 'sssa_load_sweep:equilibrium';
    point.failure_reason = err.message;
    point.equilibrium = struct('converged',false,'failure_reason',err.message);
    return;
end
point.equilibrium = eq;
if ~eq.converged
    point.failure_stage = 'EQUILIBRIUM';
    point.failure_id = 'sssa_load_sweep:equilibriumNoConverge';
    point.failure_reason = eq.failure_reason;
    return;
end

% PF diagnostics from the equilibrium (SMIB PF = source-frozen identity, not
% multi-bus Newton). The infinite bus is fixed; the terminal voltage is solved.
pf_diag = struct();
pf_diag.converged = eq.converged;
pf_diag.iterations = eq.iterations;
pf_diag.max_mismatch = eq.residual_norm;
pf_diag.voltage_min_pu = abs(eq.V_terminal);
pf_diag.voltage_max_pu = abs(eq.V_terminal);
pf_diag.V_terminal = eq.V_terminal;
pf_diag.V_infinite_bus = V_inf;
pf_diag.Z_line = Z_line;
pf_diag.classification = 'ASSUMED_DIAGNOSTIC_SMIB_LOADED_PF_EQUILIBRIUM';
point.pf = pf_diag;

% --- EQUILIBRIUM DEVICE DIAGNOSTICS --------------------------------------
% Publish only quantities reconstructed by the accepted device closure.  GFL
% exposes native current states i_d/i_q.  The no-PLL GFM has no current state,
% so its dq current is a labelled diagnostic frame transform of I_inv using
% the virtual-rotor angle; it is not fed back into any equation or gate.
try
    rec = dev.reconstruct(0,eq.x0,eq.y0,eq.u_eq,struct());
    op = equilibrium_operating_point(rec,dev,Sbase,eq.V_terminal);
    point.operating_point = op;
catch err
    point.failure_stage = 'EQUILIBRIUM_RECONSTRUCTION';
    point.failure_id = 'sssa_load_sweep:equilibriumReconstruction';
    point.failure_reason = err.message;
    return;
end

% --- SSSA_LINEARIZATION ---------------------------------------------------
try
    sssa = ibr.smib_loaded_sssa_oracle(dev, eq.x0, eq.V_terminal, eq.u_eq, ...
        V_inf, Z_line, P_load, Q_load);
catch err
    point.failure_stage = 'SSSA_LINEARIZATION';
    point.failure_id = 'sssa_load_sweep:sssa';
    point.failure_reason = err.message;
    point.sssa = [];
    return;
end
point.sssa = sssa;

% --- MODAL_REPORTING ------------------------------------------------------
% SMIB route: synthesize active_state_indices on sssa.A so the load-sweep mode
% matcher (which expects sssa.A, sssa.eigenvalues, sssa.active_state_indices)
% can run. Raw eigenvalue order is preserved.
if ~isfield(sssa,'A') || isempty(sssa.A)
    point.sssa.A = sssa.A_full;
    point.sssa.active_state_indices = (1:size(sssa.A_full,1)).';
else
    point.sssa.active_state_indices = sssa.active_state_indices;
end

try
    modal = stability.modal_analysis(sssa);
    point.modal = modal;
catch err
    point.failure_stage = 'MODAL_REPORTING';
    point.failure_id = 'sssa_load_sweep:modal';
    point.failure_reason = err.message;
    point.modal = [];
end
end

function op = equilibrium_operating_point(rec,dev,Sbase,V_terminal)
if isfield(rec,'i_d') && isfield(rec,'i_q')
    i_d = rec.i_d;
    i_q = rec.i_q;
    current_source = 'NATIVE_GFL_CURRENT_STATES';
elseif isfield(rec,'I_inv') && isfield(rec,'delta_vsm')
    I_dq_inv = rec.I_inv*exp(-1i*rec.delta_vsm);
    i_d = real(I_dq_inv);
    i_q = imag(I_dq_inv);
    current_source = 'PROJECT_DERIVED_DIAGNOSTIC_VSM_FRAME_TRANSFORM';
else
    error('route_smib_ibr:missingDqCurrent', ...
        'Device reconstruction does not expose native or reconstructable dq current.');
end
if ~isfield(rec,'Pe') || ~isfield(rec,'Qe')
    error('route_smib_ibr:missingPower', ...
        'Device reconstruction must expose Pe and Qe on system base.');
end
P_pu = rec.Pe;
Q_pu = rec.Qe;
if isfield(rec,'I_sys')
    I_sys = rec.I_sys;
elseif isfield(rec,'I_gfl')
    I_sys = rec.I_gfl;
else
    error('route_smib_ibr:missingSystemCurrent', ...
        'Device reconstruction must expose system-base network current.');
end
identity_error = abs(complex(P_pu,Q_pu)-V_terminal*conj(I_sys));
vals = [i_d i_q P_pu Q_pu];
if any(~isfinite(vals)) || ~isreal(vals) || ~isfinite(identity_error)
    error('route_smib_ibr:nonfiniteOperatingPoint', ...
        'Reconstructed dq current and P/Q must be finite real scalars.');
end
identity_tolerance = 1e-10; % NUMERICAL_METHOD reporting consistency gate
if identity_error > identity_tolerance
    error('route_smib_ibr:powerIdentityMismatch', ...
        'Reconstructed S and V*conj(I) differ by %.3e pu (tol %.3e).', ...
        identity_error,identity_tolerance);
end
op = struct('device_id',char(dev.device_id), ...
    'device_type',char(dev.device_type), ...
    'i_d_pu_inverter',i_d,'i_q_pu_inverter',i_q, ...
    'P_pu_system',P_pu,'Q_pu_system',Q_pu, ...
    'P_MW',P_pu*Sbase,'Q_MVAr',Q_pu*Sbase, ...
    'current_frame','DEVICE_SYNCHRONOUS_DQ', ...
    'current_source',current_source, ...
    'power_convention','GENERATOR_INJECTION_S_EQUALS_V_CONJ_I', ...
    'power_identity_error',identity_error, ...
    'power_identity_tolerance',identity_tolerance, ...
    'classification','EQUILIBRIUM_RECONSTRUCTION_DIAGNOSTIC');
end

function value = option_value(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = fallback;
end
end
