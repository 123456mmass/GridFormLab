function tests = test_ibr_gfl_rms10_dual
%TEST_IBR_GFL_RMS10_DUAL  23-state dual-mode integration tests (GFM+RMS10).
%   Verifies the RMS10 dual device: state layout (13 GFM + 10 RMS10), active
%   state partition by mode, current_injection/Pe/reconstruct dispatch to the
%   correct branch, equilibrium_initialize maps to the active branch, and the
%   GFM branch is unchanged from the legacy dual-mode contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
testCase.addTeardown(@() rmpath(root));
end

function d = make_rms10_dual(mode)
if nargin < 1, mode = 'gfl'; end
% bus_position=3 means V is read from y(5:6); construct at V=1.0+0j.
d = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0,1.0,mode);
end

function y = y_for(V)
% bus_position=3 -> y(2*3-1:2*3) = y(5:6).
y = zeros(6,1);
y(5) = real(V);
y(6) = imag(V);
end

function test_nx_and_layout(testCase)
d = make_rms10_dual();
testCase.verifyEqual(d.nx,23);
testCase.verifyEqual(d.nu,3);
testCase.verifyEqual(numel(d.state_names),23);
% GFM branch 1:13.
testCase.verifyEqual(d.state_names{1},'gfm_omega_m');
testCase.verifyEqual(d.state_names{13},'gfm_delta_ITmin');
% RMS10 branch 14:23.
testCase.verifyEqual(d.state_names{14},'gfl_delta_PLL');
testCase.verifyEqual(d.state_names{23},'gfl_i_q');
end

function test_active_state_indices_gfl_mode(testCase)
d = make_rms10_dual('gfl');
idx = d.active_state_indices_for_context(struct());
% GFL branch = 14:23 (10 states).
testCase.verifyEqual(sort(idx(:)'),14:23);
end

function test_active_state_indices_gfm_mode(testCase)
d = make_rms10_dual('GFM');
idx = d.active_state_indices_for_context(struct());
testCase.verifyEqual(sort(idx(:)'),1:13);
end

function test_active_state_indices_tripped_empty(testCase)
d = make_rms10_dual('tripped');
idx = d.active_state_indices_for_context(struct());
testCase.verifyTrue(isempty(idx));
end

function test_gfl_mode_current_injection_matches_standalone(testCase)
% In gfl mode, the dual current_injection must equal the standalone RMS10
% device's current_injection on the same (slice) state and inputs.
d_dual = make_rms10_dual('gfl');
d_rms10 = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0);
V = 1.0; y = y_for(V);
xeq_rms10 = d_rms10.equilibrium_initialize(V,0.4,0.0,struct());
% Embed the RMS10 equilibrium into the dual superset's GFL slice.
x_dual = d_dual.x0;
x_dual(14:23) = xeq_rms10;
I_dual = d_dual.current_injection(0,x_dual,y,[0.4;0.0;1.0],struct());
I_rms10 = d_rms10.current_injection(0,xeq_rms10,y,[0.4;0.0],struct());
testCase.verifyEqual(I_dual,I_rms10,'AbsTol',1e-12);
end

function test_gfl_mode_pe_matches_standalone(testCase)
d_dual = make_rms10_dual('gfl');
d_rms10 = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0);
V = 1.0; y = y_for(V);
xeq_rms10 = d_rms10.equilibrium_initialize(V,0.4,0.0,struct());
x_dual = d_dual.x0;
x_dual(14:23) = xeq_rms10;
Pe_dual = d_dual.electrical_power(0,x_dual,y,[0.4;0.0;1.0],struct());
Pe_rms10 = d_rms10.electrical_power(0,xeq_rms10,y,[0.4;0.0],struct());
testCase.verifyEqual(Pe_dual,Pe_rms10,'AbsTol',1e-12);
end

function test_gfl_mode_rhs_matches_standalone_slice(testCase)
d_dual = make_rms10_dual('gfl');
d_rms10 = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0);
V = 1.0; y = y_for(V);
xeq_rms10 = d_rms10.equilibrium_initialize(V,0.4,0.0,struct());
x_dual = d_dual.x0;
x_dual(14:23) = xeq_rms10;
dx_dual = d_dual.f(0,x_dual,y,[0.4;0.0;1.0],struct());
dx_rms10 = d_rms10.f(0,xeq_rms10,y,[0.4;0.0],struct());
% GFL slice (14:23) of dual RHS must match standalone RMS10 RHS.
testCase.verifyEqual(dx_dual(14:23),dx_rms10,'AbsTol',1e-12);
% GFM branch (1:13) must be held at zero (inactive in gfl mode).
testCase.verifyEqual(dx_dual(1:13),zeros(13,1),'AbsTol',0);
end

function test_tripped_mode_zero_injection(testCase)
d = make_rms10_dual('tripped');
V = 1.0; y = y_for(V);
I = d.current_injection(0,d.x0,y,[0.4;0.0;1.0],struct());
testCase.verifyEqual(I,0,'AbsTol',0);
Pe = d.electrical_power(0,d.x0,y,[0.4;0.0;1.0],struct());
testCase.verifyEqual(Pe,0,'AbsTol',0);
end

function test_equilibrium_initialize_gfl_branch(testCase)
d = make_rms10_dual('gfl');
V = 1.0; y = y_for(V);
xeq = d.equilibrium_initialize(V,0.4,0.0,struct());
% GFL slice must be a valid RMS10 equilibrium.
d_rms10 = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0);
xeq_rms10 = d_rms10.equilibrium_initialize(V,0.4,0.0,struct());
testCase.verifyEqual(xeq(14:23),xeq_rms10,'AbsTol',1e-12);
end

function test_gfm_branch_identical_to_legacy_dual(testCase)
% G16: GFM branch (1:13) of RMS10-dual must equal the legacy WECC-dual GFM
% branch exactly (REGFM_B1 unchanged).
d_rms10 = make_rms10_dual('GFM');
d_wecc = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0,1.0,'GFM');
testCase.verifyEqual(d_rms10.state_names(1:13), d_wecc.state_names(1:13));
testCase.verifyEqual(d_rms10.x0(1:13), d_wecc.x0(1:13),'AbsTol',0);
end
