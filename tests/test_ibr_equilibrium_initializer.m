function tests = test_ibr_equilibrium_initializer()
%TEST_IBR_EQUILIBRIUM_INITIALIZER  Exact device-equilibrium inversion tests.
%   These tests independently reconstruct terminal current/internal voltage
%   from S=V*conj(I), then falsify the GFL and dual-mode initializer API.
%   The initializer is device-local: passing f=0 is not a network-KCL claim.
%
%   Retired-family coverage removed 2026-09-26: the three REGFM_B1 G2 tests
%   and the two retired-20-state-dual tests pinned a 13-state GFM and a
%   20-state WECC/GFM superset that no longer exist.  The surviving
%   eecon49_dual family inherits the dual-mode mode-dispatch, tripped and
%   fail-closed coverage below.  The standalone WECC GFL dispatcher tests
%   (ibr.gfl_model / ibr.wecc_regca_reeca_model) were removed 2026-10-08 with
%   the dispatcher itself: no production path called it, and the surviving
%   SMIB grid-following model (ibr.gfl_rms10_model) is reached directly.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function test_dual_runtime_mode_shared_by_all_closures(testCase)
% Ported from the retired 20-state dual family onto the surviving
% eecon49_dual family (2026-09-26).  The PROPERTY under test is unchanged and
% is the point of the test: the constructor records a static GFL partition, and
% every closure (equilibrium_initialize, f, electrical_power,
% current_injection, reconstruct) must re-resolve the mode from the runtime
% hybrid state instead of using the constructor's.  Only the indices move,
% because the superset is 16 states here (GFL 4:9, GFM 10:16) rather than the
% retired 20 (GFL 14:20, GFM 1:13).
%
% Independent oracle: the branch factories ibr.gfl_eecon49_full_model and
% ibr.gfm_eecon49_full_model, called directly on the sliced state, which the
% dual wrapper must assemble without perturbing a bit.  (A retired test used a
% standalone leaf for this; that leaf is gone as of 2026-10-08.)
V = 1.02*exp(1i*0.12); P = 0.40; Q = 0.10;
ids = [1 2];
params = struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10));
dual = ibr.eecon49_dual_mode_model('IBR2',2,2,ids,V,params, ...
    P,Q,abs(V),'gfl');
y = bus_y(V,2,2);
u = [P;Q;abs(V)];
% Constructor mode is gfl, so the static partition is the GFL branch.
testCase.verifyEqual(dual.active_state_indices,1:9, ...
    'AbsTol',0,'Static compatibility metadata reflects constructor GFL mode.');

% Constructor says gfl, runtime hybrid state says GFM.
ec_gfm = mode_context('IBR2','GFM');
testCase.verifyEqual(dual.active_state_indices_for_context(ec_gfm),[1:3 10:16], ...
    'AbsTol',0,'Runtime GFM partition comes from the device-owned resolver.');
x_gfm = dual.equilibrium_initialize(V,P,Q,ec_gfm);
gfm_branch = ibr.gfm_eecon49_full_model('IBR2',2,2,ids,V,params,P,Q);
xgfm_expected = gfm_branch.equilibrium_initialize(V,P,Q,ec_gfm);
% GFM block is [plant 1:3, controller 10:16]; the GFL block 4:9 is frozen.
gfm_idx = [1:3 10:16];
testCase.verifyEqual(x_gfm(gfm_idx), xgfm_expected, 'AbsTol', 1e-12);
testCase.verifyEqual(x_gfm(4:9), dual.x0(4:9), 'AbsTol', 0, ...
    'The inactive GFL block must stay at its warm-start anchor.');
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
    1:9,'AbsTol',0);
x_gfl = dual.equilibrium_initialize(V,P,Q,ec_gfl);
gfl_branch = ibr.gfl_eecon49_full_model('IBR2',2,2,ids,V,params,P,Q);
xgfl_expected = gfl_branch.equilibrium_initialize(V,P,Q,ec_gfl);
% The branch factory publishes 10 coordinates: the 9 GFL states plus a
% trailing algebraic DC-source placeholder (state_names{10}='z_pad') that the
% dual superset does not carry, because in the dual the DC source is shared
% across both branches.  The dual's GFL block is therefore the branch's first 9.
gfl_idx = 1:9;
testCase.verifyEqual(gfl_branch.state_names(10),{'z_pad'}, ...
    'The branch oracle must still expose exactly one trailing pad state.');
testCase.verifyEqual(x_gfl(gfl_idx),xgfl_expected(gfl_idx),'AbsTol',1e-12);
testCase.verifyLessThan(norm(dual.f(0,x_gfl,y,u,ec_gfl),inf),1e-12);
testCase.verifyEqual(V*conj(dual.current_injection(0,x_gfl,y,u,ec_gfl)), ...
    P+1i*Q,'AbsTol',1e-12);
r_gfl = dual.reconstruct(0,x_gfl,y,u,ec_gfl);
testCase.verifyEqual(r_gfl.mode,'gfl');
testCase.verifyTrue(isfield(r_gfl,'gfl'));
testCase.verifyFalse(isfield(r_gfl,'gfm'));

testCase.verifyEqual(dual.nx,16,'AbsTol',0, ...
    ['16 published coordinates: the fixture passes dc_source without ' ...
     'source_state, so the Thevenin current stays algebraic and no 17th ' ...
     'state is appended.']);
end

% =========================================================================
function test_dual_tripped_and_invalid_runtime_modes_fail_closed(testCase)
% Ported onto eecon49_dual (2026-09-26); the retired family's identifiers are
% replaced by this family's, which are the ones the code actually throws.
V = 1+0i;
dev = ibr.eecon49_dual_mode_model('IBR2',2,2,[1 2],V,struct(),0.4,0,1,'gfl');
y = bus_y(V,2,2); u = [0.4;0;1];
ec_trip = mode_context('IBR2','tripped');
testCase.verifyEmpty(dev.active_state_indices_for_context(ec_trip));
x = dev.equilibrium_initialize(V,0,0,ec_trip);
testCase.verifyEqual(dev.current_injection(0,x,y,u,ec_trip),0,'AbsTol',0);
testCase.verifyEqual(dev.electrical_power(0,x,y,u,ec_trip),0,'AbsTol',0);
testCase.verifyTrue(dev.reconstruct(0,x,y,u,ec_trip).tripped);
testCase.verifyError(@() dev.equilibrium_initialize(V,0.1,0,ec_trip), ...
    'ibr:eecon49_dual_mode_model:offlineEquilibriumPower');
ec_bad = mode_context('IBR2','not_a_mode');
testCase.verifyError(@() dev.equilibrium_initialize(V,0,0,ec_bad), ...
    'ibr:eecon49_dual_mode_model:badRuntimeMode');
testCase.verifyError(@() dev.current_injection(0,x,y,u,ec_bad), ...
    'ibr:eecon49_dual_mode_model:badRuntimeMode');
testCase.verifyError(@() dev.active_state_indices_for_context(ec_bad), ...
    'ibr:eecon49_dual_mode_model:badRuntimeMode');
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
% The SG assertion here formerly required sg.equilibrium_initialize to be EMPTY
% ("SG explicitly advertises the optional initializer as unsupported").  That
% stopped being true when stability.sg_composite_device gained a real
% equilibrium_initialize (commit 649e168, "Add mixed-resource PF/SSSA/TS
% comparison products and RMS10 corrections"); the stale claim was left red and
% is corrected here rather than deleted, because the field's PRESENCE is exactly
% what this test is about.  Derivation of the new expectation: the SG publishes
% its own 6-state EMF6 vector from that initializer, so the handle must be real
% and must return one state per sg.nx -- not a stub.
testCase.verifyTrue(isa(sg.equilibrium_initialize,'function_handle'), ...
    'SG advertises a real equilibrium initializer.');
x_sg = sg.equilibrium_initialize(1.04,0.4,0.1,struct());
testCase.verifyEqual(numel(x_sg),sg.nx, ...
    'The SG initializer must return one state per sg.nx.');
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
