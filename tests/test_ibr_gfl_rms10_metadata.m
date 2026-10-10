function tests = test_ibr_gfl_rms10_metadata
%TEST_IBR_GFL_RMS10_METADATA  Registry tests for GFL-RMS10 metadata contracts.
%   Verifies device_contract_metadata dispatches ibr_gfl_rms10 (10/2) exactly
%   and that every state/input row carries source, classification, unit,
%   frame, and citation_status.
%
%   The two former dual-mode registry tests (dual_mode_ibr_rms10 23/3 and the
%   legacy dual_mode_ibr 20/3) were removed on 2026-09-26 with the retired
%   dual-mode family: neither contract is registered any more, so there
%   is nothing for those tests to dispatch.  The surviving eecon49_dual
%   contract has its own registry coverage in test_ibr_eecon49_dual_mode_model.
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
% The retired dual contract is GONE, and its absence must be observable rather
% than silent: a 23/3 device wearing the old dual device_type must now fail
% closed.  This replaces the former positive dispatch assertion, which pinned a
% contract_id ('dual_mode_ibr_rms10') and a 23-row layout that no longer exist.
% The state/input names below are the retired layout's own, so the rejection is
% exercised on a genuinely dual-shaped device rather than a malformed stub.
d = ibr.gfl_rms10_model("IBR3",3,3,[1 2 3],1.0,struct(),0.4,0.0);
d.device_type = 'ibr_dual_mode_rms10';
d.nx = 23;
d.state_names = [strcat('gfm_', ...
    {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL','x_PLL_int', ...
     'Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f','delta_ITmax','delta_ITmin'}), ...
    strcat('gfl_', ...
    {'delta_PLL','xi_PLL','P_f','Q_f','xi_P','xi_Q','xi_id','xi_iq','i_d','i_q'})];
d.input_names = {'P_ref','Q_ref','V_ref'};
d.nu = 3;
testCase.verifyError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
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
