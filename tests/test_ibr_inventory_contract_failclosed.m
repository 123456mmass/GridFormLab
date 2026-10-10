function tests = test_ibr_inventory_contract_failclosed()
%TEST_IBR_INVENTORY_CONTRACT_FAILCLOSED  IBR contract coverage + fail-closed.
%   Covers two gaps that the pre-existing 36 registry/inventory tests did NOT:
%     (1) the NE39 mixed case carries 5 grid-following/grid-forming EECON49
%         devices in their source_state (17-state) form, so the inventory must
%         report 5 x 17 = 85 IBR states with the DC-source current I_dc present
%         at device-local index 17 -- the 16-state registry branch cannot
%         certify this;
%     (2) an IBR-typed device that carries NO registered contract must FAIL
%         CLOSED in state_inventory_snapshot (never silently skipped), while a
%         non-IBR device (synchronous machine) is still a legitimate skip in
%         IBR_ONLY scope.
%   Nothing is relaxed: the real NE39 case, the real builder, and the real
%   equilibrium are used; the DC state is never dropped and the schema is not
%   widened.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, ...
    struct('devices',devices), struct('verbose',false));
dae = stability.composite_dae(s.case_data, devices, ...
    struct('full_kcl',true,'u_eq',eq.u_eq, ...
           'event_context',eq.equilibrium_context, ...
           'dynamic_state_indices',eq.dynamic_state_indices));
tc.TestData.s = s;
tc.TestData.eq = eq;
tc.TestData.dae = dae;
end

function test_ne39_5x17_inventory_carries_dc_state(tc)
% Five EECON49 devices, each 17 states, every I_dc present.
eq = tc.TestData.eq; dae = tc.TestData.dae;
snap = ibr.state_inventory_snapshot(dae, eq.dynamic_state_indices);
tc.verifyEqual(snap.counts.nx_total_ibr, 85);
tc.verifyEqual(snap.counts.nx_total_system, 95);
n_ibr_dev = 0;
for k = 1:numel(dae.devices)
    if startsWith(char(string(dae.devices(k).device_type)),'ibr_')
        n_ibr_dev = n_ibr_dev + 1;
    end
end
tc.verifyEqual(n_ibr_dev, 5);
names = {snap.state_rows.state_name};
tc.verifyEqual(sum(strcmp(names,'I_dc')), 5, ...
    'one DC-source current state per IBR must survive into the inventory');
end

function test_unknown_ibr_contract_fails_closed(tc)
% An IBR-typed device with no registered contract must raise, not vanish.
eq = tc.TestData.eq; d2 = tc.TestData.dae;
dev = d2.devices;
dev(1).device_type = 'ibr_unregistered_gizmo';
d2.devices = dev;
tc.verifyError(@() ibr.state_inventory_snapshot(d2, eq.dynamic_state_indices), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_non_ibr_sg_is_still_skipped(tc)
% A non-IBR device is a legitimate skip: the snapshot runs and simply reports
% one fewer IBR (4 x 17 = 68), never raising. The build order puts the five SGs
% first, so retype the FIRST IBR device into a non-IBR machine.
eq = tc.TestData.eq; d2 = tc.TestData.dae;
dev = d2.devices;
k_ibr = find(startsWith(string({dev.device_type}),'ibr_'), 1, 'first');
tc.assertNotEmpty(k_ibr);
dev(k_ibr).device_type = 'sg_emf6';   % looks like an SG, no IBR contract
d2.devices = dev;
snap = ibr.state_inventory_snapshot(d2, eq.dynamic_state_indices);
tc.verifyEqual(snap.counts.nx_total_ibr, 68);
end
