function tests = test_ibr_equilibrium_initializer()
%TEST_IBR_EQUILIBRIUM_INITIALIZER  Exact device-equilibrium inversion tests.
%   These tests independently reconstruct terminal current/internal voltage
%   from S=V*conj(I), then falsify the GFL, GFM and dual-mode initializer API.
%   The initializer is device-local: passing f=0 is not a network-KCL claim.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function test_gfm_exact_equilibrium_kappa_one(testCase)
V = 1.03*exp(1i*0.17);
P = 0.60; Q = 0.20;
ids = [1 2];
dev = ibr.regfm_b1_vsg_model('GFM_T', 2, 2, ids, V, ...
    struct('Mbase',100), P, abs(V));
x = dev.equilibrium_initialize(V, P, Q, struct());
y = bus_y(V, 2, 2);
dx = dev.f(0, x, y, [P;abs(V)], struct());
I = dev.current_injection(0, x, y, [P;abs(V)], struct());
S = V*conj(I);

testCase.verifyEqual(numel(x), 13, 'AbsTol', 0);
testCase.verifyLessThan(norm(dx,inf), 1e-10);
testCase.verifyEqual(real(S), P, 'AbsTol', 1e-12);
testCase.verifyEqual(imag(S), Q, 'AbsTol', 1e-12);
testCase.verifyEqual(x(7), P, 'AbsTol', 1e-12);   % kappa=1
testCase.verifyEqual(x(9), Q, 'AbsTol', 1e-12);
testCase.verifyEqual(x(10), abs(V), 'AbsTol', 1e-12);
testCase.verifyFalse(dev.reconstruct(0,x,y,[P;abs(V)],struct()).I_limited);
end

% =========================================================================
function test_gfm_exact_equilibrium_kappa_not_one(testCase)
% Independent system/inverter-base oracle for IBR2 (Mbase=140 MVA).
V = 1.045*exp(-1i*0.0869625858016);
P = 1.097; Q = 0.435571;
kappa = 100/140;
Zsys = kappa*(1i*0.1);
Iref = conj((P + 1i*Q)/V);
Eref = V + Zsys*Iref;
Idq = Iref*exp(-1i*angle(V));
xE = (abs(Eref) - abs(V) + 0.05*kappa*Q)/5.0;
delta_max = asin(0.1);
expected = [0; wrap_pi(angle(Eref)-angle(V)); 0; xE; angle(V); 0; ...
    kappa*P; kappa*real(Idq); kappa*Q; abs(V); kappa*imag(Idq); ...
    delta_max; -delta_max];

dev = ibr.regfm_b1_vsg_model('IBR2', 2, 2, [1 2], V, ...
    struct('Mbase',140), P, abs(V));
x = dev.equilibrium_initialize(V, P, Q, struct());
y = bus_y(V, 2, 2);
testCase.verifyEqual(x, expected, 'AbsTol', 2e-12);
testCase.verifyLessThan(norm(dev.f(0,x,y,[P;abs(V)],struct()),inf), 1e-10);
I = dev.current_injection(0,x,y,[P;abs(V)],struct());
testCase.verifyEqual(I, Iref, 'AbsTol', 2e-12);
testCase.verifyLessThan(x(11), 0, 'Positive Q must give negative Iq at PLL lock.');
end

% =========================================================================
function test_gfm_initializer_fails_closed(testCase)
ids = [1 2]; V = 1+0i;
dev = ibr.regfm_b1_vsg_model('GFM_T',2,2,ids,V,struct(),0.4,1.0);

testCase.verifyError(@() dev.equilibrium_initialize(0,0.4,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumBadVoltage');
testCase.verifyError(@() dev.equilibrium_initialize(NaN,0.4,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumBadVoltage');
testCase.verifyError(@() dev.equilibrium_initialize(V,NaN,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumBadPower');
testCase.verifyError(@() dev.equilibrium_initialize(0.03,0.01,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumPLLFreezeNonunique');
testCase.verifyError(@() dev.equilibrium_initialize(0.99,0.4,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumVoltageReferenceMismatch');
% kappa=1 and |V|=1: P=1.5 is exactly the sourced ImaxF boundary.
testCase.verifyError(@() dev.equilibrium_initialize(V,1.5,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumClampBoundary');
testCase.verifyError(@() dev.equilibrium_initialize(V,1.6,0,struct()), ...
    'ibr:regfm_b1_vsg_model:equilibriumCurrentLimit');
end

% =========================================================================
function test_gfl_exact_equilibrium_and_rotation(testCase)
V = 1.02*exp(1i*0.20); P = 0.40; Q = 0.10;
dev = ibr.gfl_model('GFL_T',2,2,[1 2],V,struct(),P,Q);
x = dev.equilibrium_initialize(V,P,Q,struct());
y = bus_y(V,2,2);
testCase.verifyLessThan(norm(dev.f(0,x,y,[P;Q],struct()),inf), 1e-12);
I = dev.current_injection(0,x,y,[P;Q],struct());
testCase.verifyEqual(V*conj(I), P+1i*Q, 'AbsTol', 1e-12);

alpha = -0.37;
Vr = V*exp(1i*alpha);
xr = dev.equilibrium_initialize(Vr,P,Q,struct());
yr = bus_y(Vr,2,2);
Ir = dev.current_injection(0,xr,yr,[P;Q],struct());
testCase.verifyLessThan(norm(dev.f(0,xr,yr,[P;Q],struct()),inf), 1e-12);
testCase.verifyEqual(Ir, I*exp(1i*alpha), 'AbsTol', 1e-12);
testCase.verifyEqual(xr,x,'AbsTol',1e-12, ...
    'WECC REGC_A/REEC_A states are rotationally invariant (no PLL state).');
end

% =========================================================================
function test_gfl_initializer_fails_closed(testCase)
dev = ibr.gfl_model('GFL_T',2,2,[1 2],1+0i,struct(),0.4,0.0);
testCase.verifyError(@() dev.equilibrium_initialize(0,0.4,0,struct()), ...
    'ibr:wecc_regca_reeca_model:equilibriumInput');
testCase.verifyError(@() dev.equilibrium_initialize(1,Inf,0,struct()), ...
    'ibr:wecc_regca_reeca_model:equilibriumInput');
end

% =========================================================================
function test_dual_runtime_mode_shared_by_all_closures(testCase)
V = 1.02*exp(1i*0.12); P = 0.40; Q = 0.10;
ids = [1 2];
dual = ibr.dual_mode_ibr_model('IBR2',2,2,ids,V,struct('Mbase',140), ...
    P,Q,abs(V),'gfl');
y = bus_y(V,2,2);
u = [P;Q;abs(V)];
testCase.verifyEqual(dual.active_state_indices,14:20, ...
    'AbsTol',0,'Static compatibility metadata reflects constructor GFL mode.');

% Constructor says gfl, runtime hybrid state says GFM.
ec_gfm = mode_context('IBR2','GFM');
testCase.verifyEqual(dual.active_state_indices_for_context(ec_gfm),1:13, ...
    'AbsTol',0,'Runtime GFM partition comes from the device-owned resolver.');
x_gfm = dual.equilibrium_initialize(V,P,Q,ec_gfm);
standalone_gfm = ibr.regfm_b1_vsg_model('IBR2',2,2,ids,V, ...
    struct('Mbase',140),P,abs(V));
xgfm_expected = standalone_gfm.equilibrium_initialize(V,P,Q,ec_gfm);
gfm_idx = 1:13;
testCase.verifyEqual(x_gfm(gfm_idx), xgfm_expected, 'AbsTol', 1e-12);
testCase.verifyLessThan(norm(dual.f(0,x_gfm,y,u,ec_gfm),inf), 1e-10);
testCase.verifyEqual(dual.electrical_power(0,x_gfm,y,u,ec_gfm),P,'AbsTol',1e-12);
testCase.verifyEqual(V*conj(dual.current_injection(0,x_gfm,y,u,ec_gfm)), ...
    P+1i*Q,'AbsTol',1e-12);
r_gfm = dual.reconstruct(0,x_gfm,y,u,ec_gfm);
testCase.verifyEqual(r_gfm.mode,'GFM');
testCase.verifyTrue(isfield(r_gfm,'gfm'));
testCase.verifyFalse(isfield(r_gfm,'gfl'));

% Runtime GFL dispatch uses the same mode resolution in every closure.
ec_gfl = mode_context('IBR2','gfl');
testCase.verifyEqual(dual.active_state_indices_for_context(ec_gfl), ...
    14:20,'AbsTol',0);
x_gfl = dual.equilibrium_initialize(V,P,Q,ec_gfl);
standalone_gfl = ibr.gfl_model('IBR2',2,2,ids,V,struct('Mbase',140),P,Q);
xgfl_expected = standalone_gfl.equilibrium_initialize(V,P,Q,ec_gfl);
gfl_idx = 14:20;
testCase.verifyEqual(x_gfl(gfl_idx),xgfl_expected,'AbsTol',1e-12);
testCase.verifyLessThan(norm(dual.f(0,x_gfl,y,u,ec_gfl),inf),1e-12);
testCase.verifyEqual(V*conj(dual.current_injection(0,x_gfl,y,u,ec_gfl)), ...
    P+1i*Q,'AbsTol',1e-12);
r_gfl = dual.reconstruct(0,x_gfl,y,u,ec_gfl);
testCase.verifyEqual(r_gfl.mode,'gfl');
testCase.verifyTrue(isfield(r_gfl,'gfl'));
testCase.verifyFalse(isfield(r_gfl,'gfm'));

testCase.verifyEqual(dual.nx,20,'AbsTol',0);
end

% =========================================================================
function test_dual_tripped_and_invalid_runtime_modes_fail_closed(testCase)
V = 1+0i;
dev = ibr.dual_mode_ibr_model('IBR2',2,2,[1 2],V,struct(),0.4,0,1,'gfl');
y = bus_y(V,2,2); u = [0.4;0;1];
ec_trip = mode_context('IBR2','tripped');
testCase.verifyEmpty(dev.active_state_indices_for_context(ec_trip));
x = dev.equilibrium_initialize(V,0,0,ec_trip);
testCase.verifyEqual(dev.current_injection(0,x,y,u,ec_trip),0,'AbsTol',0);
testCase.verifyEqual(dev.electrical_power(0,x,y,u,ec_trip),0,'AbsTol',0);
testCase.verifyTrue(dev.reconstruct(0,x,y,u,ec_trip).tripped);
testCase.verifyError(@() dev.equilibrium_initialize(V,0.1,0,ec_trip), ...
    'ibr:dual_mode_ibr_model:trippedEquilibriumPower');
ec_bad = mode_context('IBR2','not_a_mode');
testCase.verifyError(@() dev.equilibrium_initialize(V,0,0,ec_bad), ...
    'ibr:dual_mode_ibr_model:badRuntimeMode');
testCase.verifyError(@() dev.current_injection(0,x,y,u,ec_bad), ...
    'ibr:dual_mode_ibr_model:badRuntimeMode');
testCase.verifyError(@() dev.active_state_indices_for_context(ec_bad), ...
    'ibr:dual_mode_ibr_model:badRuntimeMode');
end

% =========================================================================
function test_generic_builder_normalizes_optional_initializer(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'});
dispatch = struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
testCase.verifyTrue(all(arrayfun(@(d)isfield(d,'equilibrium_initialize'),devices)));
testCase.verifyTrue(all(arrayfun(@(d)isfield(d,'active_state_indices_for_context'),devices)));
sg = devices(strcmp({devices.device_id},'SG1'));
ibrs = devices(~strcmp({devices.device_id},'SG1'));
testCase.verifyEmpty(sg.equilibrium_initialize, ...
    'SG explicitly advertises the optional initializer as unsupported.');
testCase.verifyEmpty(sg.active_state_indices_for_context, ...
    'Fixed-layout SG explicitly advertises no runtime partition resolver.');
testCase.verifyTrue(all(arrayfun(@(d)isa(d.equilibrium_initialize,'function_handle'),ibrs)));
testCase.verifyTrue(all(arrayfun(@(d)isa(d.active_state_indices_for_context,'function_handle'),ibrs)));
end

% =========================================================================
function y = bus_y(V, bp, nb)
y = zeros(2*nb,1);
y(2*bp-1) = real(V);
y(2*bp) = imag(V);
end

function ec = mode_context(device_id, mode)
key = matlab.lang.makeValidName(device_id,'ReplacementStyle','underscore');
dm = struct(); dm.(key) = mode;
ec = struct('hybrid_state',struct('device_modes',dm));
end

function a = wrap_pi(a)
a = atan2(sin(a),cos(a));
end
