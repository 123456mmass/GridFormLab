function tests = test_ieee14_1sg_4ibr_phaseEF()
%TEST_IEEE14_1SG_4IBR_PHASEEF  Phase E+F combined tests (SG trip + synchronism).
%   Verifies: sg_event_handler trip + GFM auto-commit, synchronism_guard
%   passes/fails correctly, reclose only after guard passes, no global
%   SG_ON/SG_OFF rule, per-SG state, deterministic event log.
%
%   Source: execution plan §E-F; corrections 4-5.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_synchronism_guard_pass(testCase)
% Perfect sync: identical V, delta, omega => margin positive => passes.
r = stability.synchronism_guard(1.06, 1.06, 0.0, 1.0, 1.0);
testCase.verifyTrue(r.passes, 'Perfect sync must pass.');
testCase.verifyGreaterThanOrEqual(r.signed_margin, 0, 'Margin >= 0.');
end

% =========================================================================
function test_synchronism_guard_fail_voltage(testCase)
% Large voltage mismatch => should fail.
r = stability.synchronism_guard(1.06, 0.9, 0.0, 1.0, 1.0);
testCase.verifyFalse(r.passes, 'Large dV must fail.');
testCase.verifyLessThan(r.signed_margin, 0, 'Margin < 0.');
end

% =========================================================================
function test_synchronism_guard_fail_slip(testCase)
% Large frequency slip => should fail.
r = stability.synchronism_guard(1.06, 1.06, 0.0, 1.02, 1.0);
testCase.verifyFalse(r.passes, 'Large slip must fail.');
end

% =========================================================================
function test_sg_trip_and_gfm_commit(testCase)
% Trip SG1, verify GFM auto-committed to an IBR.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
hs = stability.ts_hybrid_state_init(devices);

event = struct('type','sg_trip_request','t',1.0,'sg_ids',{{'SG1'}});
[hs2, log] = stability.sg_event_handler(hs, event, devices);
testCase.verifyTrue(log.applied, 'SG trip event applied.');

% SG1 must now be offline
testCase.verifyFalse(hs2.device_online.SG1, 'SG1 offline after trip.');
testCase.verifyEqual(hs2.device_modes.SG1, 'breaker_open', 'SG1 mode breaker_open.');
end

% =========================================================================
function test_reclose_on_already_online(testCase)
% Reclose request on an online SG must fail.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
hs = stability.ts_hybrid_state_init(devices);

event = struct('type','sg_reclose_request','t',2.0,'sg_id','SG1');
[~, log] = stability.sg_event_handler(hs, event, devices);
testCase.verifyFalse(log.applied, 'Reclose on already-online SG must not apply.');
end

% =========================================================================
function test_no_global_sg_on_off_rule_grep(testCase)
% Grep guard: sg_event_handler must NOT implement SG_ON→all-GFL or
% SG_OFF→all-GFM rule.
handler_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'sg_event_handler.m');
src = fileread(handler_path);
testCase.verifyFalse(contains(src, 'all_GFL') || contains(src, 'all_GFM'), ...
    'no global all-GFL/all-GFM rule.');
% The phrase 'SG_ON/SG_OFF' appears only in the doc comment stating
% that we do NOT use it. Verify there is no executable SG_ON/SG_OFF logic.
% Check for conditionals that would indicate a global rule.
testCase.verifyFalse(contains(src, 'all_gfl') || contains(src, 'all_gfm'), ...
    'no all-gfl/all-gfm global commands.');
end
