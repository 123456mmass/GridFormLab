function dev = dual_mode_ibr_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, Q_ref_pu, V_ref_pu, mode)
%DUAL_MODE_IBR_MODEL  Fixed-layout dual-mode GFL/GFM/tripped IBR device.
%
%   dev = dual_mode_ibr_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF_PU, Q_REF_PU, V_REF_PU, MODE) returns a device struct
%   conforming to the stability.composite_dae ABI (R3 Revision 2) with a
%   CONSTANT state dimension (20) across modes 'gfl' | 'GFM' | 'tripped'.
%
%   The superset layout reuses the standalone +ibr/gfl_model and
%   +ibr/regfm_b1_vsg_model as the SINGLE SOURCE OF TRUTH for the
%   equations: the constructor builds internal gfl_dev and gfm_dev structs and
%   the closures map the superset state into each standalone device's state
%   slice, then dispatch to the standalone closures. No equations are
%   duplicated or rewritten.
%
%   Superset state (20): GFM REGFM_B1 G2 states 1:13 followed by WECC
%   REGC_A/REEC_A GFL states 14:20.  No state is shared: the source WECC
%   current-source model aligns to terminal voltage algebraically and has no
%   PLL coordinate to merge with REGFM_B1.
%
%   Inputs (nu=3, fixed): u = [P_ref; Q_ref; V_ref] (pu, system base).
%     gfl mode uses [P_ref; Q_ref]; GFM mode uses [P_ref; V_ref]; tripped uses none.
%   Optional exact initializer (same signature on every participating device):
%     x_eq = equilibrium_initialize(V_bus, P_terminal_pu, ...
%                                  Q_terminal_pu, event_context)
%   It resolves the active runtime mode from event_context.hybrid_state by
%   device_id, maps the standalone branch equilibrium into this 20-state
%   superset, and leaves inactive unique states at their warm-start anchor.
%   Optional runtime partition resolver:
%     idx = active_state_indices_for_context(event_context)
%   returns the device-owned active state set for the same resolved mode. This
%   prevents equilibrium consumers from hard-coding the 20-state layout.
%
%   Mode dispatch:
%     'gfl'     -> active = GFL branch (7); GFM branch frozen.
%                  current_injection routes to WECC REGC_A/REEC_A.
%     'GFM'     -> active = REGFM_B1 G2 branch (13); GFL branch frozen.
%                  current_injection routes to gfm_dev (Eq.13 voltage-behind-impedance).
%     'tripped' -> all frozen; current_injection = 0.
%   Inactive branches are held (dx=0), per the frozen inactive_state_rule
%   (PROJECT_DERIVED: continuity + algebraic-residual minimization).
%
%   Transfer initialization is physical (terminal V/P/Q), not a copy of
%   source-incompatible coordinates. Runtime transfer-map integration is a
%   separate production gate.
%
%   STATUS: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES.
%
%   Source: docs/project/IEEE14_IBR_FROZEN_CONTRACT.md (inactive_state_rule);
%           docs/project/plans/IEEE14_1SG_4IBR_AUTO_VSG_SWITCHING_PLAN.md.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params struct
    P_ref_pu (1,1) double
    Q_ref_pu (1,1) double
    V_ref_pu (1,1) double
    mode (1,1) string {mustBeMember(mode, ["gfl","GFM","tripped"])}
end

% --- Validate V0 (finite, nonzero) -----------------------------------------
if ~isfinite(V0) || abs(V0) <= 0
    error('ibr:dual_mode_ibr_model:badV0', ...
        'V0 must be finite with |V0|>0 (got %.6g); PF warm-start required.', V0);
end
% --- Validate refs ---------------------------------------------------------
if ~isfinite(P_ref_pu) || ~isfinite(Q_ref_pu) || ~isfinite(V_ref_pu)
    error('ibr:dual_mode_ibr_model:badRef', ...
        'P_ref/Q_ref/V_ref must be finite.');
end

% --- Build internal standalone devices (single source of truth) -------------
% GFL device: u=[P_ref;Q_ref]. GFM device: u=[P_ref;V_ref].
% Construction-time GFL family selection (params.gfl_family): 'wecc_regca_reeca'
% (default, 7-state) or 'rms10' (10-state). The output device_type encodes the
% family so the metadata registry can dispatch exactly (no variable nx under
% one device_type).
gfl_family = 'wecc_regca_reeca';
if isfield(params,'gfl_family') && ~isempty(params.gfl_family)
    gfl_family = char(params.gfl_family);
end
switch lower(strtrim(gfl_family))
case 'wecc_regca_reeca'
    % Forward params (minus gfl_family) so the WECC default sees its overrides.
    gfl_params = rmfield_if(params, 'gfl_family');
    gfl_dev = ibr.gfl_model(device_id, bus_id, bus_position, bus_ids, V0, ...
        gfl_params, P_ref_pu, Q_ref_pu);
    device_type_tag = 'ibr_dual_mode';
    contract_nx = 20;
case 'rms10'
    gfl_params = params;
    gfl_params.gfl_family = 'rms10';
    gfl_dev = ibr.gfl_model(device_id, bus_id, bus_position, bus_ids, V0, ...
        gfl_params, P_ref_pu, Q_ref_pu);
    device_type_tag = 'ibr_dual_mode_rms10';
    contract_nx = 23;
otherwise
    error('ibr:dual_mode_ibr_model:unknownFamily', ...
        'Unknown GFL family "%s" for dual-mode device. Supported: wecc_regca_reeca (default), rms10.', gfl_family);
end
gfm_dev = ibr.regfm_b1_vsg_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, V_ref_pu);

% --- Superset state layout: separate source-model branches ----------------
% WECC REGC_A/REEC_A is voltage-angle aligned algebraically and has no PLL
% state.  REGFM_B1 owns its PLL and relative inertial angle.  The two state
% vectors are therefore concatenated without artificial shared coordinates.
% GFL-RMS10 owns its own SRF-PLL; still concatenated without shared coordinates.
state_names = [strcat('gfm_',gfm_dev.state_names), ...
               strcat('gfl_',gfl_dev.state_names)];
nx = gfm_dev.nx+gfl_dev.nx;
nu = 3;
if nx ~= contract_nx
    error('ibr:dual_mode_ibr_model:layoutMismatch', ...
        'Dual-mode layout nx=%d does not match the %s contract nx=%d.', ...
        nx, device_type_tag, contract_nx);
end

x0 = [gfm_dev.x0(:);gfl_dev.x0(:)];

u0 = [P_ref_pu; Q_ref_pu; V_ref_pu];

% --- State-slice maps ------------------------------------------------------
gfm_idx = 1:gfm_dev.nx;
gfl_idx = gfm_dev.nx+(1:gfl_dev.nx);

bp = bus_position;

% --- Differential RHS: dispatch by mode; inactive branches are exact holds --
%   Inactive unique states have dx=0 exactly (PROJECT_DERIVED). The explicit
%   active-state partition removes their rows/columns from equilibrium, SSSA,
%   and TS Newton systems, so no artificial decay pole is needed.
f = @(t, x_dev, y, u_dev, event_context) dual_f( ...
    x_dev, y, u_dev, event_context, device_id, true, mode, gfl_dev, gfm_dev, ...
    gfl_idx, gfm_idx, nx, u0);

% --- current_injection: dispatch by mode -----------------------------------
%   Tolerates u_dev=[] (diagnostic calls from mixed_equilibrium_solve.check_limits
%   use u_dev=[] at the equilibrium where u=u0). Falls back to u0 when empty.
current_injection = @(t, x_dev, y, u_dev, event_context) dual_current( ...
    x_dev, y, u_dev, event_context, device_id, true, mode, gfl_dev, gfm_dev, ...
    gfl_idx, gfm_idx, u0);

% --- electrical_power: dispatch by mode -----------------------------------
electrical_power = @(t, x_dev, y, u_dev, event_context) dual_pe( ...
    x_dev, y, u_dev, event_context, device_id, true, mode, gfl_dev, gfm_dev, ...
    gfl_idx, gfm_idx, u0);

% --- reconstruct -----------------------------------------------------------
reconstruct = @(t, x_dev, y, u_dev, event_context) dual_reconstruct( ...
    x_dev, y, u_dev, event_context, device_id, true, mode, gfl_dev, gfm_dev, ...
    gfl_idx, gfm_idx, bp, u0);

% --- Optional exact active-branch equilibrium initializer ------------------
equilibrium_initialize = @(V_bus, P_terminal_pu, Q_terminal_pu, event_context) ...
    dual_equilibrium_initialize(V_bus, P_terminal_pu, Q_terminal_pu, ...
        event_context, device_id, true, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, x0);
active_state_indices_for_context = @(event_context) ...
    dual_active_state_indices(event_context, device_id, true, mode, gfl_idx, gfm_idx);
equilibrium_constraint_specs = @(x_dev,y,u_dev,event_context) ...
    dual_equilibrium_constraint_specs(x_dev,y,u_dev,event_context,device_id, ...
        true,mode,gfm_dev,gfm_idx,u0);
% --- Physical GFL<->GFM transfer callback (device-owned, generic) -----------
%   x_right = mode_transfer_state(x_left, y, u_left, ec_left, target_mode, ec_right, opts)
%   Uses production current_injection to get I_left and terminal P/Q = V*conj(I),
%   then calls standalone branch equilibrium_initialize for target mode.
%   No PLL/Angle copy from GFL (WECC has no PLL); GFM angle from Vbus+I*Z.
mode_transfer_state = @(x_left, y, u_left, ec_left, target_mode, ec_right, varargin) ...
    dual_mode_transfer_state(x_left, y, u_left, ec_left, target_mode, ec_right, ...
        device_id, true, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, bp, u0, varargin{:});
% Backward-compatible alias
transfer_state = mode_transfer_state;

% --- Assemble device struct (composite_dae ABI, R3 Revision 2) -------------
dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = device_type_tag;
dev.mode = char(mode);
dev.initial_mode = char(mode);
dev.initial_online = true;
dev.nx = nx;
dev.nu = nu;
dev.state_names = state_names;
dev.input_names = {'P_ref','Q_ref','V_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.active_state_indices_for_context = active_state_indices_for_context;
dev.dynamic_state_indices_for_context = active_state_indices_for_context;
dev.equilibrium_constraint_specs = equilibrium_constraint_specs;
dev.mode_transfer_state = mode_transfer_state;
dev.transfer_state = transfer_state;
dev.mode_transfer = mode_transfer_state;  % alias for transfer_maps generic dispatcher
% --- Active-state metadata (equilibrium-local partition, not global freeze) ---
% Dual-mode superset has 20 states.  The active subset depends on the initial
% mode.  TS/SSSA consume frozen_state_indices for physical singular limits;
% inactive-mode unique states are NOT globally frozen here.  Instead, the
% equilibrium solver uses active_state_indices as a local mask, and the
% complement is held locally at the warm-start anchor dev.x0.
% Classification: PROJECT_DERIVED (equilibrium-local algebraic holding).
switch mode
case 'gfl'
    dev.active_state_indices = gfl_idx;
case 'GFM'
    dev.active_state_indices = gfm_idx;
case 'tripped'
    dev.active_state_indices = [];  % all held at anchor
end
dev.frozen_state_indices = [];
dev.frozen_state_values  = [];
dev.frozen_state_source  = '';
dev.frozen_state_classification = '';
dev.provenance = struct( ...
    'model', sprintf('dual_mode_%s_gfl_regfm_b1_g2', gfl_family), ...
    'source',['Reuses ', gfl_family, ' GFL + REGFM_B1 G2 as single source of truth'], ...
    'gfl_family', gfl_family, ...
    'superset_nx', nx, ...
    'shared_states', {{}}, ...
    'gfm_unique_states', {gfm_dev.state_names}, ...
    'gfl_unique_states', {gfl_dev.state_names}, ...
    'mode', char(mode), ...
    'inactive_state_rule','frozen (inactive branches held, dx=0; PROJECT_DERIVED)', ...
    'transfer_scope','physical P/Q/V/I transfer maps required at mode commit', ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES');
end

% =========================================================================
function dx = dual_f(x_dev, y, u_dev, event_context, device_id, default_online, default_mode, ...
    gfl_dev, gfm_dev, gfl_idx, gfm_idx, nx, u0)
%DUAL_F  Differential RHS (20 states).
%   Inactive branches are exact holds. Active-state reduction, rather than an
%   unsourced decay equation, keeps Newton/SSSA systems nonsingular.
dx = zeros(nx,1);
u = resolve_u(u_dev, u0);
[is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode);
if ~is_online
    dx = zeros(nx,1);
    return;
end

switch active_mode
case 'gfl'
    % Active: all seven WECC GFL states. All 13 REGFM states hold exactly.
    x_gfl = x_dev(gfl_idx);
    u_gfl = u(1:2);   % [P_ref; Q_ref]
    dx_gfl = gfl_dev.f(0, x_gfl, y, u_gfl, struct());
    dx(gfl_idx) = dx_gfl;
case 'GFM'
    % Active: all 13 REGFM states. All seven WECC GFL states hold exactly.
    x_gfm = x_dev(gfm_idx);
    u_gfm = [u(1); u(3)];   % [P_ref; V_ref]
    dx_gfm = gfm_dev.f(0, x_gfm, y, u_gfm, struct());
    dx(gfm_idx) = dx_gfm;
case 'tripped'
    % All states held (no active injection). current_injection=0.
end
end

% =========================================================================
function specs = dual_equilibrium_constraint_specs(x_dev,y,u_dev,event_context, ...
    device_id,default_online,default_mode,gfm_dev,gfm_idx,u0)
%DUAL_EQUILIBRIUM_CONSTRAINT_SPECS  Remap active GFM constraints to superset.
[is_online,active_mode]=resolve_status(event_context,device_id, ...
    default_online,default_mode);
if ~is_online || ~strcmp(active_mode,'GFM') || ...
        ~isfield(gfm_dev,'equilibrium_constraint_specs')
    specs=[];
    return;
end
ugfm=map_gfm_u(u_dev,u0);
base=gfm_dev.equilibrium_constraint_specs(x_dev(gfm_idx),y,ugfm,event_context);
specs=base;
for k=1:numel(base)
    b=base(k);
    specs(k).local_idx=gfm_idx(b.local_idx);
    specs(k).classify_fn=@(xf,yf,uf,ec) b.classify_fn( ...
        xf(gfm_idx),yf,map_gfm_u(uf,u0),ec);
    specs(k).residual_fn=@(xf,yf,uf,ec,reg) b.residual_fn( ...
        xf(gfm_idx),yf,map_gfm_u(uf,u0),ec,reg);
    specs(k).raw_dot_fn=@(xf,yf,uf,ec) b.raw_dot_fn( ...
        xf(gfm_idx),yf,map_gfm_u(uf,u0),ec);
    specs(k).admissible_fn=@(xf,yf,uf,ec,reg) b.admissible_fn( ...
        xf(gfm_idx),yf,map_gfm_u(uf,u0),ec,reg);
end
end

function ugfm=map_gfm_u(u_dev,u0)
u=resolve_u(u_dev,u0);
ugfm=[u(1);u(3)];
end

% =========================================================================
function idx = dual_active_state_indices(event_context, device_id, ...
    default_online, default_mode, gfl_idx, gfm_idx)
%DUAL_ACTIVE_STATE_INDICES  Device-owned runtime equilibrium partition.
[is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode);
if ~is_online
    idx = [];
    return;
end
switch active_mode
case 'gfl'
    idx = sort(gfl_idx);
case 'GFM'
    idx = sort(gfm_idx);
case 'tripped'
    idx = [];
end
end

% =========================================================================
function [is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode)
%RESOLVE_STATUS  Resolve one canonical online/mode status for every closure.
%   Runtime hybrid state, when present for this device_id, takes precedence
%   over constructor metadata. An offline device has zero current/power and no
%   active differential states regardless of its retained mode label.
is_online = logical(default_online);
raw_mode = default_mode;
if ~isempty(event_context) && isstruct(event_context) && ...
        isfield(event_context, 'hybrid_state') && ...
        isstruct(event_context.hybrid_state) && ...
        isfield(event_context.hybrid_state, 'device_modes') && ...
        isstruct(event_context.hybrid_state.device_modes)
    key = matlab.lang.makeValidName(char(device_id), ...
        'ReplacementStyle', 'underscore');
    hs = event_context.hybrid_state;
    if isfield(hs, 'device_online') && isstruct(hs.device_online) && ...
            isfield(hs.device_online, key)
        raw_online = hs.device_online.(key);
        if ~(islogical(raw_online) && isscalar(raw_online))
            error('ibr:dual_mode_ibr_model:badRuntimeOnline', ...
                'Runtime online flag for device %s must be one logical scalar.', ...
                char(device_id));
        end
        is_online = raw_online;
    end
    if isfield(hs.device_modes, key)
        raw_mode = hs.device_modes.(key);
    end
end
if ~(ischar(raw_mode) || (isstring(raw_mode) && isscalar(raw_mode)))
    error('ibr:dual_mode_ibr_model:badRuntimeMode', ...
        'Runtime mode for device %s must be a character vector or scalar string.', ...
        char(device_id));
end
switch lower(strtrim(char(raw_mode)))
case 'gfl'
    active_mode = 'gfl';
case 'gfm'
    active_mode = 'GFM';
case 'tripped'
    active_mode = 'tripped';
otherwise
    error('ibr:dual_mode_ibr_model:badRuntimeMode', ...
        'Unsupported runtime mode %s for device %s.', ...
        char(raw_mode), char(device_id));
end
end

% =========================================================================
function u = resolve_u(u_dev, u0)
%RESOLVE_U  Fall back to u0 when u_dev is empty (diagnostic calls from
%   mixed_equilibrium_solve.check_limits pass u_dev=[] at the equilibrium,
%   where u=u0). Non-empty u_dev is validated by the standalone models.
if isempty(u_dev)
    u = u0;
else
    u = u_dev;
end
end

% =========================================================================
function I = dual_current(x_dev, y, u_dev, event_context, device_id, ...
    default_online, default_mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0)
u = resolve_u(u_dev, u0);
[is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode);
if ~is_online
    I = 0.0 + 0.0i;
    return;
end
switch active_mode
case 'gfl'
    x_gfl = x_dev(gfl_idx);
    u_gfl = u(1:2);
    I = gfl_dev.current_injection(0, x_gfl, y, u_gfl, struct());
case 'GFM'
    x_gfm = x_dev(gfm_idx);
    u_gfm = [u(1); u(3)];
    I = gfm_dev.current_injection(0, x_gfm, y, u_gfm, struct());
case 'tripped'
    I = 0;
end
end

% =========================================================================
function Pe = dual_pe(x_dev, y, u_dev, event_context, device_id, ...
    default_online, default_mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0)
u = resolve_u(u_dev, u0);
[is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode);
if ~is_online
    Pe = 0.0;
    return;
end
switch active_mode
case 'gfl'
    x_gfl = x_dev(gfl_idx);
    u_gfl = u(1:2);
    Pe = gfl_dev.electrical_power(0, x_gfl, y, u_gfl, struct());
case 'GFM'
    x_gfm = x_dev(gfm_idx);
    u_gfm = [u(1); u(3)];
    Pe = gfm_dev.electrical_power(0, x_gfm, y, u_gfm, struct());
case 'tripped'
    Pe = 0;
end
end

% =========================================================================
function out = dual_reconstruct(x_dev, y, u_dev, event_context, device_id, ...
    default_online, default_mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, bp, u0)
u = resolve_u(u_dev, u0);
[is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode);
out = struct('mode', char(active_mode), 'bus_position', bp, ...
    'online', is_online);
if ~is_online
    out.current = 0.0 + 0.0i;
    out.electrical_power = 0.0;
    out.breaker_open = true;
    return;
end
switch active_mode
case 'gfl'
    x_gfl = x_dev(gfl_idx);
    u_gfl = u(1:2);
    out.gfl = gfl_dev.reconstruct(0, x_gfl, y, u_gfl, struct());
case 'GFM'
    x_gfm = x_dev(gfm_idx);
    u_gfm = [u(1); u(3)];
    out.gfm = gfm_dev.reconstruct(0, x_gfm, y, u_gfm, struct());
case 'tripped'
    out.tripped = true;
end
end

% =========================================================================
function x_eq = dual_equilibrium_initialize(V_bus, P_terminal_pu, ...
    Q_terminal_pu, event_context, device_id, default_online, default_mode, gfl_dev, gfm_dev, ...
    gfl_idx, gfm_idx, x_warm)
%DUAL_EQUILIBRIUM_INITIALIZE  Map exact active-branch state into superset.
[is_online, active_mode] = resolve_status( ...
    event_context, device_id, default_online, default_mode);
x_eq = x_warm;
if ~is_online
    if ~isscalar(P_terminal_pu) || ~isscalar(Q_terminal_pu) || ...
            ~isreal(P_terminal_pu) || ~isreal(Q_terminal_pu) || ...
            ~isfinite(P_terminal_pu) || ~isfinite(Q_terminal_pu) || ...
            abs(P_terminal_pu) > 64*eps(max(1,abs(P_terminal_pu))) || ...
            abs(Q_terminal_pu) > 64*eps(max(1,abs(Q_terminal_pu)))
        error('ibr:dual_mode_ibr_model:offlineEquilibriumPower', ...
            'An offline IBR equilibrium initializer requires zero terminal P/Q.');
    end
    return;
end
switch active_mode
case 'gfl'
    x_eq(gfl_idx) = gfl_dev.equilibrium_initialize( ...
        V_bus, P_terminal_pu, Q_terminal_pu, event_context);
case 'GFM'
    x_eq(gfm_idx) = gfm_dev.equilibrium_initialize( ...
        V_bus, P_terminal_pu, Q_terminal_pu, event_context);
case 'tripped'
    if ~isscalar(P_terminal_pu) || ~isscalar(Q_terminal_pu) || ...
            ~isreal(P_terminal_pu) || ~isreal(Q_terminal_pu) || ...
            ~isfinite(P_terminal_pu) || ~isfinite(Q_terminal_pu)
        error('ibr:dual_mode_ibr_model:trippedEquilibriumPower', ...
            'A tripped IBR equilibrium initializer requires zero terminal P/Q.');
    end
    pscale = max([1.0, abs(P_terminal_pu), abs(Q_terminal_pu)]);
    ptol = 64*eps(pscale);
    if abs(P_terminal_pu) > ptol || abs(Q_terminal_pu) > ptol
        error('ibr:dual_mode_ibr_model:trippedEquilibriumPower', ...
            'A tripped IBR equilibrium initializer requires zero terminal P/Q.');
    end
end
end

% =========================================================================
function [x_right, info] = dual_mode_transfer_state(x_left, y, u_left, ec_left, ...
    target_mode, ec_right, device_id, default_online, default_mode, ...
    gfl_dev, gfm_dev, gfl_idx, gfm_idx, bp, u0, varargin)
%DUAL_MODE_TRANSFER_STATE  Physical GFL<->GFM transfer using terminal V/I.
%   [X_RIGHT, INFO] = dual_mode_transfer_state(X_LEFT, Y, U_LEFT, EC_LEFT,
%   TARGET_MODE, EC_RIGHT, DEVICE_ID, DEFAULT_ONLINE, DEFAULT_MODE,
%   GFL_DEV, GFM_DEV, GFL_IDX, GFM_IDX, BP, U0, OPTS)
%
%   Physical contract (project-owned, no external solver):
%   - Vbus from y at bp, I_left from production current_injection dispatch
%   - S_left = Vbus*conj(I_left), P_left=real(S), Q_left=imag(S)
%   - Call standalone branch equilibrium_initialize(Vbus,P_left,Q_left,ec_right)
%     for target mode, which enforces its own current/P/Q/angle/voltage limits
%     and fails closed with stable IDs.
%   - Map result to 1:13 (GFM) or 14:20 (GFL), preserve inactive anchor.
%   - Verify current continuity |I_right-I_left| <= Tol (default 1e-10).
%
%   No PLL/angle copy from GFL: WECC REGC_A/REEC_A has no PLL state.
%   No bus_id or device_id hard-code inside transfer math; bus_position closure used.
%   No state-equation hard-code; delegates to standalone initializers and current_injection.
%
%   Fail-closed:
%   - V zero/non-finite -> ibr:transfer_maps:badVoltage
%   - I_left non-finite -> ibr:transfer_maps:badCurrent
%   - unsupported mode -> ibr:transfer_maps:unsupportedMode
%   - target initializer violates limit -> its own stable ID (propagated)
%   - continuity violation -> ibr:transfer_maps:currentContinuity

% --- Parse opts ------------------------------------------------------------
tol = 1e-10;
if ~isempty(varargin)
    if isstruct(varargin{1}) && isfield(varargin{1},'AbsTol')
        tol = varargin{1}.AbsTol;
    elseif isstruct(varargin{1}) && isfield(varargin{1},'tol')
        tol = varargin{1}.tol;
    elseif isnumeric(varargin{1}) && isscalar(varargin{1})
        tol = varargin{1};
    end
end
if ~(isscalar(tol) && isfinite(tol) && tol>0)
    error('ibr:transfer_maps:badTol','AbsTol must be finite positive scalar.');
end

% --- Validate target_mode ---------------------------------------------------
if ~(ischar(target_mode) || (isstring(target_mode) && isscalar(target_mode)))
    error('ibr:transfer_maps:unsupportedMode', ...
        'target_mode must be char or scalar string.');
end
tmode_raw = char(target_mode);
% Case-sensitive per mission: 'gfl' | 'GFM' | 'tripped'
if strcmp(tmode_raw,'GFM')
    target = 'GFM';
elseif strcmp(tmode_raw,'gfl')
    target = 'gfl';
elseif strcmp(tmode_raw,'tripped')
    target = 'tripped';
else
    % allow lower->GFM mapping for convenience? Strict fail-closed per spec.
    switch lower(strtrim(tmode_raw))
    case 'gfl'
        target = 'gfl';
    case 'gfm'
        target = 'GFM';
    case 'tripped'
        target = 'tripped';
    otherwise
        error('ibr:transfer_maps:unsupportedMode', ...
            'Unsupported target mode %s for device %s.', tmode_raw, char(device_id));
    end
end

% --- Validate x_left -------------------------------------------------------
if ~isvector(x_left) || numel(x_left) ~= (gfm_dev.nx+gfl_dev.nx)
    error('ibr:transfer_maps:badStateDim', ...
        'x_left must be %d-state vector (got %d).', gfm_dev.nx+gfl_dev.nx, numel(x_left));
end
if any(~isfinite(x_left))
    error('ibr:transfer_maps:badState', 'x_left contains non-finite values.');
end

% --- Extract Vbus from y using bus_position -------------------------------
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:transfer_maps:badVoltage', ...
        'Network state y does not contain finite voltage for bus_position %d.', bp);
end
Vbus = complex(y(2*bp-1), y(2*bp));
if ~isfinite(Vbus) || abs(Vbus) <= 1e-12
    error('ibr:transfer_maps:badVoltage', ...
        'Vbus must be finite with |V|>0 (got |V|=%.3g) for device %s.', abs(Vbus), char(device_id));
end

% --- Compute I_left using production dispatch ------------------------------
% Reuse dual_current logic (same as device current_injection closure)
% Resolve u
if isempty(u_left)
    u_res = u0;
else
    u_res = u_left;
end
% Determine source mode if ec_left provided, else infer from active indices?
% Use resolve_status for source mode detection (via ec_left) but we also have default.
[~, src_mode] = resolve_status(ec_left, device_id, default_online, default_mode);
% Compute I_left via dual_current
I_left = dual_current(x_left(:), y, u_res, ec_left, device_id, default_online, default_mode, ...
    gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0);
if ~isscalar(I_left) || ~isfinite(I_left)
    error('ibr:transfer_maps:badCurrent', ...
        'I_left must be finite scalar complex (got non-finite) for device %s.', char(device_id));
end

% --- S_left = Vbus*conj(I_left) -------------------------------------------
S_left = Vbus * conj(I_left);
P_left = real(S_left);
Q_left = imag(S_left);
if ~isfinite(P_left) || ~isfinite(Q_left)
    error('ibr:transfer_maps:badPower', 'P_left/Q_left non-finite for device %s.', char(device_id));
end

% --- Prepare ec_right with target mode if not already ----------------------
if isempty(ec_right) || ~isstruct(ec_right) || ~isfield(ec_right,'hybrid_state')
    ec_right = ec_left;
end
if isempty(ec_right)
    ec_right = struct();
end
if ~isfield(ec_right,'hybrid_state') || ~isstruct(ec_right.hybrid_state) || ...
        ~isfield(ec_right.hybrid_state,'device_modes')
    ec_right.hybrid_state = struct();
    ec_right.hybrid_state.device_modes = struct();
    ec_right.hybrid_state.device_online = struct();
end
key = matlab.lang.makeValidName(char(device_id), 'ReplacementStyle','underscore');
% Set target mode in right context
ec_right.hybrid_state.device_modes.(key) = target;
% The mode value, not the online breaker flag, represents the tripped
% converter branch in this device ABI. Keep the device online for every
% target mode so resolve_status observes the requested mode deterministically.
if ~isfield(ec_right.hybrid_state,'device_online') || ~isstruct(ec_right.hybrid_state.device_online)
    ec_right.hybrid_state.device_online = struct();
end
ec_right.hybrid_state.device_online.(key) = true;

% --- Call target branch initializer ---------------------------------------
x_right = x_left(:);  % start from left, preserve inactive anchor
switch target
case 'GFM'
    % Runtime transfer permits the disturbed terminal voltage to differ from
    % V_ref while preserving V/I continuity. Stationary equilibrium keeps its
    % stricter |V|=V_ref contract in equilibrium_initialize.
    if ~isfield(gfm_dev,'transfer_initialize') || ...
            ~isa(gfm_dev.transfer_initialize,'function_handle')
        error('ibr:transfer_maps:noRuntimeInitializer', ...
            'GFM target lacks a runtime transfer initializer.');
    end
    x_gfm_target = gfm_dev.transfer_initialize(Vbus, P_left, Q_left, ec_right);
    if numel(x_gfm_target) ~= gfm_dev.nx
        error('ibr:transfer_maps:badTargetStateDim','GFM target initializer returned wrong dimension.');
    end
    x_right(gfm_idx) = x_gfm_target;
    % gfl branch 14:20 preserved as inactive anchor
case 'gfl'
    x_gfl_target = gfl_dev.equilibrium_initialize(Vbus, P_left, Q_left, ec_right);
    if numel(x_gfl_target) ~= gfl_dev.nx
        error('ibr:transfer_maps:badTargetStateDim','GFL target initializer returned wrong dimension.');
    end
    x_right(gfl_idx) = x_gfl_target;
    % gfm branch preserved
case 'tripped'
    % tripped: all frozen, current zero; continuity not applicable (intentional island)
    % Keep x_right = x_left (exact hold) to satisfy inactive preservation
    % No initializer call; tripped requires zero P/Q which would not match P_left unless island.
    % For physical transfer to tripped, we deliberately keep states and let I_right=0.
    % To avoid false continuity error, skip continuity check for tripped target.
otherwise
    error('ibr:transfer_maps:unsupportedMode','Unsupported target mode %s.', target);
end

% --- Compute I_right at same Vbus -----------------------------------------
if strcmp(target,'tripped')
    I_right = 0+0i;
    P_right = 0;
    Q_right = 0;
else
    I_right = dual_current(x_right, y, u_res, ec_right, device_id, default_online, default_mode, ...
        gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0);
    if ~isfinite(I_right)
        error('ibr:transfer_maps:badCurrent','I_right non-finite after target init for device %s.', char(device_id));
    end
    S_right = Vbus * conj(I_right);
    P_right = real(S_right);
    Q_right = imag(S_right);
end

% --- Continuity check (except tripped) ------------------------------------
if ~strcmp(target,'tripped')
    if abs(I_right - I_left) > tol
        error('ibr:transfer_maps:currentContinuity', ...
            ['Current continuity violation for device %s: |I_right-I_left|=%.3g > Tol=%.3g ' ...
             '(I_left=%.6g%+.6gj, I_right=%.6g%+.6gj, V=%.6g%+.6gj).'], ...
            char(device_id), abs(I_right-I_left), tol, real(I_left), imag(I_left), real(I_right), imag(I_right), real(Vbus), imag(Vbus));
    end
end

% --- Info for testing ------------------------------------------------------
info = struct('Vbus',Vbus,'I_left',I_left,'I_right',I_right, ...
    'P_left',P_left,'Q_left',Q_left,'P_right',P_right,'Q_right',Q_right, ...
    'tol',tol,'source_mode',char(src_mode),'target_mode',char(target), ...
    'gfm_idx',gfm_idx,'gfl_idx',gfl_idx);

end

% =========================================================================
function s = rmfield_if(s, name)
%RMFIELD_IF  Remove a field if present; otherwise return the struct unchanged.
if isfield(s, name)
    s = rmfield(s, name);
end
end
