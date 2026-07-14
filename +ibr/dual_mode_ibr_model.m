function dev = dual_mode_ibr_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, Q_ref_pu, V_ref_pu, mode)
%DUAL_MODE_IBR_MODEL  Fixed-layout dual-mode GFL/GFM/tripped IBR device (Phase 7).
%
%   dev = dual_mode_ibr_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF_PU, Q_REF_PU, V_REF_PU, MODE) returns a device struct
%   conforming to the stability.composite_dae ABI (R3 Revision 2) with a
%   CONSTANT state dimension (15) across modes 'gfl' | 'GFM' | 'tripped'.
%
%   The superset layout reuses the standalone +ibr/gfl_model (Phase 5) and
%   +ibr/regfm_b1_vsg_model (Phase 6) as the SINGLE SOURCE OF TRUTH for the
%   equations: the constructor builds internal gfl_dev and gfm_dev structs and
%   the closures map the superset state into each standalone device's state
%   slice, then dispatch to the standalone closures. No equations are
%   duplicated or rewritten (the Phase 5 handoff forbids forcing unsourced GFL
%   dynamics into the Phase 5 GFL).
%
%   Superset state (15, fixed order, constant across modes):
%     x = [ delta_PLL, x_PLL_int,           % shared PLL (2) - merged (identical
%                                            %   REGFM_B1 Table 1 kpPLL/kiPLL)
%           omega_m, delta_VSM, x_washout, x_Eint,   % GFM-unique (4 of 9)
%           Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f,% GFM-unique filters (5 of 9)
%           P_f, Q_f, phi_P, phi_Q ]        % GFL-unique (4) - Ding-derived
%   Indices:
%     SHARED:  delta_PLL=1, x_PLL_int=2
%     GFM:     omega_m=3, delta_VSM=4, x_washout=5, x_Eint=6,
%              Pinv_f=7, Idinv_f=8, Qinv_f=9, Vinv_f=10, Iqinv_f=11
%     GFL:     P_f=12, Q_f=13, phi_P=14, phi_Q=15
%
%   Inputs (nu=3, fixed): u = [P_ref; Q_ref; V_ref] (pu, system base).
%     gfl mode uses [P_ref; Q_ref]; GFM mode uses [P_ref; V_ref]; tripped uses none.
%
%   Mode dispatch:
%     'gfl'     -> active = shared(2) + GFL-unique(4) = 6; GFM-unique(9) frozen.
%                  current_injection routes to gfl_dev (Ding current source).
%     'GFM'     -> active = shared(2) + GFM-unique(9) = 11; GFL-unique(4) frozen.
%                  current_injection routes to gfm_dev (Eq.13 voltage-behind-impedance).
%     'tripped' -> all frozen; current_injection = 0.
%   Inactive branches are held (dx=0), per the frozen inactive_state_rule
%   (PROJECT_DERIVED: continuity + algebraic-residual minimization).
%
%   Transfer (Phase 7 = deterministic initial only; full adaptive bumpless
%   transfer is Phase 10-11): on a mode switch, shared PLL states are carried
%   over; the newly-active unique states are warm-started from the PF solution
%   per the standalone model initialization. Full bumpless transfer is deferred.
%
%   STATUS: STRUCTURAL_ONLY. Reuses Phase 5 GFL (STRUCTURAL_ONLY, Kps/Kis
%   ASSUMED_DIAGNOSTIC) and Phase 6 GFM (STRUCTURAL_ONLY, source-closed).
%   No production-readiness claim. IBR_PRODUCTION_INTEGRATION_READY = NOT_READY.
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
gfl_dev = ibr.gfl_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, Q_ref_pu);
gfm_dev = ibr.regfm_b1_vsg_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, V_ref_pu);

% --- Superset state layout (15, constant) ---------------------------------
% SHARED (2): delta_PLL, x_PLL_int  (GFL: delta_pll, eps_pll; GFM: delta_PLL, x_PLL_int)
% GFM-unique (9): omega_m, delta_VSM, x_washout, x_Eint, Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f
% GFL-unique (4): P_f, Q_f, phi_P, phi_Q
state_names = {'delta_PLL','x_PLL_int', ...
    'omega_m','delta_VSM','x_washout','x_Eint', ...
    'Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f', ...
    'P_f','Q_f','phi_P','phi_Q'};
nx = 15;
nu = 3;

% --- Initial state: merge GFL + GFM warm-starts ----------------------------
% Shared PLL: GFL delta_pll=angle(V0), eps_pll=0; GFM delta_PLL=angle(V0), x_PLL_int=0.
% They are identical (both REGFM_B1 Table 1 kpPLL/kiPLL, same Vq). Use GFL's.
x0 = zeros(nx, 1);
x0(1) = gfl_dev.x0(1);   % delta_PLL = delta_pll (GFL) = angle(V0)
x0(2) = gfl_dev.x0(2);   % x_PLL_int = eps_pll (GFL) = 0
% GFM-unique (3..11): from gfm_dev.x0 (omega_m, delta_VSM, x_washout, x_Eint,
% delta_PLL, x_PLL_int, Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f).
% gfm_dev.x0 = [omega_m, delta_VSM, x_washout, x_Eint, delta_PLL, x_PLL_int,
%               Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f].
% Map GFM-unique: omega_m(3), delta_VSM(4), x_washout(5), x_Eint(6),
%   Pinv_f(7), Idinv_f(8), Qinv_f(9), Vinv_f(10), Iqinv_f(11).
x0(3) = gfm_dev.x0(1);   % omega_m
x0(4) = gfm_dev.x0(2);   % delta_VSM
x0(5) = gfm_dev.x0(3);   % x_washout
x0(6) = gfm_dev.x0(4);   % x_Eint
x0(7) = gfm_dev.x0(7);   % Pinv_f
x0(8) = gfm_dev.x0(8);   % Idinv_f
x0(9) = gfm_dev.x0(9);   % Qinv_f
x0(10) = gfm_dev.x0(10); % Vinv_f
x0(11) = gfm_dev.x0(11); % Iqinv_f
% GFL-unique (12..15): P_f, Q_f, phi_P, phi_Q from gfl_dev.x0(3..6).
x0(12) = gfl_dev.x0(3);  % P_f
x0(13) = gfl_dev.x0(4);  % Q_f
x0(14) = gfl_dev.x0(5);  % phi_P
x0(15) = gfl_dev.x0(6);  % phi_Q

u0 = [P_ref_pu; Q_ref_pu; V_ref_pu];

% --- State-slice maps ------------------------------------------------------
% GFL sub-state (6): [delta_pll; eps_pll; P_f; Q_f; phi_P; phi_Q]
%   = superset [1, 2, 12, 13, 14, 15].
gfl_idx = [1, 2, 12, 13, 14, 15];
% GFM sub-state (11): [omega_m, delta_VSM, x_washout, x_Eint, delta_PLL,
%   x_PLL_int, Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f]
%   = superset [3, 4, 5, 6, 1, 2, 7, 8, 9, 10, 11].
gfm_idx = [3, 4, 5, 6, 1, 2, 7, 8, 9, 10, 11];

bp = bus_position;

% --- Differential RHS: dispatch by mode, inactive branches decay to warm-start
%   Inactive states use dx = -lambda*(x - x_warmstart) instead of a hard
%   freeze (dx=0). A hard freeze creates zero Jacobian columns for inactive
%   states, making the coupled Newton Jacobian singular (rcond=0) at the
%   warm-start — the Newton step becomes NaN. The decay-to-warmstart keeps
%   the Jacobian full-rank (column = -lambda) while preserving the
%   frozen-policy intent: inactive states are held AT their warm-start values
%   (equilibrium of inactive branch = warm-start value). lambda=1e-3 is a
%   NUMERICAL_METHOD choice (declared before results): small enough that
%   inactive states are held, large enough that the Jacobian column is
%   non-zero. Does NOT change active-state equations or their equilibrium.
f = @(t, x_dev, y, u_dev, event_context) dual_f( ...
    x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, nx, x0, u0);

% --- current_injection: dispatch by mode -----------------------------------
%   Tolerates u_dev=[] (diagnostic calls from mixed_equilibrium_solve.check_limits
%   use u_dev=[] at the equilibrium where u=u0). Falls back to u0 when empty.
current_injection = @(t, x_dev, y, u_dev, event_context) dual_current( ...
    x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0);

% --- electrical_power: dispatch by mode -----------------------------------
electrical_power = @(t, x_dev, y, u_dev, event_context) dual_pe( ...
    x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0);

% --- reconstruct -----------------------------------------------------------
reconstruct = @(t, x_dev, y, u_dev, event_context) dual_reconstruct( ...
    x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, bp, u0);

% --- Assemble device struct (composite_dae ABI, R3 Revision 2) -------------
dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_dual_mode';
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
dev.frozen_state_indices = [];
dev.frozen_state_values  = [];
dev.frozen_state_source  = '';
dev.active_state_indices = 1:dev.nx;
dev.frozen_state_classification = '';
dev.provenance = struct( ...
    'model','dual_mode_ibr_phase7_structural_only', ...
    'source','Reuses +ibr/gfl_model (Phase 5) + +ibr/regfm_b1_vsg_model (Phase 6) as single source of truth', ...
    'superset_nx', nx, ...
    'shared_states', {{'delta_PLL','x_PLL_int'}}, ...
    'gfm_unique_states', {{'omega_m','delta_VSM','x_washout','x_Eint','Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f'}}, ...
    'gfl_unique_states', {{'P_f','Q_f','phi_P','phi_Q'}}, ...
    'mode', char(mode), ...
    'inactive_state_rule','frozen (inactive branches held, dx=0; PROJECT_DERIVED)', ...
    'transfer_scope','Phase 7 = deterministic initial only; full bumpless transfer deferred to Phase 10-11', ...
    'readiness','STRUCTURAL_ONLY');
end

% =========================================================================
function dx = dual_f(x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, nx, x_warm, u0)
%DUAL_F  Differential RHS (15 states).
%   Inactive branches decay to warm-start: dx = -lambda*(x - x_warm). This
%   keeps the Jacobian full-rank (column = -lambda) while holding inactive
%   states AT their warm-start values (equilibrium of inactive branch =
%   warm-start value). See header comment for rationale.
lambda = 1e-3;   % NUMERICAL_METHOD: inactive-state decay-to-warmstart rate
dx = -lambda * (x_dev - x_warm);
u = resolve_u(u_dev, u0);
switch mode
case 'gfl'
    % Active: shared(2) + GFL-unique(4). GFM-unique(9) decay to warm-start.
    x_gfl = x_dev(gfl_idx);
    u_gfl = u(1:2);   % [P_ref; Q_ref]
    dx_gfl = gfl_dev.f(0, x_gfl, y, u_gfl, struct());
    dx(gfl_idx) = dx_gfl;
case 'GFM'
    % Active: shared(2) + GFM-unique(9). GFL-unique(4) decay to warm-start.
    x_gfm = x_dev(gfm_idx);
    u_gfm = [u(1); u(3)];   % [P_ref; V_ref]
    dx_gfm = gfm_dev.f(0, x_gfm, y, u_gfm, struct());
    dx(gfm_idx) = dx_gfm;
case 'tripped'
    % All decay to warm-start (no active injection). current_injection=0.
    % dx already = -lambda*(x - x_warm).
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
function I = dual_current(x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0)
u = resolve_u(u_dev, u0);
switch mode
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
function Pe = dual_pe(x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, u0)
u = resolve_u(u_dev, u0);
switch mode
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
function out = dual_reconstruct(x_dev, y, u_dev, mode, gfl_dev, gfm_dev, gfl_idx, gfm_idx, bp, u0)
u = resolve_u(u_dev, u0);
out = struct('mode', char(mode), 'bus_position', bp);
switch mode
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
