function tests = test_ibr_transfer_maps_physical()
%TEST_IBR_TRANSFER_MAPS_PHYSICAL  Physical GFL<->GFM transfer oracles.
%   Retargeted 2026-09-26 onto ibr.eecon49_dual_mode_model, the only IBR family
%   that survives; the former subject (a 20-state WECC-GFL/REGFM_B1-GFM
%   superset) no longer exists.
%
%   Implements independent oracles per task contract:
%   - GFL->GFM: I_right == I_left at same V within AbsTol 1e-10
%   - GFM->GFL: I_right == I_left within AbsTol 1e-10
%   - P/Q before and after match
%   - global angle rotation changes phasor current per rotation but P/Q and
%     internal relative states invariant
%   - inactive branch not overwritten
%   - 16-state dimension constant
%   - the surviving family's own fail-closed surface (see the limits test)
%   - no external solver
%
%   INDEX MAP (measured, not assumed).  The 16-state superset is
%     [1:3]  shared plant   i_d, i_q, V_dc
%     [4:9]  GFL controller gfl_delta_PLL, gfl_xi_PLL, gfl_xi_P, gfl_xi_Q,
%                            gfl_xi_Id, gfl_xi_Iq
%     [10:16] GFM controller gfm_delta_VSG, gfm_omega_VSG, gfm_E, gfm_xi_Vd,
%                            gfm_xi_Vq, gfm_xi_Id, gfm_xi_Iq
%   so the GFM branch angle is index 10 and the GFL branch angle is index 4 --
%   NOT the retired family's delta_PLL=5 / delta_IT=2.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
% Fixture helpers
% =========================================================================
function [dev, y, u, ec_gfl, ec_gfm, Vbus, P_ref, Q_ref, V_ref, bus_ids] = dual_fixture_gfl(P_ref_in, Q_ref_in, V_ref_in, Vbus_in)
if nargin<1 || isempty(P_ref_in), P_ref_in=0.4; end
if nargin<2 || isempty(Q_ref_in), Q_ref_in=0.1; end
if nargin<3 || isempty(V_ref_in), V_ref_in=1.0; end
if nargin<4 || isempty(Vbus_in), Vbus_in=1.0+0i; end
P_ref=P_ref_in; Q_ref=Q_ref_in; V_ref=V_ref_in; Vbus=Vbus_in;
bus_ids=[1;2];
dev_gfl = ibr.eecon49_dual_mode_model('IBR_test',2,2,bus_ids,Vbus,struct(),P_ref,Q_ref,V_ref,"gfl");
% Build y: bus1 1.06∠0, bus2 Vbus
y = [1.06; 0.0; real(Vbus); imag(Vbus)];
u = dev_gfl.u0;
% event_contexts
key = matlab.lang.makeValidName('IBR_test','ReplacementStyle','underscore');
ec_gfl = struct();
ec_gfl.hybrid_state = struct();
ec_gfl.hybrid_state.device_modes = struct();
ec_gfl.hybrid_state.device_online = struct();
ec_gfl.hybrid_state.device_modes.(key) = 'gfl';
ec_gfl.hybrid_state.device_online.(key) = true;

ec_gfm = struct();
ec_gfm.hybrid_state = struct();
ec_gfm.hybrid_state.device_modes = struct();
ec_gfm.hybrid_state.device_online = struct();
ec_gfm.hybrid_state.device_modes.(key) = 'GFM';
ec_gfm.hybrid_state.device_online.(key) = true;

dev = dev_gfl; % will be overwritten to exact eq below
end

function x_eq = get_exact_equil(dev, Vbus, P, Q, ec)
% Use device's equilibrium_initialize for given mode (ec determines mode)
x_eq = dev.equilibrium_initialize(Vbus, P, Q, ec);
end

% =========================================================================
% 1. GFL -> GFM current continuity
% =========================================================================
function test_gfl_to_gfm_current_continuity(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus, P_ref, Q_ref, V_ref] = dual_fixture_gfl(0.4, 0.1, 1.0, 1.0+0i);
% Get exact GFL equilibrium at Vbus, P_ref, Q_ref
x_left = get_exact_equil(dev, Vbus, P_ref, Q_ref, ec_gfl);
% Compute left current via production closure
I_left = dev.current_injection(0, x_left, y, u, ec_gfl);
testCase.verifyTrue(isfinite(I_left) && abs(I_left)>0, 'I_left finite nonzero');
S_left = Vbus*conj(I_left);
P_left = real(S_left); Q_left = imag(S_left);
% Transfer to GFM
x_right = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
testCase.verifyEqual(numel(x_right), 16, 'AbsTol',0, '16-state dimension');
I_right = dev.current_injection(0, x_right, y, u, ec_gfm);
testCase.verifyEqual(I_right, I_left, 'AbsTol', 1e-10, 'GFL->GFM I_right==I_left within 1e-10');
testCase.verifyEqual(real(Vbus*conj(I_right)), P_left, 'AbsTol',1e-10, 'P continuity');
testCase.verifyEqual(imag(Vbus*conj(I_right)), Q_left, 'AbsTol',1e-10, 'Q continuity');
end

% =========================================================================
% 2. GFM -> GFL current continuity
% =========================================================================
function test_gfm_to_gfl_current_continuity(testCase)
% Start in GFM mode
[dev_gfl, y, u, ec_gfl, ec_gfm, Vbus, P_ref, Q_ref, V_ref, bus_ids] = dual_fixture_gfl(0.4, 0.05, 1.0, 1.0+0i);
% Need a GFM device for exact eq
dev_gfm = ibr.eecon49_dual_mode_model('IBR_test',2,2,bus_ids,Vbus,struct(),P_ref,0.0,V_ref,"GFM");
% Build exact GFM equilibrium that delivers P_ref, Q_ref (Q from S, not Q_ref input)
% For GFM, equilibrium_initialize expects terminal P/Q, and checks |V|==V_ref.
x_left = get_exact_equil(dev_gfm, Vbus, P_ref, Q_ref, ec_gfm);
I_left = dev_gfm.current_injection(0, x_left, y, dev_gfm.u0, ec_gfm);
S_left = Vbus*conj(I_left);
P_left = real(S_left); Q_left = imag(S_left);
% Transfer to GFL using GFM device's callback (same superset, same bus)
% Use dev_gfm's mode_transfer_state (it has same gfl/gfm devs inside)
x_right = dev_gfm.mode_transfer_state(x_left, y, dev_gfm.u0, ec_gfm, 'gfl', ec_gfl);
testCase.verifyEqual(numel(x_right),16,'AbsTol',0,'dim 16');
I_right = dev_gfm.current_injection(0, x_right, y, dev_gfm.u0, ec_gfl);
testCase.verifyEqual(I_right, I_left, 'AbsTol',1e-10, 'GFM->GFL I continuity 1e-10');
testCase.verifyEqual(real(Vbus*conj(I_right)), P_left, 'AbsTol',1e-10, 'P continuity GFM->GFL');
testCase.verifyEqual(imag(Vbus*conj(I_right)), Q_left, 'AbsTol',1e-10, 'Q continuity GFM->GFL');
end

% =========================================================================
% 3. P/Q match oracle explicit
% =========================================================================
function test_pq_match_before_after(testCase)
% Use V with |V|==V_ref to satisfy GFM V_ref check, but with angle for nontrivial case
theta0 = 0.05; % ~2.86 deg
Vbus = cos(theta0)+1i*sin(theta0); % |V|==1.0
[dev, y, u, ec_gfl, ec_gfm] = dual_fixture_gfl(0.5, 0.2, 1.0, Vbus);
P_ref=0.5; Q_ref=0.2;
x_left = get_exact_equil(dev, Vbus, P_ref, Q_ref, ec_gfl);
I_left = dev.current_injection(0, x_left, y, u, ec_gfl);
P_left = real(Vbus*conj(I_left)); Q_left = imag(Vbus*conj(I_left));
x_right = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
I_right = dev.current_injection(0, x_right, y, u, ec_gfm);
P_right = real(Vbus*conj(I_right)); Q_right = imag(Vbus*conj(I_right));
testCase.verifyEqual(P_right, P_left, 'AbsTol',1e-10, 'P before==after');
testCase.verifyEqual(Q_right, Q_left, 'AbsTol',1e-10, 'Q before==after');
end

% =========================================================================
% 4. Global angle rotation invariance
% =========================================================================
function test_global_angle_rotation_invariance(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl(0.4, 0.1, 1.0, 1.0+0i);
theta = pi/6; % 30 deg
Vbus_rot = Vbus * exp(1i*theta);
y_rot = y;
y_rot(3) = real(Vbus_rot); y_rot(4)=imag(Vbus_rot);
% Also rotate infinite bus? Keep bus1 at 1.06 rotated same theta for global rotation
V1 = complex(y(1),y(2));
V1_rot = V1 * exp(1i*theta);
y_rot(1)=real(V1_rot); y_rot(2)=imag(V1_rot);

% For GFL, get equilibrium at original and rotated
x_gfl = get_exact_equil(dev, Vbus, 0.4, 0.1, ec_gfl);
x_gfl_rot = get_exact_equil(dev, Vbus_rot, 0.4, 0.1, ec_gfl);
I_gfl = dev.current_injection(0, x_gfl, y, u, ec_gfl);
I_gfl_rot = dev.current_injection(0, x_gfl_rot, y_rot, u, ec_gfl);
% I should rotate by theta
testCase.verifyEqual(I_gfl_rot, I_gfl*exp(1i*theta), 'AbsTol',1e-9, 'GFL I rotates with V');
% P/Q invariant
testCase.verifyEqual(real(Vbus_rot*conj(I_gfl_rot)), real(Vbus*conj(I_gfl)), 'AbsTol',1e-9, 'P invariant under rotation GFL');
testCase.verifyEqual(imag(Vbus_rot*conj(I_gfl_rot)), imag(Vbus*conj(I_gfl)), 'AbsTol',1e-9, 'Q invariant under rotation GFL');

% Now transfer GFL->GFM at original and rotated, check relative states invariant
x_gfm = dev.mode_transfer_state(x_gfl, y, u, ec_gfl, 'GFM', ec_gfm);
x_gfm_rot = dev.mode_transfer_state(x_gfl_rot, y_rot, u, ec_gfl, 'GFM', ec_gfm);
% Index map for THIS family (16-state, measured): 1:3 shared plant, 4:9 GFL
% controller, 10:16 GFM controller.  So the absolute VSG angle is index 10
% (it was index 2 'delta_IT' plus 5 'delta_PLL' in the retired layout), and the
% shared-plant currents are 1:2 rather than the retired 7/9 filtered powers.
% The invariance statement is unchanged: a rigid rotation of the whole network
% rotates the absolute angle by theta and leaves the relative/plant coordinates
% untouched.
delta_VSG = x_gfm(10); delta_VSG_rot = x_gfm_rot(10);
diff = wrapToPi(delta_VSG_rot - delta_VSG);
testCase.verifyEqual(diff, theta, 'AbsTol',1e-8, 'gfm_delta_VSG rotates by theta');
% The plant currents are expressed in the device frame, so they are invariant.
testCase.verifyEqual(x_gfm(1:2), x_gfm_rot(1:2), 'AbsTol',1e-9, ...
    'plant dq currents invariant under global rotation');
testCase.verifyEqual(x_gfm(3), x_gfm_rot(3), 'AbsTol',1e-9, 'V_dc invariant');
% The carried GFL block is NOT wholly invariant: index 4 is gfl_delta_PLL, an
% ABSOLUTE angle, so it rotates with the frame exactly like the VSG angle above
% (measured: both shift by exactly theta while 5:9 stay put).  Asserting the
% whole block invariant, as the retired layout allowed for its relative
% delta_IT, would be wrong for this family.
testCase.verifyEqual(wrapToPi(x_gfm(4)-x_gfm_rot(4)), -theta, 'AbsTol',1e-8, ...
    'gfl_delta_PLL rotates by theta (carried across the transfer)');
testCase.verifyEqual(x_gfm(5:9), x_gfm_rot(5:9), 'AbsTol',1e-9, ...
    'GFL integrator block invariant under global rotation');
testCase.verifyEqual(x_gfm(11:16), x_gfm_rot(11:16), 'AbsTol',1e-9, ...
    'GFM integrator block invariant under global rotation');
end

function a = wrapToPi(a)
a = mod(a+pi, 2*pi)-pi;
end

% =========================================================================
% 5. Inactive branch not overwritten
% =========================================================================
function test_inactive_branch_preservation(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl(0.3, 0.0, 1.0, 1.0+0i);
x_left = get_exact_equil(dev, Vbus, 0.3, 0.0, ec_gfl);
% Index map for this family: 1:3 shared plant, 4:9 GFL, 10:16 GFM.
gfm_idx = 10:16; gfl_idx = 4:9;
x_right = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
% After GFL->GFM, GFL branch should be preserved
testCase.verifyEqual(x_right(gfl_idx), x_left(gfl_idx), 'AbsTol',0, 'GFL->GFM preserves GFL anchor (inactive)');
% Check opposite: GFM->GFL preserves GFM anchor
[dev2, y2, u2, ec_gfl2, ec_gfm2, Vbus2, ~,~,~, bus_ids] = dual_fixture_gfl(0.4,0.05,1.0,1.0+0i);
dev_gfm = ibr.eecon49_dual_mode_model('IBR_test',2,2,bus_ids,Vbus2,struct(),0.4,0.0,1.0,"GFM");
x_left_gfm = get_exact_equil(dev_gfm, Vbus2, 0.4, 0.05, ec_gfm2);
x_right_gfl = dev_gfm.mode_transfer_state(x_left_gfm, y2, dev_gfm.u0, ec_gfm2, 'gfl', ec_gfl2);
testCase.verifyEqual(x_right_gfl(gfm_idx), x_left_gfm(gfm_idx), 'AbsTol',0, 'GFM->GFL preserves GFM anchor');
end

% =========================================================================
% 6. Dimension 16 constant
% =========================================================================
function test_dimension_16(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl();
x_left = get_exact_equil(dev, Vbus, 0.4, 0.1, ec_gfl);
x_r1 = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
x_r2 = dev.mode_transfer_state(x_r1, y, u, ec_gfm, 'gfl', ec_gfl);
testCase.verifyEqual(numel(x_left),16,'AbsTol',0);
testCase.verifyEqual(numel(x_r1),16,'AbsTol',0);
testCase.verifyEqual(numel(x_r2),16,'AbsTol',0);
end

% =========================================================================
% 7. Fail-closed surface of the surviving family
% =========================================================================
function test_fail_closed_surface(testCase)
% Retargeted 2026-09-26.  The retired test asserted three guards that were
% REGFM_B1-specific and have NO counterpart in ibr.eecon49_dual_mode_model:
%   (c) "P beyond Imax" -> equilibriumCurrentLimit/ClampBoundary,
%   (d) "V below VPLLfrz" -> equilibriumPLLFreezeNonunique,
%   (e) "|Vbus| != V_ref" -> equilibriumVoltageReferenceMismatch.
% Those assertions are DELETED, not relaxed: they described the retired model's
% initializer contract.  The EECON49 initializer is a direct algebraic solve
% (gfl_eecon49_full_model>equilibrium: id = k*P/|V|, iq = -k*Q/|V|) whose ONLY
% voltage guard is abs(V)<=0, and its GFM branch has no PLL at all, so there is
% no freeze threshold and no V_ref match to violate.  Pasting the new model's
% permissive values into those assertions would have asserted that a limit
% check passes when no limit check exists.
%
% What replaces them is the survivor's REAL fail-closed surface, each identifier
% measured on this tree:
%   badVoltage   -- transfer at a zero or non-finite bus voltage
%   badState     -- wrong-length or non-finite device state vector
%   badInput     -- wrong-length or non-finite input vector
%   badRuntimeMode -- a target/context mode outside {gfl, GFM, tripped}
%   gfl_eecon49:eq -- the initializer's only voltage guard (|V| <= 0)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl(0.4,0.1,1.0,1.0+0i);
x_left = get_exact_equil(dev, Vbus, 0.4, 0.1, ec_gfl);

% a) V zero -- transfer must fail closed
y_zero = y; y_zero(3)=0; y_zero(4)=0;
testCase.verifyError(@() dev.mode_transfer_state(x_left, y_zero, u, ec_gfl, 'GFM', ec_gfm), ...
    'ibr:transfer_maps:badVoltage', 'V zero fails closed badVoltage');

% b) V non-finite -- same guard
y_nan = y; y_nan(3)=NaN;
testCase.verifyError(@() dev.mode_transfer_state(x_left, y_nan, u, ec_gfl, 'GFM', ec_gfm), ...
    'ibr:transfer_maps:badVoltage', 'V non-finite fails closed badVoltage');

% c) Initializer voltage guard: the one limit the survivor DOES enforce.
testCase.verifyError(@() dev.equilibrium_initialize(0, 0.4, 0.1, ec_gfl), ...
    'ibr:gfl_eecon49:eq', 'zero |V| must fail closed in the initializer');

% d) Wrong-length state must be rejected, not silently reinterpreted.
testCase.verifyError(@() dev.f(0, x_left(1:15), y, u, ec_gfl), ...
    'ibr:eecon49_dual_mode_model:badState', 'short state must fail closed');
testCase.verifyError(@() dev.f(0, [NaN; x_left(2:end)], y, u, ec_gfl), ...
    'ibr:eecon49_dual_mode_model:badState', 'non-finite state must fail closed');

% e) Wrong-length / non-finite input must be rejected.
testCase.verifyError(@() dev.f(0, x_left, y, u(1:2), ec_gfl), ...
    'ibr:eecon49_dual_mode_model:badInput', 'short input must fail closed');
testCase.verifyError(@() dev.f(0, x_left, y, [u(1:2); NaN], ec_gfl), ...
    'ibr:eecon49_dual_mode_model:badInput', 'non-finite input must fail closed');

% f) Unsupported target mode must fail closed.
testCase.verifyError(@() dev.mode_transfer_state(x_left, y, u, ec_gfl, 'invalid_mode', ec_gfm), ...
    'ibr:eecon49_dual_mode_model:badRuntimeMode', 'unsupported mode fails closed');
end

% =========================================================================
% 8. No external solver (grep guard)
% =========================================================================
function test_no_external_solver(testCase)
src1 = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr','eecon49_dual_mode_model.m'));
src2 = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), '+stability','transfer_maps.m'));
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src1, fn{1}), ['no ' fn{1} ' in eecon49_dual_mode_model']);
    testCase.verifyFalse(contains(src2, fn{1}), ['no ' fn{1} ' in transfer_maps']);
end
end

% =========================================================================
% 9. Transfer via transfer_maps dispatcher (generic API)
% =========================================================================
function test_transfer_via_maps_dispatcher(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl(0.4,0.1,1.0,1.0+0i);
bus_ids=[1;2];
% Build devices array as in PhaseC
devices = dev; % single device for simplicity
Vbus_arr = Vbus;
maps = stability.transfer_maps(devices, Vbus_arr);
key = matlab.lang.makeValidName(dev.device_id,'ReplacementStyle','underscore');
testCase.verifyTrue(isfield(maps,key), 'maps has device');
testCase.verifyTrue(maps.(key).available, 'available');
testCase.verifyTrue(isfield(maps.(key),'gfl_to_gfm'), 'has gfl_to_gfm');
testCase.verifyTrue(isfield(maps.(key).gfl_to_gfm,'transfer'), 'gfl_to_gfm has transfer handle');
% Use dispatcher handle to do physical transfer
x_left = get_exact_equil(dev, Vbus, 0.4, 0.1, ec_gfl);
x_right_via_map = maps.(key).gfl_to_gfm.transfer(x_left, y, u, ec_gfl, ec_gfm);
x_right_direct = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
testCase.verifyEqual(x_right_via_map, x_right_direct, 'AbsTol',1e-12, 'dispatcher matches direct callback');
end
