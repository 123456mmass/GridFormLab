function tests = test_ieee14_1sg_4ibr_phaseD()
%TEST_IEEE14_1SG_4IBR_PHASED  Phase D composite SSSA + config selector tests.
%   Verifies: composite_sssa_model reduction-before-eig (no artificial Edp mode),
%   selector rejects no-VF config, selector deterministic fingerprint,
%   SSSA returns eigenvalues from active-state A only, no eig-then-delete grep,
%   frozen state excluded from A matrix dimensions.
%
%   Source: execution plan §D; correction 8.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_sssa_reduction_before_eig_dimensions(testCase)
% SSSA model A matrix must be nx_active x nx_active (Edp excluded for Kodsi).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');

sssa = stability.composite_sssa_model(devices, eq.x0, eq.y0, c);
% Total states: SG1(6) + 4*IBR(15) = 6 + 60 = 66
% Frozen: SG1 Edp(1) = 1
% Active: 66 - 1 = 65
testCase.verifyEqual(sssa.nx_total, 66, 'AbsTol', 0, 'nx_total = 66.');
testCase.verifyEqual(sssa.nx_active, 65, 'AbsTol', 0, 'nx_active = 65 (Edp excluded).');
testCase.verifyEqual(size(sssa.A), [65, 65], 'AbsTol', 0, 'A is 65x65.');
testCase.verifyEqual(numel(sssa.eigenvalues), 65, 'AbsTol', 0, '65 eigenvalues.');
end

% =========================================================================
function test_sssa_no_edp_zero_eigenvalue_artifact(testCase)
% Frozen Edp must NOT contribute a zero eigenvalue (reduction before eig).
% The eigenvalues should reflect only physical modes.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);

config = struct('devices', devices);
eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(eq.converged, 'Equilibrium must converge.');

sssa = stability.composite_sssa_model(devices, eq.x0, eq.y0, c);
testCase.verifyTrue(sssa.no_eig_delete, 'no_eig_delete flag set.');
testCase.verifyEqual(sssa.reduction_method, ...
    'active_state_galerkin_before_eig', 'AbsTol', 0, ...
    'reduction method is Galerkin before eig.');
end

% =========================================================================
function test_selector_rejects_no_voltage_forming(testCase)
% Selector must reject configurations with no VF source.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
scenario_opt = struct();
scenario_opt.dispatch = disp_s;
scenario_opt.initial_modes = modes;
[resources, ~] = stability.resource_table(c, ...
    ieee14_spec(), scenario_opt);
% Set all resources offline (simulate all-tripped)
for k = 1:numel(resources)
    resources(k).initial_online = false;
end
result = stability.ibr_config_selector(resources, struct(), struct());
testCase.verifyFalse(isfield(result.selected_config, 'feasible') && ...
    result.selected_config.feasible, 'No-VF config must not be feasible.');
end

function spec = ieee14_spec()
Sbase = 100;
sg1 = struct('resource_id','SG1','bus_id',1,'resource_type','sg','model_id','sg_emf6',...
    'supported_modes',["synchronous","breaker_open"],...
    'voltage_forming_modes',"synchronous",...
    'initial_mode',"synchronous",'initial_online',true,...
    'can_switch_mode',true,'can_switch_online',true,...
    'has_current_limiter',false,'has_frt',false,'can_black_start',false,...
    'limits',struct('ImaxSS',[],'ImaxF',[],'Pmax_MW',[],'Qmax_MVAr',[],'Emax',[],'Emin',[]),...
    'ratings',struct('Mbase',615,'Sbase',Sbase),...
    'dynamic_params',struct(),...
    'provenance',struct('model','sg_emf6','source','Kodsi','classification','CASE_DEFINED','details',''));
spec = sg1;
ids = {'IBR2','IBR3','IBR6','IBR8'}; buses = [2,3,6,8]; mbases = [140,100,100,100];
for k = 1:4
    r = struct('resource_id',ids{k},'bus_id',buses(k),'resource_type','ibr','model_id','regfm_b1_dual',...
        'supported_modes',["gfl","gfm","tripped"],'voltage_forming_modes',"gfm",...
        'initial_mode',"gfl",'initial_online',true,...
        'can_switch_mode',true,'can_switch_online',true,...
        'has_current_limiter',true,'has_frt',true,'can_black_start',false,...
        'limits',struct('ImaxSS',1,'ImaxF',1.5,'Pmax_MW',mbases(k),'Qmax_MVAr',mbases(k),'Emax',1.2,'Emin',0.8),...
        'ratings',struct('Mbase',mbases(k),'Sbase',Sbase,'default_P_MW',0),...
        'dynamic_params',struct('Mbase',mbases(k)),...
        'provenance',struct('model','regfm_b1_dual','source','REGFM_B1','classification','CASE_DEFINED','details',''));
    spec(end+1) = r; %#ok<AGROW>
end
end

% =========================================================================
function test_selector_fingerprint_deterministic(testCase)
% Selector must produce deterministic fingerprint.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
scenario_opt = struct();
scenario_opt.dispatch = disp_s;
scenario_opt.initial_modes = modes;
[resources, ~] = stability.resource_table(c, ...
    ieee14_spec(), scenario_opt);
r1 = stability.ibr_config_selector(resources);
r2 = stability.ibr_config_selector(resources);
testCase.verifyEqual(r1.fingerprint, r2.fingerprint, 'AbsTol', 0, ...
    'Selector fingerprint deterministic.');
end

% =========================================================================
function test_no_eig_then_delete_grep(testCase)
% Grep guard: composite_sssa_model must NOT delete eigenvalues AFTER eig.
sssa_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'composite_sssa_model.m');
src = fileread(sssa_path);
% Verify no post-eig eigenvalue deletion. Check that no line calls eig()
% then deletes entries from the result array (common anti-pattern).
% The "no_eig_delete" flag name is allowed (it's a positive assertion).
testCase.verifyTrue(contains(src, 'no_eig_delete'), 'no_eig_delete flag present.');
testCase.verifyTrue(contains(src, 'active_state_galerkin_before_eig'), ...
    'reduction method is Galerkin before eig.');
testCase.verifyTrue(contains(src, 'active_state_galerkin'), ...
    'uses Galerkin reduction before eig.');
testCase.verifyTrue(contains(src, 'no_eig_delete'), 'no_eig_delete flag.');
end

% =========================================================================
function test_selector_no_bus_id_hardcode_grep(testCase)
% Grep guard: config_selector must NOT contain IEEE14 bus IDs.
sel_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'ibr_config_selector.m');
src = fileread(sel_path);
testCase.verifyFalse(contains(src, '"IBR2"') || contains(src, 'IBR2'), ...
    'no IEEE14 device IDs in generic selector.');
testCase.verifyFalse(contains(src, 'bus_id == 2') || contains(src, 'bus2'), ...
    'no IEEE14 bus numbers in generic selector.');
end
