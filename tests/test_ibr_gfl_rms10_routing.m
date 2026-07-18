function tests = test_ibr_gfl_rms10_routing
%TEST_IBR_GFL_RMS10_ROUTING  Integration tests for GFL family routing.
%   Verifies the gfl_model dispatcher routes by params.gfl_family, that the
%   WECC default is unchanged when no family is given, and that unknown
%   families fail closed. Also verifies the dual-mode constructor produces
%   the correct distinct device_type for each family.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
testCase.addTeardown(@() rmpath(root));
end

function test_default_family_is_wecc(testCase)
d = ibr.gfl_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
testCase.verifyEqual(d.device_type,'ibr_gfl_wecc_regca_reeca');
testCase.verifyEqual(d.nx,7);
end

function test_explicit_wecc_family(testCase)
d = ibr.gfl_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','wecc_regca_reeca'),0.4,0.0);
testCase.verifyEqual(d.device_type,'ibr_gfl_wecc_regca_reeca');
testCase.verifyEqual(d.nx,7);
end

function test_rms10_family_routes_to_rms10(testCase)
d = ibr.gfl_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0);
testCase.verifyEqual(d.device_type,'ibr_gfl_rms10');
testCase.verifyEqual(d.nx,10);
testCase.verifyEqual(d.state_names, ...
    {'delta_PLL','xi_PLL','P_f','Q_f','xi_P','xi_Q','xi_id','xi_iq','i_d','i_q'});
end

function test_unknown_family_fails_closed(testCase)
testCase.verifyError(@() ibr.gfl_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','bogus'),0.4,0.0), ...
    'ibr:gfl_model:unknownFamily');
end

function test_case_insensitive_family(testCase)
d = ibr.gfl_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','RMS10'),0.4,0.0);
testCase.verifyEqual(d.device_type,'ibr_gfl_rms10');
end

function test_wecc_default_equivalent_to_explicit(testCase)
d1 = ibr.gfl_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.1);
d2 = ibr.gfl_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','wecc_regca_reeca'),0.4,0.1);
testCase.verifyEqual(d1.device_type,d2.device_type);
testCase.verifyEqual(d1.nx,d2.nx);
testCase.verifyEqual(d1.x0,d2.x0,'AbsTol',0);
end

function test_dual_wecc_default_device_type(testCase)
d = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0,struct(), ...
    0.4,0.0,1.0,'gfl');
testCase.verifyEqual(d.device_type,'ibr_dual_mode');
testCase.verifyEqual(d.nx,20);
end

function test_dual_rms10_device_type(testCase)
d = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0,1.0,'gfl');
testCase.verifyEqual(d.device_type,'ibr_dual_mode_rms10');
testCase.verifyEqual(d.nx,23);
% GFM branch 1:13 unchanged; GFL-RMS10 branch 14:23 has delta_PLL first.
testCase.verifyEqual(d.state_names{14},'gfl_delta_PLL');
testCase.verifyEqual(d.state_names{23},'gfl_i_q');
end

function test_dual_unknown_family_fails_closed(testCase)
testCase.verifyError(@() ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','bogus'),0.4,0.0,1.0,'gfl'), ...
    'ibr:dual_mode_ibr_model:unknownFamily');
end

function test_dual_rms10_gfm_branch_unchanged(testCase)
% GFM states 1:13 must be identical between WECC-dual and RMS10-dual.
d_wecc = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0,1.0,'gfl');
d_rms10 = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0,1.0,'gfl');
testCase.verifyEqual(d_wecc.state_names(1:13), d_rms10.state_names(1:13));
testCase.verifyEqual(d_wecc.x0(1:13), d_rms10.x0(1:13),'AbsTol',0);
end
