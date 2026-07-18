function tests = test_ibr_gfl_rms10_metadata
%TEST_IBR_GFL_RMS10_METADATA  Registry tests for GFL-RMS10 metadata contracts.
%   Verifies device_contract_metadata dispatches ibr_gfl_rms10 (10/2) and
%   ibr_dual_mode_rms10 (23/3) exactly, that the legacy ibr_dual_mode (20/3)
%   contract is unchanged, and that every state/input row carries source,
%   classification, unit, frame, and citation_status.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
testCase.addTeardown(@() rmpath(root));
end

function test_rms10_standalone_metadata_dispatches(testCase)
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
m = ibr.device_contract_metadata(d);
testCase.verifyEqual(m.contract_id,'gfl_rms10');
testCase.verifyEqual(numel(m.state_metadata),10);
testCase.verifyEqual(numel(m.input_metadata),2);
names = {m.state_metadata.state_name};
testCase.verifyEqual(names, ...
    {'delta_PLL','xi_PLL','P_f','Q_f','xi_P','xi_Q','xi_id','xi_iq','i_d','i_q'});
end

function test_rms10_metadata_classifications(testCase)
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
m = ibr.device_contract_metadata(d);
classif = {m.state_metadata.equation_classification};
% 6 SOURCE_DEFINED (delta_PLL, xi_PLL, xi_id, xi_iq, i_d, i_q).
n_source = sum(strcmp(classif,'SOURCE_DEFINED'));
n_derived = sum(strcmp(classif,'PROJECT_DERIVED'));
testCase.verifyEqual(n_source,6);
testCase.verifyEqual(n_derived,4);
end

function test_rms10_metadata_every_row_has_source(testCase)
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
m = ibr.device_contract_metadata(d);
for k = 1:numel(m.state_metadata)
    r = m.state_metadata(k);
    testCase.verifyTrue(~isempty(r.equation_source), ...
        sprintf('state %s missing equation_source', r.state_name));
    testCase.verifyTrue(~isempty(r.unit), ...
        sprintf('state %s missing unit', r.state_name));
    testCase.verifyTrue(~isempty(r.frame), ...
        sprintf('state %s missing frame', r.state_name));
    testCase.verifyTrue(~isempty(r.citation_status), ...
        sprintf('state %s missing citation_status', r.state_name));
    testCase.verifyTrue(~isempty(r.source_doc), ...
        sprintf('state %s missing source_doc', r.state_name));
end
end

function test_dual_rms10_metadata_dispatches(testCase)
d = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0, ...
    struct('gfl_family','rms10'),0.4,0.0,1.0,'gfl');
m = ibr.device_contract_metadata(d);
testCase.verifyEqual(m.contract_id,'dual_mode_ibr_rms10');
testCase.verifyEqual(numel(m.state_metadata),23);
% GFM branch 1:13, GFL-RMS10 branch 14:23.
testCase.verifyEqual(m.state_metadata(1).state_name,'gfm_omega_m');
testCase.verifyEqual(m.state_metadata(14).state_name,'gfl_delta_PLL');
testCase.verifyEqual(m.state_metadata(23).state_name,'gfl_i_q');
end

function test_legacy_dual_metadata_unchanged(testCase)
% G15: legacy WECC-dual contract must still dispatch identically.
d = ibr.dual_mode_ibr_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0,1.0,'gfl');
m = ibr.device_contract_metadata(d);
testCase.verifyEqual(m.contract_id,'dual_mode_ibr');
testCase.verifyEqual(numel(m.state_metadata),20);
testCase.verifyEqual(m.state_metadata(14).state_name,'gfl_Vt_f');
end

function test_wrong_nx_fails_closed(testCase)
% A 10-state device mislabelled as dual-mode must fail closed (no variable nx).
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
d.device_type = 'ibr_dual_mode';  % deliberately wrong type for the nx
d.nx = 10;
testCase.verifyError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_wrong_state_order_fails_closed(testCase)
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
d.state_names = fliplr(d.state_names);  % wrong order
testCase.verifyError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_rms10_input_metadata(testCase)
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
m = ibr.device_contract_metadata(d);
in_names = {m.input_metadata.input_name};
testCase.verifyEqual(in_names,{'P_ref','Q_ref'});
for k = 1:numel(m.input_metadata)
    testCase.verifyTrue(~isempty(m.input_metadata(k).source));
    testCase.verifyTrue(~isempty(m.input_metadata(k).source_doc));
end
end
