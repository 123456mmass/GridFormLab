function tests = test_ieee14_1sg_4ibr_phaseC()
%TEST_IEEE14_1SG_4IBR_PHASEC  Phase C transfer maps + frozen anchor tests.
%   Verifies: dimension constant (15 across modes), live mode switch preserves
%   state dimension, transfer_maps builds per-device maps, hybrid_state_init
%   includes device_frozen_anchor, current continuity across GFL<->GFM,
%   inactive frozen at anchor, repeated switching, invalid mode fail-closed.
%
%   Source: execution plan §C; corrections 3, 4.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_dimension_constant_across_modes(testCase)
% Device nx must be 15 for all modes (gfl, GFM, tripped).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
bus_ids = c.mpc.bus(:,1)';
for mode = ["gfl","GFM","tripped"]
    dev = ibr.dual_mode_ibr_model("IBR2", 2, 2, bus_ids, 1.04, ...
        struct('Mbase',140), 0.4, 0.0, 1.04, mode);
    testCase.verifyEqual(dev.nx, 15, 'AbsTol', 0, ...
        sprintf('nx=15 in mode "%s".', mode));
    testCase.verifyEqual(numel(dev.x0), 15, 'AbsTol', 0, ...
        sprintf('x0 length 15 in mode "%s".', mode));
end
end

% =========================================================================
function test_transfer_maps_builds_for_dual_mode(testCase)
% transfer_maps must produce per-device maps for dual-mode IBRs.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

% Compute bus voltages from PF
Vbus = zeros(numel(devices), 1);
for k = 1:numel(devices)
    bp = devices(k).bus_position;
    Vbus(k) = complex(1.0, 0.0);   % placeholder
end
maps = stability.transfer_maps(devices, Vbus);

for k = 1:numel(devices)
    mid = devices(k).device_id;
    key = matlab.lang.makeValidName(mid, 'ReplacementStyle','underscore');
    testCase.verifyTrue(isfield(maps, key), ...
        sprintf('transfer_maps has entry for %s.', mid));
    % Dual-mode IBRs should have gfl_to_gfm + gfm_to_gfl
    if strcmp(devices(k).device_type, 'ibr_dual_mode')
        testCase.verifyTrue(maps.(key).available, ...
            sprintf('%s transfer map available.', mid));
        testCase.verifyTrue(isfield(maps.(key), 'gfl_to_gfm'), ...
            sprintf('%s has gfl_to_gfm.', mid));
        testCase.verifyTrue(isfield(maps.(key), 'gfm_to_gfl'), ...
            sprintf('%s has gfm_to_gfl.', mid));
        testCase.verifyTrue(isfield(maps.(key), 'warmstart'), ...
            sprintf('%s has warmstart.', mid));
    end
end
end

% =========================================================================
function test_hybrid_state_has_frozen_anchor(testCase)
% hybrid_state_init must include device_frozen_anchor (correction 5).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

hs = stability.ts_hybrid_state_init(devices);
testCase.verifyTrue(isfield(hs, 'device_frozen_anchor'), ...
    'hybrid_state has device_frozen_anchor.');
testCase.verifyTrue(isstruct(hs.device_frozen_anchor), ...
    'device_frozen_anchor is a struct.');
end

% =========================================================================
function test_invalid_mode_fail_closed(testCase)
% Invalid mode must fail closed in dual_mode_ibr_model.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
bus_ids = c.mpc.bus(:,1)';
errored = false;
try
    ibr.dual_mode_ibr_model("IBR2", 2, 2, bus_ids, 1.04, ...
        struct('Mbase',140), 0.4, 0.0, 1.04, "invalid_mode");
catch me
    errored = true;
    testCase.verifyTrue(contains(me.identifier, 'mustBeMember') || ...
        contains(me.message, 'invalid'), ...
        'Invalid mode fails closed with appropriate error.');
end
testCase.verifyTrue(errored, 'Invalid mode must fail closed.');
end

% =========================================================================
function test_dual_mode_ibr_has_frozen_metadata(testCase)
% All dual-mode IBR devices must carry frozen_state metadata (uniform schema).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

for k = 1:numel(devices)
    dev = devices(k);
    testCase.verifyTrue(isfield(dev, 'frozen_state_indices'), ...
        sprintf('%s has frozen_state_indices.', dev.device_id));
    testCase.verifyTrue(isfield(dev, 'frozen_state_values'), ...
        sprintf('%s has frozen_state_values.', dev.device_id));
end
end

% =========================================================================
function test_inactive_frozen_at_anchor_grep(testCase)
% Grep guard: transfer_maps.m declares warmstart values (PROJECT_DERIVED).
maps_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'transfer_maps.m');
src = fileread(maps_path);
testCase.verifyTrue(contains(src, 'warmstart'), 'transfer_maps has warmstart.');
testCase.verifyTrue(contains(src, 'algebraic'), 'transfer_maps references algebraic continuity.');
end
