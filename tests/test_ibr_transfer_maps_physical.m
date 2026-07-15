function tests = test_ibr_transfer_maps_physical()
%TEST_IBR_TRANSFER_MAPS_PHYSICAL  Physical GFL<->GFM transfer oracles.
%   Implements independent oracles per task contract:
%   - GFL->GFM: I_right == I_left at same V within AbsTol 1e-10
%   - GFM->GFL: I_right == I_left within AbsTol 1e-10
%   - P/Q before and after match
%   - global angle rotation changes phasor current per rotation but P/Q and
%     internal relative states invariant
%   - inactive branch not overwritten
%   - 20-state dimension constant
%   - invalid limit fails closed with stable error ID
%   - no external solver
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
dev_gfl = ibr.dual_mode_ibr_model('IBR_test',2,2,bus_ids,Vbus,struct(),P_ref,Q_ref,V_ref,"gfl");
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
testCase.verifyEqual(numel(x_right), 20, 'AbsTol',0, '20-state dimension');
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
dev_gfm = ibr.dual_mode_ibr_model('IBR_test',2,2,bus_ids,Vbus,struct(),P_ref,0.0,V_ref,"GFM");
% Build exact GFM equilibrium that delivers P_ref, Q_ref (Q from S, not Q_ref input)
% For GFM, equilibrium_initialize expects terminal P/Q, and checks |V|==V_ref.
x_left = get_exact_equil(dev_gfm, Vbus, P_ref, Q_ref, ec_gfm);
I_left = dev_gfm.current_injection(0, x_left, y, dev_gfm.u0, ec_gfm);
S_left = Vbus*conj(I_left);
P_left = real(S_left); Q_left = imag(S_left);
% Transfer to GFL using GFM device's callback (same superset, same bus)
% Use dev_gfm's mode_transfer_state (it has same gfl/gfm devs inside)
x_right = dev_gfm.mode_transfer_state(x_left, y, dev_gfm.u0, ec_gfm, 'gfl', ec_gfl);
testCase.verifyEqual(numel(x_right),20,'AbsTol',0,'dim 20');
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
% Internal relative: delta_IT (angle difference) should be invariant
% gfm_idx: delta_IT is index 2, x_Eint 4, etc. Absolute angles delta_PLL (5) should shift by theta
% Extract
delta_IT = x_gfm(2); delta_IT_rot = x_gfm_rot(2);
testCase.verifyEqual(delta_IT, delta_IT_rot, 'AbsTol',1e-9, 'delta_IT invariant under global rotation');
% P_f, Q_f etc (indices 7,9) should be same (inverter base) because P/Q same
testCase.verifyEqual(x_gfm(7), x_gfm_rot(7), 'AbsTol',1e-9, 'Pinv_f invariant');
testCase.verifyEqual(x_gfm(9), x_gfm_rot(9), 'AbsTol',1e-9, 'Qinv_f invariant');
% Absolute angle delta_PLL should rotate by theta
delta_PLL = x_gfm(5); delta_PLL_rot = x_gfm_rot(5);
% Wrap difference
diff = wrapToPi(delta_PLL_rot - delta_PLL);
testCase.verifyEqual(diff, theta, 'AbsTol',1e-8, 'delta_PLL rotates by theta');
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
% Save GFM inactive branch (1:13) from left
gfm_idx = 1:13; gfl_idx = 14:20;
gfm_anchor_left = x_left(gfm_idx);
x_right = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
% After GFL->GFM, GFL branch should be preserved
testCase.verifyEqual(x_right(gfl_idx), x_left(gfl_idx), 'AbsTol',0, 'GFL->GFM preserves GFL anchor (inactive)');
% Check opposite: GFM->GFL preserves GFM anchor
[dev2, y2, u2, ec_gfl2, ec_gfm2, Vbus2, ~,~,~, bus_ids] = dual_fixture_gfl(0.4,0.05,1.0,1.0+0i);
dev_gfm = ibr.dual_mode_ibr_model('IBR_test',2,2,bus_ids,Vbus2,struct(),0.4,0.0,1.0,"GFM");
x_left_gfm = get_exact_equil(dev_gfm, Vbus2, 0.4, 0.05, ec_gfm2);
gfl_anchor_left = x_left_gfm(gfl_idx);
x_right_gfl = dev_gfm.mode_transfer_state(x_left_gfm, y2, dev_gfm.u0, ec_gfm2, 'gfl', ec_gfl2);
testCase.verifyEqual(x_right_gfl(gfm_idx), x_left_gfm(gfm_idx), 'AbsTol',0, 'GFM->GFL preserves GFM anchor');
end

% =========================================================================
% 6. Dimension 20 constant
% =========================================================================
function test_dimension_20(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl();
x_left = get_exact_equil(dev, Vbus, 0.4, 0.1, ec_gfl);
x_r1 = dev.mode_transfer_state(x_left, y, u, ec_gfl, 'GFM', ec_gfm);
x_r2 = dev.mode_transfer_state(x_r1, y, u, ec_gfm, 'gfl', ec_gfl);
testCase.verifyEqual(numel(x_left),20,'AbsTol',0);
testCase.verifyEqual(numel(x_r1),20,'AbsTol',0);
testCase.verifyEqual(numel(x_r2),20,'AbsTol',0);
end

% =========================================================================
% 7. Invalid limit fails closed with stable error ID
% =========================================================================
function test_invalid_limits_fail_closed(testCase)
[dev, y, u, ec_gfl, ec_gfm, Vbus] = dual_fixture_gfl(0.4,0.1,1.0,1.0+0i);
x_left = get_exact_equil(dev, Vbus, 0.4, 0.1, ec_gfl);

% a) V zero
y_zero = y; y_zero(3)=0; y_zero(4)=0;
errored=false;
try
    dev.mode_transfer_state(x_left, y_zero, u, ec_gfl, 'GFM', ec_gfm);
catch me
    errored=true;
    testCase.verifyTrue(contains(me.identifier,'badVoltage') || contains(me.identifier,'transfer_maps'), 'V zero fails closed badVoltage');
end
testCase.verifyTrue(errored,'V zero must fail closed');

% b) V non-finite
y_nan = y; y_nan(3)=NaN;
errored=false;
try
    dev.mode_transfer_state(x_left, y_nan, u, ec_gfl, 'GFM', ec_gfm);
catch me
    errored=true;
    testCase.verifyTrue(contains(me.identifier,'badVoltage') || contains(me.identifier,'transfer_maps') || contains(me.identifier,'badNetworkState'), 'V non-finite fails');
end
testCase.verifyTrue(errored,'V non-finite must fail closed');

% c) P beyond Imax (WECC Imax=1.0 default, request 2.0 pu)
V_ok = 1.0+0i;
P_big = 2.0; Q_big = 0.0;
x_big = get_exact_equil(dev, V_ok, 0.4, 0.1, ec_gfl); % valid left
% Try to transfer with P_left huge? Actually our transfer computes P_left from I_left, so to force limit violation we need to craft x_left that produces huge I, then target initializer will reject.
% Instead directly test target initializer limit: GFL initializer with P_big should error
errored=false;
try
    dev.equilibrium_initialize(V_ok, P_big, Q_big, ec_gfl);
catch me
    errored=true;
    testCase.verifyTrue(contains(me.identifier,'CurrentLimit') || contains(me.identifier,'PowerLimit') || contains(me.identifier,'equilibrium'), ['Limit error ID stable: ' me.identifier]);
end
testCase.verifyTrue(errored,'P beyond Imax should fail closed via initializer');

% d) GFM V below VPLLfrz (0.05 pu) should fail via equilibriumPLLFreezeNonunique
V_low = 0.04+0i;
% Construct device at normal voltage (so constructor succeeds), then init at low V
[dev_low, ~, ~, ec_gfl_low, ec_gfm_low, ~] = dual_fixture_gfl(0.1,0.0,1.0,1.0+0i);
% V_ref is 1.0, but |V|=0.04 < VPLLfrz -> GFM initializer should error
errored=false;
try
    dev_low.equilibrium_initialize(V_low, 0.1, 0.0, ec_gfm_low);
catch me
    errored=true;
    testCase.verifyTrue(contains(me.identifier,'PLLFreeze') || contains(me.identifier,'equilibrium'), 'V low PLL freeze fails closed');
end
testCase.verifyTrue(errored,'V below VPLLfrz must fail closed');

% e) V_ref mismatch for GFM: |Vbus| != V_ref should error equilibriumVoltageReferenceMismatch
V_mismatch = 0.9+0i;
y_mis = [1.06;0; real(V_mismatch); imag(V_mismatch)];
errored=false;
try
    % dev has V_ref=1.0, Vbus=0.9 -> mismatch
    dev.equilibrium_initialize(V_mismatch, 0.4, 0.1, ec_gfm);
catch me
    errored=true;
    testCase.verifyTrue(contains(me.identifier,'VoltageReferenceMismatch') || contains(me.identifier,'equilibrium'), 'V_ref mismatch fails closed');
end
testCase.verifyTrue(errored,'V_ref mismatch must fail closed');

% f) Unsupported mode
errored=false;
try
    dev.mode_transfer_state(x_left, y, u, ec_gfl, 'invalid_mode', ec_gfm);
catch me
    errored=true;
    testCase.verifyTrue(contains(me.identifier,'unsupportedMode'), 'unsupported mode fails closed');
end
testCase.verifyTrue(errored,'Invalid mode must fail closed');
end

% =========================================================================
% 8. No external solver (grep guard)
% =========================================================================
function test_no_external_solver(testCase)
src1 = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr','dual_mode_ibr_model.m'));
src2 = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), '+stability','transfer_maps.m'));
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src1, fn{1}), ['no ' fn{1} ' in dual_mode_ibr_model']);
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
